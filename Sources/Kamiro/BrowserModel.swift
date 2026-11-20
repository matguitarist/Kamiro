import AppKit
import KamiroKit
import LogKitUI
import Observation

enum LoadState: Equatable {
    case loading, ready
    case failed(FolderError)
}

/// One window's folder: where it is, what's in it, what's selected, and the address bar.
@Observable
final class BrowserModel {
    private(set) var history: History
    private(set) var items: [FileItem] = []
    /// Goes up each time `items` changes, so the table reloads only then.
    private(set) var itemsVersion = 0
    var selection: Set<URL> = [] {
        didSet { if selection != oldValue { publish() } }
    }
    private(set) var state: LoadState = .loading
    /// Shown only when a folder takes more than half a second.
    private(set) var showsLoading = false
    var order = ItemOrder() {
        didSet { if order != oldValue { resort() } }
    }
    private(set) var available: Int64?
    /// The table scrolls to the selection when this changes.
    private(set) var revealToken = 0
    /// The table takes the keyboard when this changes.
    private(set) var focusToken = 0

    // The address bar.
    var isEditingPath = false
    var pathText = ""
    var pathError: String?
    private(set) var shakeToken = 0

    // File actions (FileActions.swift).
    /// The list starts renaming `renameTarget` when this changes.
    var renameToken = 0
    var renameTarget: URL?
    /// Name conflicts waiting for an answer, first one shown.
    var conflicts: [ConflictQuestion] = []
    /// Items waiting for "Delete Immediately?".
    var pendingDelete: [URL]?
    var pendingExtension: ExtensionQuestion?
    /// The list, for the self-test (spring-loaded folders, rename).
    @ObservationIgnored weak var details: DetailsCoordinator?

    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var remembered: [URL: Set<URL>] = [:]
    @ObservationIgnored private var started = false
    /// Opens a folder in a new window (set by the window's view).
    @ObservationIgnored var openWindow: ((URL) -> Void)?
    /// Shows or hides Quick Look (set by the table).
    @ObservationIgnored var quickLook: (() -> Void)?
    @ObservationIgnored let log: LogStore

    init(start: URL, log: LogStore) {
        history = History(start)
        self.log = log
    }

