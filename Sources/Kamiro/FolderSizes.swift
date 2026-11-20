import Foundation
import KamiroKit

/// The sizes of a folder's subfolders and packages (S-023), measured one at a time off the
/// main thread. Starting on another folder stops the measuring; an FSEvents watch on the tree
/// measures a subfolder again when something inside it changes.
@MainActor @Observable
final class FolderSizes {
    /// Sizes measured so far; folders not in it show "—".
    private(set) var sizes: [URL: Int64] = [:]
    /// Goes up as sizes arrive, so the list redraws its Size column.
    private(set) var version = 0
    var isMeasuring: Bool { task != nil }
    /// Called after each new size.
    @ObservationIgnored var arrived: () -> Void = {}

    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private var items: () -> [FileItem] = { [] }
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var run = 0
    @ObservationIgnored private var waiting: [URL] = []
    @ObservationIgnored private var watcher: TreeWatcher?

    /// Forgets the old folder's sizes and watches `folder`; `items` gives what's on screen.
    func start(in folder: URL, items: @escaping () -> [FileItem]) {
        task?.cancel()
        task = nil
        waiting = []
        sizes = [:]
        version += 1
        self.folder = folder
        self.items = items
        watcher = TreeWatcher(folder: folder) { [weak self] paths in
            Task { @MainActor in self?.changed(paths) }
        }
    }

    /// Adds folders to the queue.
    func measure(_ urls: [URL]) {
        waiting += urls.filter { !waiting.contains($0) }
        guard task == nil, !waiting.isEmpty, let folder else { return }
        run += 1
        let current = run
        task = Task { [weak self] in
            defer { if self?.run == current { self?.task = nil } }
            while let self, !Task.isCancelled, !waiting.isEmpty {
                let next = waiting.removeFirst()
                let measured = await Self.size(of: next)
                guard !Task.isCancelled, self.folder == folder else { break }
                // A folder that can't be read keeps its "—".
                guard case .success(let size) = measured else { continue }
                sizes[next] = size
                version += 1
                arrived()
            }
        }
    }

    @concurrent
    nonisolated private static func size(of url: URL) async -> Result<Int64, any Error> {
        Result { try FolderSize.measure(url) }
    }

    /// Something changed inside a subfolder: measure that subfolder again.
    private func changed(_ paths: [String]) {
        guard let watcher else { return }
        let names = Set(paths.compactMap(watcher.child(holding:)))
        let changed = items().filter { ($0.isFolder || $0.isPackage) && names.contains($0.name) }.map(\.url)
        measure(changed)
    }
}
