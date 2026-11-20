import Foundation

/// The last folders things were copied or moved into, newest first (S-046).
public struct RecentFolders: Equatable, Sendable {
    public static let limit = 8
    public private(set) var paths: [String]

    public init(_ paths: [String] = []) {
        self.paths = Array(paths.prefix(Self.limit))
    }

    public var urls: [URL] { paths.map { URL(filePath: $0, directoryHint: .isDirectory).canonical } }

    public mutating func add(_ url: URL) {
        let path = url.canonical.path
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        paths = Array(paths.prefix(Self.limit))
    }
}

/// Where Copy To and Move To can send the selection (S-046).
public enum Destinations {
    /// False for a folder the items are already in, one of the items, or a folder inside one.
    public static func allows(_ destination: URL, sources: [URL]) -> Bool {
        let destination = destination.canonical
        guard !sources.isEmpty else { return false }
        if sources.allSatisfy({ $0.deletingLastPathComponent().canonical == destination }) { return false }
        let path = destination.path
        return !sources.contains { source in
            let source = source.canonical.path
            return path == source || path.hasPrefix(source.hasSuffix("/") ? source : source + "/")
        }
    }

    /// Pinned folders, then recent ones that aren't pinned, leaving out what `allows` refuses
    /// and folders that are gone.
    public static func choices(pins: [URL], recents: [URL], sources: [URL],
                               exists: (URL) -> Bool) -> (pinned: [URL], recent: [URL]) {
        let pinned = pins.map(\.canonical).filter { exists($0) && allows($0, sources: sources) }
        let recent = recents.map(\.canonical).filter { !pinned.contains($0) && exists($0) && allows($0, sources: sources) }
        return (pinned, recent)
    }
}