    var folder: URL { history.current }
    var title: String { FileManager.default.displayName(atPath: folder.path) }
    var selectedItems: [FileItem] { items.filter { selection.contains($0.url) } }
    var canGoUp: Bool { Location(folder).parent != nil }
    var isFailed: Bool { if case .failed = state { true } else { false } }
    var counts: StatusCounts { StatusCounts(items: items, selection: selection, available: available) }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        load(select: [])
    }

    // MARK: Going places

    func go(to url: URL, select: Set<URL> = []) {
        let target = url.canonical
        let wanted = Set(select.map(\.canonical))
        guard target != folder else {
            if !wanted.isEmpty { selection = wanted; revealToken += 1 }
            return
        }
        remembered[folder] = selection
        history.go(to: target)
        load(select: wanted)
    }

    func goBack(_ steps: Int = 1) {
        let from = folder
        guard history.back(steps) != nil else { return }
        remembered[from] = selection
        load(select: remembered[folder] ?? [])
    }

    func goForward(_ steps: Int = 1) {
        let from = folder
        guard history.forward(steps) != nil else { return }
        remembered[from] = selection
        load(select: remembered[folder] ?? [])
    }

    /// Up to the enclosing folder, with the folder we came from selected.
    func goUp() {
        guard let parent = Location(folder).parent else { return }
        go(to: parent.url, select: [folder])
    }

    /// Opens the selection (or `urls`): one folder opens here, files open in their apps.
    func open(_ urls: [URL]? = nil, newWindow: Bool = false) {
        let targets = urls.map { list in list.compactMap { url in items.first { $0.url == url.canonical } } } ?? selectedItems
        let folders = targets.filter(\.isFolder)
        let files = targets.filter { !$0.isFolder }
        if !newWindow, folders.count == 1, files.isEmpty {
            go(to: folders[0].url)
        } else {
            folders.forEach { openWindow?($0.url) }
        }
        for file in files { NSWorkspace.shared.open(file.url) }
    }

    /// Return renames, like the Finder; with Settings › General › "Return opens items" on, it opens.
    func handleReturn() -> Bool {
        guard !selection.isEmpty else { return false }
        if Prefs.defaults.bool(forKey: Prefs.returnOpensItems) { open() } else { beginRename() }
        return true
    }

    func refresh() { load(select: nil) }

    /// Reads the folder again and selects `urls`, without clearing the list first.
    func reload(selecting urls: Set<URL>) { load(select: Set(urls.map(\.canonical)), clear: false) }

    func focusList() { focusToken += 1 }

    // MARK: The address bar

    func beginEditingPath() {
        pathText = PathInput.display(folder)
        pathError = nil
        isEditingPath = true
    }

    func cancelEditingPath() {
        isEditingPath = false
        pathError = nil
        focusList()
    }

    func submitPath() {
        guard let url = PathInput.resolve(pathText, relativeTo: folder) else { cancelEditingPath(); return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            pathError = String(localized: "No folder at this path.")
            shakeToken += 1
            return
        }
        isEditingPath = false
        pathError = nil
        if isDirectory.boolValue, !NSWorkspace.shared.isFilePackage(atPath: url.path) {
            go(to: url)
        } else {
            go(to: url.deletingLastPathComponent(), select: [url])
        }
        focusList()
    }

    // MARK: Loading

    /// Reads the folder off the main thread. `select` nil keeps the selection (a refresh):
    /// the same files by URL, or by file ID when one was renamed.
    private func load(select: Set<URL>?, clear: Bool = true) {
        loadTask?.cancel()
        let folder = folder
        let order = order
        let keep = select ?? selection
        let keepIDs = select == nil ? Set(selectedItems.compactMap(\.fileID)) : []
        if select != nil, clear {
            items = []
            itemsVersion += 1
            state = .loading
            showsLoading = false
            selection = []
            watch(folder)
            publish()
        }
        // The read starts at once, off the main thread, instead of waiting behind the redraw
        // that clearing the list causes (about 50 ms on 10,000 files).
        let reading = Task.detached(priority: .userInitiated) { await Self.read(folder, order: order) }
        loadTask = Task {
            let spinner = Task {
                try? await Task.sleep(for: .milliseconds(500))
                if !Task.isCancelled, state == .loading { showsLoading = true }
            }
            let result = await reading.value
            spinner.cancel()
            guard !Task.isCancelled, folder == self.folder else { return }
            showsLoading = false
            switch result {
            case .success(let (list, space)):
                items = list
                itemsVersion += 1
                available = space
                state = .ready
                var kept = keep.intersection(list.map(\.url))
                if !keepIDs.isEmpty {
                    kept.formUnion(list.filter { $0.fileID.map(keepIDs.contains) ?? false }.map(\.url))
                }
                selection = kept
                if select != nil { revealToken += 1 }
            case .failure(let error):
                items = []
                itemsVersion += 1
                state = .failed(error)
                log.post(error == .denied ? .warning : .error, "Kamiro can't open \(folder.path): \(error)", source: "Browse")
            }
            publish()
        }
    }

    @concurrent
    nonisolated private static func read(_ folder: URL, order: ItemOrder) async -> Result<([FileItem], Int64?), FolderError> {
        do {
            let list = try FolderReader.list(folder)
            return .success((order.sorted(list), Volumes.availableSpace(at: folder)))
        } catch {
            return .failure(error)
        }
    }

    @concurrent
    nonisolated private static func sort(_ items: [FileItem], order: ItemOrder) async -> [FileItem] {
        order.sorted(items)
    }

    private func resort() {
        let order = order
        let list = items
        Task {
            let sorted = await Self.sort(list, order: order)
            guard self.order == order, self.items == list else { return }
            items = sorted
            itemsVersion += 1
        }
    }

    private func watch(_ folder: URL) {
        watcher = FolderWatcher(folder: folder) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func publish() { MenuState.shared.refresh(self) }

    /// For the self-test and snapshots: wait until the folder is read.
    func waitUntilLoaded() async {
        await loadTask?.value
    }
}

/// Small preferences. Test runs (APP_STORE set) use their own domain, never the real one.
enum Prefs {
    static let returnOpensItems = "returnOpensItems"
    static let showStatusBar = "showStatusBar"
    static let defaults: UserDefaults = Store.isOverridden
        ? UserDefaults(suiteName: "com.mathieuares.kamiro.test") ?? .standard : .standard
}
