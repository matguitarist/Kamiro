import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// What a tile in the disk usage map holds (S-063), for its color.
public enum DiskCategory: String, CaseIterable, Sendable {
    case folder, pictures, movies, music, documents, apps, archives, code, other, smaller

    /// A file's category from its type; a package by what it is (an app, a photo library…).
    public static func of(_ url: URL, isPackage: Bool = false) -> DiskCategory {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return isPackage ? .documents : .other }
        if type.conforms(to: .application) || type.conforms(to: .applicationBundle) { return .apps }
        if type.conforms(to: .image) { return .pictures }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .movies }
        if type.conforms(to: .audio) { return .music }
        if type.conforms(to: .archive) || type.conforms(to: .diskImage) { return .archives }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) || type.conforms(to: .json)
            || type.conforms(to: .xml) { return .code }
        if type.conforms(to: .text) || type.conforms(to: .pdf) || type.conforms(to: .presentation)
            || type.conforms(to: .spreadsheet) || type.conforms(to: .content) || isPackage { return .documents }
        return .other
    }
}

/// One item in the disk usage map: a folder with what's inside it, a file, or a folder's
/// smallest files folded into one tile. Built once by DiskUsage.scan and never changed.
public struct DiskNode: Identifiable, Sendable {
    public let id: String
    public let url: URL
    public let name: String
    /// Size on disk, as FolderSize counts it.
    public let size: Int64
    /// Files and folders inside, at every depth; for the smaller-items tile, how many it holds.
    public let items: Int
    public let category: DiskCategory
    /// Biggest first. Empty for files, packages, and the smaller-items tile.
    public let children: [DiskNode]

    public var isFolder: Bool { category == .folder }
    public var isSmallerItems: Bool { category == .smaller }

    public init(url: URL, name: String, size: Int64, items: Int = 0, category: DiskCategory, children: [DiskNode] = []) {
        id = category == .smaller ? url.path + "/\u{0}smaller" : url.path
        self.url = url
        self.name = name
        self.size = size
        self.items = items
        self.category = category
        self.children = children
    }

    /// The node with this id, at any depth, and the folders on the way to it (self first).
    public func path(to id: String) -> [DiskNode]? {
        if self.id == id { return [self] }
        guard isFolder, id.hasPrefix(self.id == "/" ? "/" : self.id + "/") else { return nil }
        for child in children {
            if let rest = child.path(to: id) { return [self] + rest }
        }
        return nil
    }
}

/// Measures a folder for the disk usage map (S-063): the same count as FolderSize (allocated
/// size, hard links once, hidden files, other apps' containers left out), kept as a tree.
/// Stays on the folder's own disk, and keeps a folder's \(keptFiles) biggest files: the rest
/// become one "smaller items" tile, so a folder of a million files doesn't fill memory.
public enum DiskUsage {
    public static let keptFiles = 200

    public struct Progress: Sendable, Equatable {
        public var items = 0
        public var bytes: Int64 = 0
        public init(items: Int = 0, bytes: Int64 = 0) {
            self.items = items
            self.bytes = bytes
        }
    }

    static let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey,
                                         .fileAllocatedSizeKey, .linkCountKey, .fileIdentifierKey, .volumeIdentifierKey]

    /// Throws FolderError.denied when the folder can't be read, CancellationError when its task stops.
    /// `progress` is called now and then from the scanning thread.
    public static func scan(_ folder: URL, keep: Int = keptFiles,
                            progress: @escaping @Sendable (Progress) -> Void = { _ in }) throws -> DiskNode {
        guard let handle = opendir(folder.path) else { throw FolderError.denied }
        closedir(handle)
        let volume = try? folder.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
        var walker = Walker(volume: volume, keep: keep, progress: progress)
        let root = try walker.folder(folder.canonical, name: FileManager.default.displayName(atPath: folder.path))
        progress(walker.done)
        return root
    }

    private struct Walker {
        let volume: NSObject?
        let keep: Int
        let progress: @Sendable (Progress) -> Void
        var done = Progress()
        var linked: Set<UInt64> = []
        var sinceReport = 0

        init(volume: NSObject?, keep: Int, progress: @escaping @Sendable (Progress) -> Void) {
            self.volume = volume
            self.keep = keep
            self.progress = progress
        }

        mutating func folder(_ url: URL, name: String) throws -> DiskNode {
            let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [])) ?? []
            var folders: [DiskNode] = []
            var files: [DiskNode] = []
            var items = 0
            for found in contents {
                if Task.isCancelled { throw CancellationError() }
                guard let values = try? found.resourceValues(forKeys: Set(keys)) else { continue }
                // Named from the folder's own path, so every id starts with its folder's (the
                // listing can answer /private/tmp for /tmp).
                let child = url.appending(path: found.lastPathComponent, directoryHint: .notDirectory)
                count()
                items += 1
                let isDirectory = values.isDirectory == true && values.isSymbolicLink != true
                if isDirectory {
                    // Another disk mounted inside, or other apps' data: left out, as FolderSize does.
                    if let volume, let other = values.volumeIdentifier as? NSObject, !volume.isEqual(other) { continue }
                    if FolderSize.skipped.contains(child.canonical.path) { continue }
                    let inside = try folder(child, name: child.lastPathComponent)
                    items += inside.items
                    if values.isPackage == true {
                        files.append(DiskNode(url: child, name: child.lastPathComponent, size: inside.size, items: inside.items,
                                              category: DiskCategory.of(child, isPackage: true)))
                    } else {
                        folders.append(inside)
                    }
                    continue
                }
                if (values.linkCount ?? 1) > 1, let id = values.fileIdentifier, !linked.insert(id).inserted { continue }
                let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                done.bytes += size
                files.append(DiskNode(url: child, name: child.lastPathComponent, size: size, category: DiskCategory.of(child)))
            }
            files.sort { $0.size > $1.size }
            if files.count > keep + 1 {
                let rest = files[keep...]
                files = Array(files[..<keep])
                files.append(DiskNode(url: url, name: "", size: rest.reduce(0) { $0 + $1.size }, items: rest.count, category: .smaller))
            }
            let children = (folders + files).sorted { $0.size > $1.size }
            return DiskNode(url: url, name: name, size: children.reduce(0) { $0 + $1.size }, items: items,
                            category: .folder, children: children)
        }

        mutating func count() {
            done.items += 1
            sinceReport += 1
            if sinceReport >= 2_000 {
                sinceReport = 0
                progress(done)
            }
        }
    }
}

