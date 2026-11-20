import Foundation

/// A folder or file shown in the address bar, split into the crumbs people click.
public struct Location: Hashable, Sendable {
    public let url: URL

    public init(_ url: URL) { self.url = url.standardizedFileURL }

    /// Each folder from the root down to this one: "/", "Users", "mathieu", "Documents".
    public var crumbs: [URL] {
        var parts: [URL] = []
        var current = url
        while true {
            parts.append(current)
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { break }
            current = parent
        }
        return parts.reversed()
    }

    /// The folder that holds this one, or nil at the root.
    public var parent: Location? {
        let up = url.deletingLastPathComponent().standardizedFileURL
        return up.path == url.path ? nil : Location(up)
    }
}
