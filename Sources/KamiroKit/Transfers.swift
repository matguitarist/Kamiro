import Darwin
import Foundation
import ProcessKit
import Synchronization

public enum TransferKind: Sendable, Equatable {
    case copy, move
}

/// How far a transfer has come, in bytes counted before it starts.
public struct TransferProgress: Sendable, Equatable {
    public var totalBytes: Int64 = 0
    public var doneBytes: Int64 = 0
    public var totalItems = 0
    public var doneItems = 0
    public var current = ""

    public init() {}

    public var fraction: Double { totalBytes > 0 ? min(1, Double(doneBytes) / Double(totalBytes)) : (totalItems > 0 ? Double(doneItems) / Double(totalItems) : 0) }
}

/// A pasted or dropped item whose name is already used where it goes.
public struct Conflict: Sendable, Equatable {
    public let source: URL
    public let existing: URL
    /// Items still to come after this one, for "Apply to All".
    public let remaining: Int

    public init(source: URL, existing: URL, remaining: Int) {
        self.source = source.canonical
        self.existing = existing.canonical
        self.remaining = remaining
    }
}

public enum ConflictChoice: Sendable, Equatable {
    case replace, keepBoth, skip, stop
}

public struct ConflictAnswer: Sendable, Equatable {
    public let choice: ConflictChoice
    public let applyToAll: Bool

    public init(_ choice: ConflictChoice, applyToAll: Bool = false) {
        self.choice = choice
        self.applyToAll = applyToAll
    }
}

/// Set from any thread; the transfer stops at the next file, and a tool it runs stops at once.
public typealias CancelFlag = Shell.CancelFlag

public struct TransferOutcome: Sendable, Equatable {
    /// For Undo.
    public var change: FileChange = .batch([])
    /// Where the items are now, to select them.
    public var placed: [URL] = []
    public var cancelled = false
    public var failures: [String] = []
}

