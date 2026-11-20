import Foundation

/// Back and forward through the folders one window visited.
public struct History: Equatable, Sendable {
    public private(set) var current: URL
    /// Oldest first; the last one is where Back goes.
    public private(set) var backList: [URL] = []
    /// Oldest first; the last one is where Forward goes.
    public private(set) var forwardList: [URL] = []
    public static let limit = 100

    public init(_ start: URL) { current = start.canonical }

    public var canGoBack: Bool { !backList.isEmpty }
    public var canGoForward: Bool { !forwardList.isEmpty }

    public mutating func go(to url: URL) {
        let target = url.canonical
        guard target != current else { return }
        backList.append(current)
        if backList.count > Self.limit { backList.removeFirst() }
        forwardList.removeAll()
        current = target
    }

    /// Goes back `steps` folders (the long-press menu jumps several); nil when it can't.
    /// Changes where the window is without a new Back step (a search's scope or filters).
    public mutating func replace(with url: URL) {
        current = url
    }

    @discardableResult
    public mutating func back(_ steps: Int = 1) -> URL? {
        guard steps >= 1, steps <= backList.count else { return nil }
        for _ in 0..<steps {
            forwardList.append(current)
            current = backList.removeLast()
        }
        return current
    }

    @discardableResult
    public mutating func forward(_ steps: Int = 1) -> URL? {
        guard steps >= 1, steps <= forwardList.count else { return nil }
        for _ in 0..<steps {
            backList.append(current)
            current = forwardList.removeLast()
        }
        return current
    }
}

/// What people type in the address bar.
public enum PathInput {
    /// "~", "~/Documents", "/Users", "Projects" (from the current folder), a quoted path,
    /// "My\\ Folder" from a terminal, or a file:// URL. nil for an empty field.
    public static func resolve(_ text: String, relativeTo current: URL, home: URL = .homeDirectory) -> URL? {
        var path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.count >= 2, let first = path.first, first == path.last, first == "\"" || first == "'" {
            path = String(path.dropFirst().dropLast())
        }
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("file://"), let url = URL(string: path), url.isFileURL { return url.canonical }
        path = path.replacingOccurrences(of: "\\ ", with: " ")
        if path == "~" { return home.canonical }
        if path.hasPrefix("~/") { return home.appending(path: String(path.dropFirst(2))).canonical }
        if path.hasPrefix("/") { return URL(filePath: path).canonical }
        return current.appending(path: path).canonical
    }

    /// The path as the field shows it: "~/Documents" inside the home folder.
    public static func display(_ url: URL, home: URL = .homeDirectory) -> String {
        let path = url.canonical.path
        let homePath = home.canonical.path
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
        return path
    }

    /// Folders that complete what's typed, as the field would show them ("~/Documents/").
    public static func completions(for text: String, relativeTo current: URL, home: URL = .homeDirectory,
                                   limit: Int = 12) -> [String] {
        guard !text.isEmpty else { return [] }
        let base: String
        let prefix: String
        if let slash = text.lastIndex(of: "/") {
            base = String(text[...slash])
            prefix = String(text[text.index(after: slash)...])
        } else {
            base = ""
            prefix = text == "~" ? "" : text
        }
        let parentText = base.isEmpty ? (text == "~" ? "~" : ".") : base
        guard let parent = resolve(parentText == "." ? current.path : parentText, relativeTo: current, home: home),
              let items = try? FolderReader.list(parent, showHidden: prefix.hasPrefix(".")) else { return [] }
        let start = text == "~" ? "~/" : base
        return items
            .filter { $0.isFolder && $0.name.lowercased().hasPrefix(prefix.lowercased()) }
            .map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .prefix(limit)
            .map { start + $0 + "/" }
    }

    /// The longest start every completion shares, for Tab.
    public static func commonPrefix(_ completions: [String]) -> String? {
        guard var common = completions.first else { return nil }
        for other in completions.dropFirst() {
            while !other.lowercased().hasPrefix(common.lowercased()) { common.removeLast() }
        }
        return common
    }
}

/// A folder or file shown in the address bar, split into the crumbs people click.
public struct Location: Hashable, Sendable {
    public let url: URL

    public init(_ url: URL) { self.url = url.canonical }

    /// Each folder from the root down to this one: "/", "/Users", "/Users/someone".
    public var crumbs: [URL] {
        var parts: [URL] = []
        var current = url
        while true {
            parts.append(current)
            guard let up = Location(current).parent else { break }
            current = up.url
        }
        return parts.reversed()
    }

    /// The folder that holds this one, or nil at the root. iCloud Drive and sync folders are a
    /// root, and an app's folder in iCloud Drive is in iCloud Drive (S-057).
    public var parent: Location? {
        guard url.path != "/" else { return nil }
        if let cloud = Cloud.parent(of: url) { return cloud.map(Location.init) }
        return Location(url.deletingLastPathComponent())
    }
}
