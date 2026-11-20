import CoreServices
import Foundation
import UniformTypeIdentifiers

/// A place the window shows that isn't a folder: the items with one tag (S-027). It travels as
/// a kamiro: URL, so history, views and the window's memory treat it like any folder.
public enum VirtualPlace: Hashable, Sendable {
    /// The Home page: pins, recent files and volumes (S-031).
    case home
    case tag(String)
    /// Search results (S-029).
    case search(Search)
    /// A file server's shares, like \\server on Windows (S-055).
    case server(URL)

    static let scheme = "kamiro"

    public init?(_ url: URL) {
        guard url.scheme == Self.scheme,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if parts.path == "home" {
            self = .home
            return
        }
        guard let query = parts.queryItems else { return nil }
        func value(_ key: String) -> String? { query.first { $0.name == key }?.value.flatMap { $0.isEmpty ? nil : $0 } }
        switch parts.path {
        case "tag":
            guard let name = value("name") else { return nil }
            self = .tag(name)
        case "server":
            guard let address = value("url"), let url = URL(string: address).flatMap(ServerHost.server(of:)) else { return nil }
            self = .server(url)
        case "search":
            guard let text = value("text") else { return nil }
            self = .search(Search(text: text, scope: value("in").map { URL(filePath: $0) },
                                  kind: value("kind").flatMap(SearchKind.init(rawValue:)) ?? .any,
                                  date: value("date").flatMap(SearchDate.init(rawValue:)) ?? .any))
        default:
            return nil
        }
    }

    public var url: URL {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        switch self {
        case .home:
            parts.path = "home"
        case .tag(let name):
            parts.path = "tag"
            parts.queryItems = [URLQueryItem(name: "name", value: name)]
        case .server(let url):
            parts.path = "server"
            parts.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        case .search(let search):
            parts.path = "search"
            parts.queryItems = [URLQueryItem(name: "text", value: search.text)]
                + (search.scope.map { [URLQueryItem(name: "in", value: $0.path)] } ?? [])
                + (search.kind == .any ? [] : [URLQueryItem(name: "kind", value: search.kind.rawValue)])
                + (search.date == .any ? [] : [URLQueryItem(name: "date", value: search.date.rawValue)])
        }
        return parts.url ?? URL(string: "kamiro:tag")!
    }

    public var title: String {
        switch self {
        case .home: "Home"
        case .tag(let name): name
        case .search(let search): search.text
        case .server(let url): ServerHost.displayName(url)
        }
    }

    /// What's in the place. `root` limits a tag to one folder tree, walked instead of asking
    /// Spotlight: for trees Spotlight doesn't index, like the test tree in /tmp.
    public func items(showHidden: Bool, root: URL? = nil) -> [FileItem] {
        switch self {
        case .home:
            // The Home page draws itself; it has no list.
            return []
        case .tag(let name):
            let urls = root.map { TagFinder.walk(name, in: $0) } ?? TagFinder.spotlight(name)
            return urls.compactMap(FolderReader.item(at:)).filter { showHidden || !$0.isHidden }
        case .search(let search):
            // Test runs walk the test tree, whatever the scope: Spotlight doesn't index /tmp.
            let urls = root.map { search.walk(in: search.scope ?? $0) } ?? search.spotlight()
            return urls.compactMap(FolderReader.item(at:)).filter { showHidden || !$0.isHidden }
        case .server(let url):
            return (try? ShareList.items(on: url, mounted: Volumes.mounted())) ?? []
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

/// What to look for when searching (S-029): words in the name, where, what kind, how recent.
public struct Search: Hashable, Sendable {
    public var text: String
    /// A folder and its subfolders, or nil for the whole Mac.
    public var scope: URL?
    public var kind: SearchKind
    public var date: SearchDate

    public init(text: String, scope: URL? = nil, kind: SearchKind = .any, date: SearchDate = .any) {
        self.text = text
        self.scope = scope?.canonical
        self.kind = kind
        self.date = date
    }

    static let limit = 2_000

    /// The Spotlight query: each word in the name, the kind, and the date.
    public func query(now: Date = .now) -> String {
        var parts = NameFilter.words(text).map { word in
            let escaped = word.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "*", with: "\\*")
            return "kMDItemFSName == \"*\(escaped)*\"cd"
        }
        if let type = kind.type { parts.append("kMDItemContentTypeTree == \"\(type)\"") }
        if let start = date.start(now: now) {
            parts.append("kMDItemFSContentChangeDate >= $time.iso(\(start.ISO8601Format()))")
        }
        return parts.isEmpty ? "kMDItemFSName == \"*\"" : parts.joined(separator: " && ")
    }

    /// Whether one item fits, for the walk (the same rules as the query).
    public func matches(name: String, contentType: UTType?, modified: Date?, now: Date = .now) -> Bool {
        guard NameFilter.matches(name, text) else { return false }
        if let type = kind.type {
            guard let contentType, contentType.conforms(to: UTType(type) ?? .item) else { return false }
        }
        if let start = date.start(now: now) {
            guard let modified, modified >= start else { return false }
        }
        return true
    }

    public func spotlight() -> [URL] {
        guard let query = MDQueryCreate(kCFAllocatorDefault, query() as CFString, nil, nil) else { return [] }
        let scopes: [Any] = scope.map { [$0.path] } ?? [kMDQueryScopeComputer as Any]
        MDQuerySetSearchScope(query, scopes as CFArray, 0)
        MDQuerySetMaxCount(query, Self.limit)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        return (0..<MDQueryGetResultCount(query)).compactMap { index in
            guard let raw = MDQueryGetResultAtIndex(query, index) else { return nil }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            return (MDItemCopyAttribute(item, kMDItemPath) as? String).map { URL(filePath: $0).canonical }
        }
    }

    /// Walks a tree (folders Spotlight doesn't index).
    public func walk(in root: URL, now: Date = .now) -> [URL] {
        let keys: [URLResourceKey] = [.contentTypeKey, .contentModificationDateKey]
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys)
        var found: [URL] = []
        while let url = files?.nextObject() as? URL, found.count < Self.limit {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if matches(name: url.lastPathComponent, contentType: values?.contentType, modified: values?.contentModificationDate, now: now) {
                found.append(url.canonical)
            }
        }
        return found
    }
}

public enum SearchKind: String, CaseIterable, Sendable {
    case any, folder, document, image, movie, audio, pdf, app

    /// The content type it stands for.
    var type: String? {
        switch self {
        case .any: nil
        case .folder: UTType.folder.identifier
        case .document: UTType.content.identifier
        case .image: UTType.image.identifier
        case .movie: UTType.movie.identifier
        case .audio: UTType.audio.identifier
        case .pdf: UTType.pdf.identifier
        case .app: UTType.application.identifier
        }
    }
}

public enum SearchDate: String, CaseIterable, Sendable {
    case any, today, week, month, year

    /// The earliest modification date that fits.
    public func start(now: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .any: return nil
        case .today: return today
        case .week: return calendar.date(byAdding: .day, value: -7, to: today)
        case .month: return calendar.date(byAdding: .day, value: -30, to: today)
        case .year: return calendar.date(from: calendar.dateComponents([.year], from: now))
        }
    }
}