/// A tile of the map, in the view's points.
public struct DiskTile: Sendable {
    public let node: DiskNode
    public let rect: CGRect
    /// 0 for the shown folder's own items, 1 inside them, and so on.
    public let depth: Int
    /// A folder drawn with its items inside it, under a title strip.
    public let isOpen: Bool
}

/// Squarified treemap (Bruls, Huizing and van Wijk): tiles in proportion to their sizes,
/// as close to square as the order allows.
public enum Treemap {
    /// One rect per size, in the same order. Sizes of zero or less get an empty rect.
    public static func layout(_ sizes: [Double], in bounds: CGRect) -> [CGRect] {
        var result = Array(repeating: CGRect.zero, count: sizes.count)
        let total = sizes.reduce(0) { $0 + max($1, 0) }
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return result }
        let scale = Double(bounds.width * bounds.height) / total
        let order = sizes.indices.filter { sizes[$0] > 0 }.sorted { sizes[$0] > sizes[$1] }
        var rest = bounds
        var row: [Int] = []
        var rowArea = 0.0
        func area(_ index: Int) -> Double { sizes[index] * scale }
        func worst(_ sum: Double, _ smallest: Double, _ largest: Double, side: Double) -> Double {
            let side2 = side * side, sum2 = sum * sum
            return max(side2 * largest / sum2, sum2 / (side2 * smallest))
        }
        func place(last: Bool) {
            guard !row.isEmpty else { return }
            let horizontal = rest.width >= rest.height
            // The row runs along the short side; the last row takes what's left exactly.
            let thickness = last ? (horizontal ? rest.width : rest.height)
                : CGFloat(rowArea / Double(horizontal ? rest.height : rest.width))
            var offset: CGFloat = 0
            let length = horizontal ? rest.height : rest.width
            for (n, index) in row.enumerated() {
                let span = n == row.count - 1 ? length - offset : CGFloat(area(index) / rowArea) * length
                result[index] = horizontal
                    ? CGRect(x: rest.minX, y: rest.minY + offset, width: thickness, height: span)
                    : CGRect(x: rest.minX + offset, y: rest.minY, width: span, height: thickness)
                offset += span
            }
            if horizontal {
                rest = CGRect(x: rest.minX + thickness, y: rest.minY, width: max(rest.width - thickness, 0), height: rest.height)
            } else {
                rest = CGRect(x: rest.minX, y: rest.minY + thickness, width: rest.width, height: max(rest.height - thickness, 0))
            }
            row = []
            rowArea = 0
        }
        var i = 0
        while i < order.count {
            let index = order[i]
            let side = Double(min(rest.width, rest.height))
            let next = area(index)
            if row.isEmpty {
                row = [index]
                rowArea = next
                i += 1
                continue
            }
            // Sorted biggest first: the row's largest is its first, its smallest the newcomer.
            let largest = area(row[0]), smallest = area(row[row.count - 1])
            if worst(rowArea + next, next, largest, side: side) <= worst(rowArea, smallest, largest, side: side) {
                row.append(index)
                rowArea += next
                i += 1
            } else {
                place(last: false)
            }
        }
        place(last: true)
        return result
    }

    /// The tiles for a folder's items in `bounds`, folders opened up to `depth` levels when
    /// there's room, a `header`-tall title strip on each open folder. Tiles under `minimum`
    /// points on a side are left out.
    public static func tiles(for folder: DiskNode, in bounds: CGRect, depth: Int = 3, header: CGFloat = 16,
                             inset: CGFloat = 2, minimum: CGFloat = 2) -> [DiskTile] {
        var out: [DiskTile] = []
        func add(_ node: DiskNode, children: [DiskNode], in box: CGRect, level: Int) {
            let rects = layout(children.map { Double($0.size) }, in: box)
            for (child, rect) in zip(children, rects) where rect.width >= minimum && rect.height >= minimum {
                let roomy = rect.width >= 40 && rect.height >= header + 20
                let open = child.isFolder && !child.children.isEmpty && level + 1 < depth && roomy
                out.append(DiskTile(node: child, rect: rect, depth: level, isOpen: open))
                if open {
                    let inner = CGRect(x: rect.minX + inset, y: rect.minY + header, width: rect.width - inset * 2,
                                       height: rect.height - header - inset)
                    add(child, children: child.children, in: inner, level: level + 1)
                }
            }
        }
        add(folder, children: folder.children, in: bounds, level: 0)
        return out
    }
}
