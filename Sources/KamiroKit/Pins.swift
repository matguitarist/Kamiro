import CoreServices
import Foundation

/// The sidebar's Pinned folders, in the order people put them (S-032).
public struct PinList: Equatable, Sendable {
    public private(set) var urls: [URL]

    public init(_ urls: [URL]) {
        self.urls = []
        pin(urls)
    }

    public init(paths: [String]) {
        self.init(paths.map { URL(filePath: $0, directoryHint: .isDirectory) })
    }

    /// What is saved: one path per pin.
    public var paths: [String] { urls.map(\.path) }

    public func contains(_ url: URL) -> Bool { urls.contains(url.canonical) }

    /// Pins folders at `index` (the end when nil), skipping ones already pinned.
    /// Returns true when something was added.
    @discardableResult
    public mutating func pin(_ new: [URL], at index: Int? = nil) -> Bool {
        var position = min(max(index ?? urls.count, 0), urls.count)
        var added = false
        for url in new.map(\.canonical) where !urls.contains(url) {
            urls.insert(url, at: position)
            position += 1
            added = true
        }
        return added
    }

    public mutating func unpin(_ url: URL) {
        urls.removeAll { $0 == url.canonical }
    }

    /// Moves pins as a list's drag does: `destination` counts the rows before the moved ones are taken out.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.filter(urls.indices.contains).map { urls[$0] }
        let before = source.filter { $0 < destination }.count
        for index in source.sorted(by: >) where urls.indices.contains(index) { urls.remove(at: index) }
        urls.insert(contentsOf: moving, at: min(max(destination - before, 0), urls.count))
    }
}

/// The sidebar's parts people can hide (S-032).
public enum SidebarSection: String, CaseIterable, Sendable {
    case home, pinned, locations, tags
}

/// Files opened lately, for the Home page (S-031).
public enum RecentFiles {
    public static let limit = 20

    /// The newest `limit` of the items, by date.
    public static func newest(_ dated: [(url: URL, date: Date)], limit: Int = limit) -> [URL] {
        dated.sorted { $0.date > $1.date }.prefix(limit).map(\.url)
    }

    /// Files used in the last 30 days in the home folder, from Spotlight, newest first.
    public static func spotlight(limit: Int = limit) -> [URL] {
        let text = "kMDItemLastUsedDate >= $time.today(-30) && kMDItemContentTypeTree != \"public.folder\""
            + " && kMDItemContentTypeTree != \"com.apple.application\""
        guard let query = MDQueryCreate(kCFAllocatorDefault, text as CFString, nil, nil) else { return [] }
        MDQuerySetSearchScope(query, [kMDQueryScopeHome] as CFArray, 0)
        MDQuerySetMaxCount(query, 500)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        let library = URL.libraryDirectory.canonical.path + "/"
        let dated: [(url: URL, date: Date)] = (0..<MDQueryGetResultCount(query)).compactMap { index in
            guard let raw = MDQueryGetResultAtIndex(query, index) else { return nil }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String, !path.hasPrefix(library),
                  let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date else { return nil }
            return (URL(filePath: path).canonical, date)
        }
        return newest(dated, limit: limit)
    }

    /// The newest files of a tree by modification date (trees Spotlight doesn't index).
    public static func walk(in root: URL, limit: Int = limit) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                   options: [.skipsHiddenFiles, .skipsPackageDescendants])
        var dated: [(url: URL, date: Date)] = []
        while let url = files?.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let date = values.contentModificationDate else { continue }
            dated.append((url.canonical, date))
        }
        return newest(dated, limit: limit)
    }
}
