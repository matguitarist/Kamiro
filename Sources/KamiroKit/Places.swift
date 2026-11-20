import CoreServices
import Foundation

/// A place the window shows that isn't a folder: the items with one tag (S-027). It travels as
/// a kamiro: URL, so history, views and the window's memory treat it like any folder.
public enum VirtualPlace: Hashable, Sendable {
    case tag(String)

    static let scheme = "kamiro"

    public init?(_ url: URL) {
        guard url.scheme == Self.scheme,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.path == "tag",
              let name = parts.queryItems?.first(where: { $0.name == "name" })?.value, !name.isEmpty else { return nil }
        self = .tag(name)
    }

    public var url: URL {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        switch self {
        case .tag(let name):
            parts.path = "tag"
            parts.queryItems = [URLQueryItem(name: "name", value: name)]
        }
        return parts.url ?? URL(string: "kamiro:tag")!
    }

    public var title: String {
        switch self {
        case .tag(let name): name
        }
    }

    /// What's in the place. `root` limits a tag to one folder tree, walked instead of asking
    /// Spotlight: for trees Spotlight doesn't index, like the test tree in /tmp.
    public func items(showHidden: Bool, root: URL? = nil) -> [FileItem] {
        switch self {
        case .tag(let name):
            let urls = root.map { TagFinder.walk(name, in: $0) } ?? TagFinder.spotlight(name)
            return urls.compactMap(FolderReader.item(at:)).filter { showHidden || !$0.isHidden }
        }
    }
}

/// Finder tags on items (S-027).
public enum Tags {
    public static func of(_ url: URL) -> [String] {
        (try? url.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
    }

    /// Adds or removes one tag on every item, keeping their other tags.
    public static func set(_ tag: String, present: Bool, on urls: [URL]) throws {
        for url in urls {
            var names = of(url).filter { $0 != tag }
            if present { names.append(tag) }
            try (url as NSURL).setResourceValue(names, forKey: .tagNamesKey)
        }
    }
}

/// Finds items with a tag.
public enum TagFinder {
    static let limit = 5_000

    /// The Spotlight query for a tag, with quotes and backslashes in the name escaped.
    public static func query(for tag: String) -> String {
        let escaped = tag.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "kMDItemUserTags == \"\(escaped)\""
    }

    /// Everything Spotlight knows with this tag, on this Mac.
    public static func spotlight(_ tag: String) -> [URL] {
        guard let query = MDQueryCreate(kCFAllocatorDefault, query(for: tag) as CFString, nil, nil) else { return [] }
        MDQuerySetSearchScope(query, [kMDQueryScopeComputer] as CFArray, 0)
        MDQuerySetMaxCount(query, limit)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        return (0..<MDQueryGetResultCount(query)).compactMap { index in
            guard let raw = MDQueryGetResultAtIndex(query, index) else { return nil }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            return (MDItemCopyAttribute(item, kMDItemPath) as? String).map { URL(filePath: $0).canonical }
        }
    }

    /// Walks a tree for the tag (folders Spotlight doesn't index).
    public static func walk(_ tag: String, in root: URL) -> [URL] {
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.tagNamesKey])
        var found: [URL] = []
        while let url = files?.nextObject() as? URL, found.count < limit {
            if Tags.of(url).contains(tag) { found.append(url.canonical) }
        }
        return found
    }
}
