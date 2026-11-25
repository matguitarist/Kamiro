import Foundation
import ProcessKit
import Synchronization

/// A file server found on the local network with Bonjour, for the sidebar's Network section.
public struct NetworkServer: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case smb, afp }

    public let name: String
    public let kind: Kind
    public var id: String { name }

    public init(name: String, kind: Kind) {
        self.name = name
        self.kind = kind
    }

    /// The Bonjour name as an address NetFS mounts, like the Finder: smb://HomeServer._smb._tcp.local
    /// Names with spaces or accents are percent-encoded, as URLComponents won't take them in a host.
    public var url: URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let host = "\(name).\(kind == .smb ? "_smb._tcp" : "_afpovertcp._tcp").local"
        return host.addingPercentEncoding(withAllowedCharacters: allowed).flatMap { URL(string: "\(kind.rawValue)://\($0)") }
    }

    /// One entry per name, SMB first when a server offers both, sorted like the Finder.
    public static func merged(smb: [String], afp: [String]) -> [NetworkServer] {
        var seen = Set<String>()
        let all = smb.map { NetworkServer(name: $0, kind: .smb) } + afp.map { NetworkServer(name: $0, kind: .afp) }
        return all.filter { seen.insert($0.name.lowercased()).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// One server, whatever spelling reached it: "HomeServer._smb._tcp.local", "homeserver.local"
/// and "HomeServer" are the same machine.
public enum ServerHost {
    public static func key(_ host: String) -> String {
        var host = host.lowercased()
        while host.hasSuffix(".") { host.removeLast() }
        for suffix in ["._smb._tcp.local", "._afpovertcp._tcp.local", ".local"] where host.hasSuffix(suffix) {
            host.removeLast(suffix.count)
            break
        }
        return host
    }

    /// "HomeServer" for smb://HomeServer._smb._tcp.local, the host itself otherwise.
    public static func displayName(_ url: URL) -> String {
        let host = url.host(percentEncoded: false) ?? url.absoluteString
        for suffix in ["._smb._tcp.local", "._afpovertcp._tcp.local", ".local"] where host.lowercased().hasSuffix(suffix) {
            return String(host.dropLast(suffix.count))
        }
        return host
    }

    /// smb://HomeServer._smb._tcp.local, without a user, a share or a slash.
    public static func server(of url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), ["smb", "afp"].contains(scheme),
              let host = url.host(percentEncoded: true), !host.isEmpty else { return nil }
        return URL(string: "\(scheme)://\(host)")
    }

    /// The share named in an address (smb://server/isos → "isos"), nil for a server alone.
    public static func share(of url: URL) -> String? {
        let first = url.path(percentEncoded: false).split(separator: "/").first.map(String.init)
        return first?.isEmpty == false ? first : nil
    }

    public static func same(_ a: URL, _ b: URL) -> Bool {
        guard let one = a.host(percentEncoded: false), let two = b.host(percentEncoded: false) else { return false }
        return key(one) == key(two)
    }
}

/// The shares a server offers, from macOS's own `smbutil view`: as guest, or with the password
/// the keychain or an open session already has. Never asks.
public enum ShareList {
    public struct Share: Hashable, Sendable {
        public let name: String
        public let comment: String
    }

    public enum Failure: Error, Equatable { case unreachable(String) }

    /// For the self-test: a server's shares without asking the network.
    public static let fake = Mutex<[String]?>(nil)

    /// Disk shares only; IPC$ and the hidden admin shares (ending in $) are left out.
    public static func parse(_ output: String) -> [Share] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let text = String(line)
            guard let range = text.range(of: #"\s{2,}Disk(\s+|$)"#, options: .regularExpression) else { return nil }
            let name = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let comment = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return name.isEmpty || name.hasSuffix("$") ? nil : Share(name: name, comment: comment)
        }
    }

    /// The ways `smbutil view` is tried, in order: the keychain's password on the open session;
    /// a new session (just after a disconnect the old one can refuse, "Authentication error");
    /// then as guest.
    public static let attempts: [[String]] = [["-N"], ["-N", "-f"], ["-N", "-f", "-g"]]

    /// The server's shares, or why they can't be listed (a password it doesn't have, no answer).
    public static func shares(on server: URL,
                              run: (_ options: [String], _ host: String) throws -> String = runSMBUtil) throws -> [Share] {
        if let names = fake.withLock({ $0 }) { return names.map { Share(name: $0, comment: "") } }
        guard server.scheme?.lowercased() == "smb", let host = server.host(percentEncoded: false) else {
            throw Failure.unreachable("Only SMB servers can list their shares.")
        }
        var last: (any Error)?
        for options in attempts {
            do { return parse(try run(options, host)) } catch { last = error }
        }
        throw last ?? Failure.unreachable(host)
    }

    /// One `smbutil view`; throws with its message when it fails.
    public static func runSMBUtil(_ options: [String], host: String) throws -> String {
        let output: Shell.Output
        do {
            // A server that doesn't answer gives up after 15 seconds.
            output = try Shell.runSync("/usr/bin/smbutil", ["view"] + options + ["//\(host)"],
                                       options: Shell.Options(stderr: .merged, timeout: .seconds(15)))
        } catch ShellError.timedOut(let partial) {
            output = partial
        }
        guard output.succeeded else {
            throw Failure.unreachable(output.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output.text
    }

    /// The server page's items: each share a folder, the mounted ones at their place in /Volumes.
    public static func items(on server: URL, mounted: [Volume]) throws -> [FileItem] {
        try shares(on: server).map { share in
            let volume = mounted.first { volume in
                volume.remoteURL.map { ServerHost.same($0, server) && ServerHost.share(of: $0)?.lowercased() == share.name.lowercased() } ?? false
            }
            let url = volume?.url ?? server.appending(path: share.name)
            return FileItem(url: url, name: share.name, isFolder: true)
        }
    }
}
