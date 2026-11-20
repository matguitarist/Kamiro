import Foundation

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