/// Copies and moves with progress, cancel, and conflict answers. Copies clone on APFS
/// (copyfile with COPYFILE_CLONE), so a copy on the same disk finishes at once.
public enum TransferEngine {
    /// Bytes and files under `urls`, counted before a transfer starts.
    public static func measure(_ url: URL) -> (bytes: Int64, files: Int) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return (0, 0) }
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            return (Int64(values.fileSize ?? 0), 1)
        }
        var bytes: Int64 = 0
        var files = 0
        let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys)
        while let child = walker?.nextObject() as? URL {
            guard let v = try? child.resourceValues(forKeys: Set(keys)), v.isDirectory != true else { continue }
            bytes += Int64(v.fileSize ?? 0)
            files += 1
        }
        return (bytes, files)
    }

    /// True when both are on the same volume, where a move is a rename.
    public static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let va = try? a.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
        let vb = try? b.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
        guard let va, let vb else { return false }
        return va.isEqual(vb)
    }

    /// Copies or moves `sources` into `destination`. `copyWord` names copies made in their own
    /// folder ("report copy.pdf"). `ask` answers name conflicts. `progress` runs on this task.
    @concurrent
    public static func run(
        _ kind: TransferKind, sources: [URL], into destination: URL, copyWord: String = "copy",
        trash: TrashCan = .system, cancel: CancelFlag = CancelFlag(),
        ask: @Sendable (Conflict) async -> ConflictAnswer = { _ in ConflictAnswer(.keepBoth) },
        progress: @Sendable (TransferProgress) -> Void = { _ in }
    ) async -> TransferOutcome {
        let files = FileManager.default
        let destination = destination.canonical
        let sources = sources.map(\.canonical)
        var outcome = TransferOutcome()
        var moves: [FileMove] = []
        var made: [URL] = []
        var replaced: [FileMove] = []
        var standing: ConflictChoice?

        let sizes = sources.map(measure)
        var state = TransferProgress()
        state.totalBytes = sizes.reduce(0) { $0 + $1.bytes }
        state.totalItems = sources.count
        progress(state)

        for (index, source) in sources.enumerated() {
            if cancel.isCancelled { outcome.cancelled = true; break }
            let isFolder = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let name = source.lastPathComponent
            var target = destination.appending(path: name)
            state.current = name
            progress(state)
            defer {
                state.doneItems += 1
                progress(state)
            }

            if source.deletingLastPathComponent().canonical == destination {
                // Pasting where it already is: a move does nothing, a copy makes "name copy".
                if kind == .move { state.doneBytes += sizes[index].bytes; outcome.placed.append(source); continue }
                target = destination.appending(path: Naming.copy(of: name, isFolder: isFolder, word: copyWord, in: destination))
            } else if destination.path == source.path || destination.path.hasPrefix(source.path + "/") {
                outcome.failures.append("\(name): a folder can't go inside itself")
                continue
            } else if files.fileExists(atPath: target.path) {
                let answer: ConflictAnswer
                if let standing {
                    answer = ConflictAnswer(standing)
                } else {
                    answer = await ask(Conflict(source: source, existing: target.canonical, remaining: sources.count - index - 1))
                }
                if answer.applyToAll { standing = answer.choice }
                switch answer.choice {
                case .skip:
                    state.doneBytes += sizes[index].bytes
                    continue
                case .stop:
                    outcome.cancelled = true
                case .keepBoth:
                    target = destination.appending(path: Naming.numbered(name, isFolder: isFolder, in: destination))
                case .replace:
                    do {
                        replaced.append(FileMove(from: target, to: try trash.put(target)))
                    } catch {
                        outcome.failures.append("\(name): \(error.localizedDescription)")
                        continue
                    }
                }
                if outcome.cancelled { break }
            }

            do {
                if kind == .move, sameVolume(source, destination) {
                    try files.moveItem(at: source, to: target)
                    moves.append(FileMove(from: source, to: target))
                    state.doneBytes += sizes[index].bytes
                } else {
                    let base = state.doneBytes
                    do {
                        try copyTree(source, to: target, cancel: cancel) { bytes in
                            state.doneBytes += bytes
                            progress(state)
                        }
                    } catch {
                        // Nothing half-copied stays behind.
                        try? files.removeItem(at: target)
                        state.doneBytes = base
                        throw error
                    }
                    if kind == .move {
                        try files.removeItem(at: source)
                        moves.append(FileMove(from: source, to: target))
                    } else {
                        made.append(target.canonical)
                    }
                }
                outcome.placed.append(target.canonical)
            } catch is CancellationError {
                outcome.cancelled = true
                break
            } catch {
                outcome.failures.append("\(name): \(error.localizedDescription)")
            }
        }
        outcome.change = .batch([.trashed(replaced), .moved(moves), .made(made)].filter { !$0.isEmpty })
        return outcome
    }

    /// Copies a file, link or folder tree, cloning where the disk can. Calls `copied` with
    /// each file's size. Throws CancellationError when cancelled between files.
    static func copyTree(_ source: URL, to target: URL, cancel: CancelFlag, copied: (Int64) -> Void) throws {
        if cancel.isCancelled { throw CancellationError() }
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        if values.isDirectory == true, values.isSymbolicLink != true {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            let children = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            for child in children {
                try copyTree(child, to: target.appending(path: child.lastPathComponent), cancel: cancel, copied: copied)
            }
            // Permissions, extended attributes and tags, once the folder is full.
            _ = copyfile(source.path, target.path, nil, copyfile_flags_t(COPYFILE_METADATA))
        } else {
            let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_CLONE | COPYFILE_NOFOLLOW | COPYFILE_EXCL)
            guard copyfile(source.path, target.path, nil, flags) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            copied(Int64(values.fileSize ?? 0))
        }
    }
}

/// Which way a drop goes: ⌥ copies, ⌘ moves, otherwise a move on the same disk and a copy
/// to another one, like the Finder.
public enum DropRule {
    public static func kind(sources: [URL], destination: URL, option: Bool, command: Bool) -> TransferKind {
        if option { return .copy }
        if command { return .move }
        return sources.allSatisfy { TransferEngine.sameVolume($0, destination) } ? .move : .copy
    }

    /// A drop that would do nothing: moving items into the folder they're already in,
    /// or a folder onto itself.
    public static func isNoOp(sources: [URL], destination: URL, kind: TransferKind) -> Bool {
        let destination = destination.canonical
        if sources.contains(where: { $0.canonical == destination }) { return true }
        return kind == .move && sources.allSatisfy { $0.deletingLastPathComponent().canonical == destination }
    }
}
