import AppKit
import KamiroKit
import os

/// The disk usage map's state (S-063): measures a folder off the main thread, then keeps the
/// tree, the folders zoomed into, and the selected tile.
@MainActor @Observable
final class DiskUsageModel {
    enum State: Equatable { case measuring, ready, denied, stopped }

    let folder: URL
    private(set) var state: State = .measuring
    private(set) var progress = DiskUsage.Progress()
    private(set) var root: DiskNode?
    /// The folders from the measured one to the one on screen.
    private(set) var trail: [DiskNode] = []
    /// The selected tile or row, by node id.
    var selection: String?
    /// The tile under the pointer; the footer names it and its right-click menu acts on it.
    var hovered: DiskNode?
    /// Opens a browser window when none is open; set by the window.
    @ObservationIgnored var openBrowser: ((WindowStart) -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?

    /// The last one opened, for the self-test.
    static weak var latest: DiskUsageModel?

    init(folder: URL) {
        self.folder = folder
    }

    var shown: DiskNode? { trail.last }
    var selected: DiskNode? { selection.flatMap { root?.path(to: $0)?.last } }

    func start() {
        task?.cancel()
        state = .measuring
        progress = DiskUsage.Progress()
        let folder = folder
        let box = ProgressBox()
        let keep = trail.last?.id
        task = Task { [weak self] in
            let poll = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    self?.progress = box.value
                }
            }
            let result = await Self.scan(folder, box: box)
            poll.cancel()
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let node):
                root = node
                progress = box.value
                // Measuring again keeps the folder that was on screen when it's still there.
                trail = keep.flatMap { node.path(to: $0) } ?? [node]
                state = .ready
            case .failure(let error):
                state = error is CancellationError ? .stopped : .denied
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if state == .measuring { state = .stopped }
    }

    @concurrent
    nonisolated private static func scan(_ folder: URL, box: ProgressBox) async -> Result<DiskNode, any Error> {
        Result { try DiskUsage.scan(folder) { box.value = $0 } }
    }

    // MARK: Zooming

    /// A folder fills the map; a file zooms to the folder it's in.
    func zoom(into node: DiskNode) {
        guard let root, let path = root.path(to: node.id) else { return }
        let folders = path.filter(\.isFolder)
        guard folders.count > 1 || node.isFolder else { return }
        trail = folders
        hovered = nil
    }

    func zoomOut() {
        guard trail.count > 1 else { return }
        let left = trail.removeLast()
        selection = left.id
        hovered = nil
    }

    func zoom(toLevel index: Int) {
        guard trail.indices.contains(index) else { return }
        trail = Array(trail.prefix(index + 1))
        hovered = nil
    }

    // MARK: Actions

    /// Shows the item selected in the front browser window: a folder's contents, a file in its
    /// folder, the smaller-items tile as its folder.
    func showInBrowser(_ node: DiskNode, openFolder: Bool = false) {
        let target = node.isSmallerItems || (openFolder && node.isFolder) ? node.url : node.url.deletingLastPathComponent()
        let select: Set<URL> = target == node.url ? [] : [node.url.canonical]
        if let browser = MenuState.shared.browser {
            browser.go(to: target, select: select)
            browser.details?.table?.window?.makeKeyAndOrderFront(nil)
        } else {
            openBrowser?(WindowStart(url: target, select: select.first))
        }
    }

    func open(_ node: DiskNode) {
        if node.isFolder || node.isSmallerItems {
            showInBrowser(node, openFolder: true)
        } else {
            NSWorkspace.shared.open(node.url)
        }
    }

    func copyPath(_ node: DiskNode) {
        ItemActions.copyPaths([node.url])
    }
}

/// The scan's running count, written by the scanning thread and read by the window.
nonisolated final class ProgressBox: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: DiskUsage.Progress())
    var value: DiskUsage.Progress {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }
}

/// Shared bits of Show Disk Usage for the menus.
enum DiskUsageActions {
    static let symbol = "square.split.2x2"
}
