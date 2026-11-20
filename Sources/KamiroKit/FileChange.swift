import Foundation

/// Where trashed items go: the real Trash, or a folder in /tmp for tests and the self-test.
public struct TrashCan: Sendable {
    public let folder: URL?

    public static let system = TrashCan(folder: nil)
    public static func folder(_ url: URL) -> TrashCan { TrashCan(folder: url) }

    /// Moves `url` to the Trash and returns where it went, so it can be put back.
    public func put(_ url: URL) throws -> URL {
        if let folder {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let target = folder.appending(path: Naming.free(url.lastPathComponent, isFolder: isFolder, in: folder))
            try FileManager.default.moveItem(at: url, to: target)
            return target.canonical
        }
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return (result as URL?)?.canonical ?? url
    }
}

/// One item moved or renamed.
public struct FileMove: Hashable, Sendable {
    public let from: URL
    public let to: URL

    public init(from: URL, to: URL) {
        self.from = from.canonical
        self.to = to.canonical
    }

    public var reversed: FileMove { FileMove(from: to, to: from) }
}

/// What a file action changed on disk, kept for Undo. Everything reduces to moves and
/// trashing: undoing a copy trashes it, undoing a trash moves the item back.
public indirect enum FileChange: Equatable, Sendable {
    /// Moved or renamed.
    case moved([FileMove])
    /// Made by a copy, New Folder or New File.
    case made([URL])
    /// Sent to the Trash: `from` is where it was, `to` where it is now.
    case trashed([FileMove])
    /// Several changes in the order they happened.
    case batch([FileChange])

    public var isEmpty: Bool {
        switch self {
        case .moved(let list), .trashed(let list): list.isEmpty
        case .made(let list): list.isEmpty
        case .batch(let list): list.allSatisfy(\.isEmpty)
        }
    }

    /// Reverses this change on disk and returns what was done, whose own undo is the Redo.
    public func undo(trash: TrashCan) throws -> FileChange {
        let files = FileManager.default
        switch self {
        case .moved(let moves):
            var done: [FileMove] = []
            for move in moves.reversed() {
                try files.moveItem(at: move.to, to: move.from)
                done.append(move.reversed)
            }
            return .moved(done)
        case .made(let urls):
            var done: [FileMove] = []
            for url in urls.reversed() {
                done.append(FileMove(from: url, to: try trash.put(url)))
            }
            return .trashed(done)
        case .trashed(let moves):
            var done: [FileMove] = []
            for move in moves.reversed() {
                try files.moveItem(at: move.to, to: move.from)
                done.append(move.reversed)
            }
            return .moved(done)
        case .batch(let changes):
            var done: [FileChange] = []
            for change in changes.reversed() where !change.isEmpty {
                done.append(try change.undo(trash: trash))
            }
            return .batch(done)
        }
    }
}
