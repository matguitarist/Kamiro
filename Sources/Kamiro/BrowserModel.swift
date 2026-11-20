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
        didSet {
            guard order != oldValue else { return }
            resort()
            remember()
        }
    }
    /// Icons, details or columns (View menu, ⌘1 to ⌘3).
    var mode: ViewMode = .details {
        didSet {
            guard mode != oldValue else { return }
            focusToken += 1
            revealToken += 1
            remember()
            publish()
        }
    }
    /// The details view's columns, left to right, and the widths people dragged (S-021).
    var columns = ListColumn.standard {
        didSet { if columns != oldValue { remember() } }
    }
    private(set) var widths: [ListColumn: Double] = [:]
    /// View › Group By (S-022); the details view shows a header before each group.
    var groupBy: GroupBy = .none {
        didSet {
            guard groupBy != oldValue else { return }
            groupVersion += 1
            remember()
            publish()
        }
    }
    private(set) var collapsedGroups: Set<String> = []
    /// Goes up when the groups change without the items changing.
    private(set) var groupVersion = 0
    /// Goes up when the columns change from outside the table (a folder's own view, the menu).
    private(set) var viewVersion = 0
    @ObservationIgnored private var restoring = false
    @ObservationIgnored private var widthSave: Task<Void, Never>?
    private(set) var available: Int64?
    /// Folder sizes measured so far (S-023); folders not in it show "—".
    private(set) var folderSizes: [URL: Int64] = [:]
    /// Goes up as sizes arrive, so the list redraws its Size column.
    private(set) var sizesVersion = 0
    @ObservationIgnored private var sizeTask: Task<Void, Never>?
    @ObservationIgnored private var sizeRun = 0
    @ObservationIgnored private var waitingSizes: [URL] = []
    @ObservationIgnored private var treeWatcher: TreeWatcher?
    @ObservationIgnored private var resortSoon: Task<Void, Never>?
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
    @ObservationIgnored weak var grid: GridCoordinator?
    @ObservationIgnored weak var columnView: ColumnCoordinator?

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
    var counts: StatusCounts { StatusCounts(items: items, selection: selection, available: available, sizes: folderSizes) }
    /// Folder sizes are being measured.
    var isMeasuring: Bool { sizeTask != nil }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        restoreView()
        load(select: [])
    }

    // MARK: Each folder's view (S-021)

    var folderView: FolderView { FolderView(mode: mode, order: order, columns: columns, widths: widths, groupBy: groupBy) }

    /// Folds or unfolds one group.
    func toggleGroup(_ id: String) {
        if collapsedGroups.remove(id) == nil { collapsedGroups.insert(id) }
        groupVersion += 1
    }

    /// Shows the folder as it was last shown, or as new folders are. Column view stays on
    /// while browsing in it.
    private func restoreView() {
        restoring = true
        defer { restoring = false }
        let view = Store.views.view(for: folder)
        order = view.order
        if mode != .columns { mode = view.mode }
        columns = view.columns
        widths = view.widths
        groupBy = view.groupBy
        collapsedGroups = []
        viewVersion += 1
    }

    private func remember() {
        guard !restoring else { return }
        Store.views.remember(folderView, for: folder)
    }

    func toggleColumn(_ column: ListColumn) {
        var view = folderView
        view.toggle(column)
        restoring = true
        columns = view.columns
        order = view.order
        restoring = false
        remember()
        viewVersion += 1
    }

    /// A column dragged wider or narrower; saved once the drag settles.
    func setWidth(_ width: Double, of column: ListColumn) {
        guard widths[column] != width else { return }
        widths[column] = width
        widthSave?.cancel()
        widthSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.remember()
        }
    }

    /// View › Use as Defaults: folders never changed show this view.
    func useAsDefaults() {
        Store.views.useAsDefaults(folderView)
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
        restoreView()
        load(select: wanted)
    }

    func goBack(_ steps: Int = 1) {
        let from = folder
        guard history.back(steps) != nil else { return }
        remembered[from] = selection
        restoreView()
        load(select: remembered[folder] ?? [])
    }

    func goForward(_ steps: Int = 1) {
        let from = folder
        guard history.forward(steps) != nil else { return }
        remembered[from] = selection
        restoreView()
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
            stopMeasuring()
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
                measure(list.filter { ($0.isFolder || $0.isPackage) && folderSizes[$0.url] == nil }.map(\.url))
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
    nonisolated private static func sort(_ items: [FileItem], order: ItemOrder, sizes: [URL: Int64]) async -> [FileItem] {
        order.sorted(items, sizes: sizes)
    }

    // MARK: Folder sizes (S-023)

    /// Measures folders one at a time, off the main thread; leaving the folder stops it.
    private func measure(_ urls: [URL]) {
        waitingSizes += urls.filter { !waitingSizes.contains($0) }
        guard sizeTask == nil, !waitingSizes.isEmpty else { return }
        let folder = folder
        sizeRun += 1
        let run = sizeRun
        sizeTask = Task { [weak self] in
            defer { if self?.sizeRun == run { self?.sizeTask = nil } }
            while let self, !Task.isCancelled, !waitingSizes.isEmpty {
                let next = waitingSizes.removeFirst()
                let measured = await Self.size(of: next)
                guard !Task.isCancelled, self.folder == folder else { break }
                // A folder that can't be read keeps its "—".
                guard case .success(let size) = measured else { continue }
                folderSizes[next] = size
                sizesVersion += 1
                if order.key == .size || groupBy == .size { sortSoon() }
                publish()
            }
        }
    }

    @concurrent
    nonisolated private static func size(of url: URL) async -> Result<Int64, any Error> {
        Result { try FolderSize.measure(url) }
    }

    private func stopMeasuring() {
        sizeTask?.cancel()
        sizeTask = nil
        waitingSizes = []
        folderSizes = [:]
        sizesVersion += 1
        treeWatcher = TreeWatcher(folder: folder) { [weak self] paths in
            Task { @MainActor in self?.sizesChanged(paths) }
        }
    }

    /// Something changed inside a subfolder: measure that subfolder again.
    private func sizesChanged(_ paths: [String]) {
        guard let watcher = treeWatcher else { return }
        let names = Set(paths.compactMap(watcher.child(holding:)))
        let changed = items.filter { ($0.isFolder || $0.isPackage) && names.contains($0.name) }.map(\.url)
        measure(changed)
    }

    /// Sizes arrive one by one; the list sorts again once they pause.
    private func sortSoon() {
        resortSoon?.cancel()
        resortSoon = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            resort()
            groupVersion += 1
        }
    }

    private func resort() {
        let order = order
        let list = items
        let sizes = folderSizes
        Task {
            let sorted = await Self.sort(list, order: order, sizes: sizes)
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
    static let iconSize = "iconSize"
    static let showHidden = "showHidden"
    static let defaults: UserDefaults = Store.isOverridden
        ? UserDefaults(suiteName: "com.mathieuares.kamiro.test") ?? .standard : .standard
}
