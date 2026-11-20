import Foundation

/// What Connect to Server accepts (S-037): smb, afp, nfs, WebDAV (http, https) and ftp
/// addresses. A bare name means SMB, and a Windows path (\\server\share) works too.
public enum ServerAddress {
    public static let schemes: Set<String> = ["smb", "afp", "nfs", "ftp", "http", "https"]

    /// The address to mount, or nil when it isn't one.
    public static func parse(_ text: String) -> URL? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("\\\\") {
            text = "smb://" + text.dropFirst(2).replacingOccurrences(of: "\\", with: "/")
        } else if !text.contains("://") {
            text = "smb://" + text
        }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), schemes.contains(scheme),
              let host = url.host(), !host.isEmpty else { return nil }
        return url
    }
}

/// The last servers connected to, newest first, at most ten, one entry per address.
public struct RecentServers: Equatable, Sendable {
    public static let limit = 10
    public private(set) var addresses: [String]

    public init(_ addresses: [String] = []) {
        self.addresses = Array(addresses.prefix(Self.limit))
    }

    public mutating func add(_ url: URL) {
        let address = url.absoluteString
        addresses.removeAll { $0.caseInsensitiveCompare(address) == .orderedSame }
        addresses.insert(address, at: 0)
        addresses = Array(addresses.prefix(Self.limit))
    }

    public mutating func remove(_ address: String) {
        addresses.removeAll { $0 == address }
    }
}
