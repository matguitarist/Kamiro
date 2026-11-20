import Foundation
import Synchronization
import UniformTypeIdentifiers

extension URL {
    /// One spelling per file: standardized, no trailing slash, so a folder from a listing,
    /// a typed path, and a crumb compare equal.
    public var canonical: URL {
        URL(filePath: standardizedFileURL.path, directoryHint: .notDirectory)
    }
}

/// One file, folder, or package in a listing, read once from disk.
public struct FileItem: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    /// A folder people browse into. Packages (.app, .bundle) open as files.
    public let isFolder: Bool
    public let isPackage: Bool
    public let isHidden: Bool
    /// nil for folders and packages (their size is computed later, S-023).
    public let size: Int64?
    public let modified: Date?
    public let created: Date?
    /// Stays the same across a rename, so a renamed selected file stays selected.
    public let fileID: UInt64?

    public init(url: URL, name: String, isFolder: Bool, isPackage: Bool = false, isHidden: Bool = false,
                size: Int64? = nil, modified: Date? = nil, created: Date? = nil, fileID: UInt64? = nil) {
        self.url = url.canonical
        self.name = name
        self.isFolder = isFolder
        self.isPackage = isPackage
        self.isHidden = isHidden
        self.size = size
        self.modified = modified
        self.created = created
        self.fileID = fileID
    }
}

/// Why a folder can't be listed.
public enum FolderError: Error, Equatable, Sendable {
    /// macOS privacy (TCC) or file permissions keep it closed.
    case denied
    case missing
    case notFolder
    case other(String)

    public init(_ error: any Error) {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case CocoaError.Code.fileReadNoPermission.rawValue: self = .denied; return
            case CocoaError.Code.fileReadNoSuchFile.rawValue, CocoaError.Code.fileNoSuchFile.rawValue: self = .missing; return
            default: break
            }
        }
        let posix = ns.domain == NSPOSIXErrorDomain ? ns.code
            : (ns.userInfo[NSUnderlyingErrorKey] as? NSError).flatMap { $0.domain == NSPOSIXErrorDomain ? $0.code : nil }
        switch posix.map(Int32.init) {
        case EACCES, EPERM: self = .denied
        case ENOENT: self = .missing
        case ENOTDIR: self = .notFolder
        default: self = .other(ns.localizedDescription)
        }
    }
}

/// Reads folders. Only the keys that are cheap are asked up front: on 100,000 files they
/// take about 210 ms, while the kind adds 2 s and tags 1.4 s (docs/research, Benchmark).
public enum FolderReader {
    public static let keys: Set<URLResourceKey> = [
        .nameKey, .isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey,
        .fileSizeKey, .contentModificationDateKey, .creationDateKey, .fileIdentifierKey,
    ]

    public static func list(_ folder: URL, showHidden: Bool = false) throws(FolderError) -> [FileItem] {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: Array(keys), options: showHidden ? [] : [.skipsHiddenFiles])
        } catch {
            throw FolderError(error)
        }
        return urls.compactMap(item(at:))
    }

    public static func item(at url: URL) -> FileItem? {
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        var isDirectory = values.isDirectory ?? false
        var isPackage = values.isPackage ?? false
        if values.isSymbolicLink == true,
           let target = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) {
            isDirectory = target.isDirectory ?? false
            isPackage = target.isPackage ?? false
        }
        return FileItem(url: url, name: values.name ?? url.lastPathComponent,
                        isFolder: isDirectory && !isPackage, isPackage: isPackage,
                        isHidden: values.isHidden ?? false,
                        size: isDirectory ? nil : values.fileSize.map(Int64.init),
                        modified: values.contentModificationDate, created: values.creationDate,
                        fileID: values.fileIdentifier)
    }
}

/// The Kind column: one Launch Services lookup per extension, then from memory.
public final class KindCache: Sendable {
    public static let shared = KindCache()
    private let cache = Mutex<[String: String]>([:])

    public init() {}

    public func kind(of item: FileItem) -> String {
        if item.isFolder { return Self.folder }
        let ext = item.url.pathExtension.lowercased()
        let key = (item.isPackage ? "package:" : "") + ext
        if let hit = cache.withLock({ $0[key] }) { return hit }
        let type = ext.isEmpty ? nil : UTType(filenameExtension: ext, conformingTo: item.isPackage ? .package : .data)
        let name = Self.capitalized(type?.localizedDescription ?? (ext.isEmpty ? Self.document : ext.uppercased()))
        cache.withLock { $0[key] = name }
        return name
    }

    static let folder = capitalized(UTType.folder.localizedDescription ?? "Folder")
    static let document = UTType.content.localizedDescription ?? "Document"

    /// Some languages' kinds start in lowercase ("dossier"); the Finder shows "Dossier".
    static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}

public enum SortKey: String, Sendable, CaseIterable, Codable {
    case name, modified, size, kind
}

/// How a listing is sorted: Finder's name order ("2" before "10"), folders first.
public struct ItemOrder: Equatable, Sendable, Codable {
    public var key: SortKey
    public var ascending: Bool
    public var foldersFirst: Bool

    public init(key: SortKey = .name, ascending: Bool = true, foldersFirst: Bool = true) {
        self.key = key
        self.ascending = ascending
        self.foldersFirst = foldersFirst
    }

    public func sorted(_ items: [FileItem], kinds: KindCache = .shared) -> [FileItem] {
        let keyed = items.map { (item: $0, kind: key == .kind ? kinds.kind(of: $0) : "") }
        return keyed.sorted { a, b in
            if foldersFirst, a.item.isFolder != b.item.isFolder { return a.item.isFolder }
            let result: ComparisonResult = switch key {
            case .name: a.item.name.localizedStandardCompare(b.item.name)
            case .modified: Self.compare(a.item.modified ?? .distantPast, b.item.modified ?? .distantPast)
            case .size: Self.compare(a.item.size ?? -1, b.item.size ?? -1)
            case .kind: a.kind.localizedStandardCompare(b.kind)
            }
            if result == .orderedSame {
                return a.item.name.localizedStandardCompare(b.item.name) == .orderedAscending
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }.map(\.item)
    }

    private static func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
    }
}

/// The numbers under the list: items, the selection and its size, free space.
public struct StatusCounts: Equatable, Sendable {
    public let items: Int
    public let selected: Int
    /// The selected files' total, or nil when only folders are selected.
    public let selectedBytes: Int64?
    public let available: Int64?

    public init(items: [FileItem], selection: Set<URL>, available: Int64?) {
        self.items = items.count
        let chosen = items.filter { selection.contains($0.url) }
        selected = chosen.count
        let sizes = chosen.compactMap(\.size)
        selectedBytes = sizes.isEmpty ? nil : sizes.reduce(0, +)
        self.available = available
    }
}
