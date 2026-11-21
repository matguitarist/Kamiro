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
    /// What the list shows: the folder's items, narrowed by the filter (S-028).
    private(set) var items: [FileItem] = []
    /// Everything in the folder, before the filter.
    @ObservationIgnored private var allItems: [FileItem] = []
    /// The folder a search started from, for the scope bar's second choice (S-029).
    var searchFolder: URL?
    /// Edit › Find (⌘F) puts the keyboard in the filter.
    private(set) var filterFocusToken = 0
    func focusFilter() { filterFocusToken += 1 }
    /// The toolbar filter; going to another folder clears it.
    var filterText = "" {
        didSet {
            guard filterText != oldValue else { return }
            showFiltered()
        }
    }
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
    /// Subfolder sizes (S-023).
    let sizes = FolderSizes()
    var folderSizes: [URL: Int64] { sizes.sizes }
    var sizesVersion: Int { sizes.version }
    /// Each item's cloud status in iCloud Drive and sync folders (S-058), read after the list shows.
    private(set) var cloud: [URL: CloudStatus] = [:]
    private(set) var cloudVersion = 0
    @ObservationIgnored private var cloudTask: Task<Void, Never>?
    @ObservationIgnored private var resortSoon: Task<Void, Never>?
    /// Opens a Properties window; set by the window.
    @ObservationIgnored var openProperties: ((URL) -> Void)?
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
    /// Go › Connect to Server… shows its sheet on this window (S-037).
    var connectShown = false
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
    @ObservationIgnored nonisolated(unsafe) private var hiddenWatch: (any NSObjectProtocol)?
    @ObservationIgnored nonisolated(unsafe) private var foldersFirstWatch: (any NSObjectProtocol)?
    /// Opens a folder in a new window, or a new tab of this one when true (set by the window's view).
    @ObservationIgnored var openWindow: ((URL, Bool) -> Void)?
    /// What the window shows selected when it opens (a file another app sent).
    @ObservationIgnored var startSelection: Set<URL> = []
    /// Shows or hides Quick Look (set by the table).
    @ObservationIgnored var quickLook: (() -> Void)?
    @ObservationIgnored let log: LogStore

    init(start: URL, log: LogStore) {
        history = History(start)
        self.log = log
        sizes.arrived = { [weak self] in
            guard let self else { return }
            if order.key == .size || groupBy == .size { sortSoon() }
            publish()
        }
        hiddenWatch = NotificationCenter.default.addObserver(forName: HiddenFiles.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Settings › Views › Folders on top applies to every folder, these windows too.
        foldersFirstWatch = NotificationCenter.default.addObserver(forName: Self.foldersFirstChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.restoring = true
                self.order.foldersFirst = Store.views.memory.foldersFirst
                self.restoring = false
            }
        }
    }

    static let foldersFirstChanged = Notification.Name("KamiroFoldersFirstChanged")

    deinit {
        if let hiddenWatch { NotificationCenter.default.removeObserver(hiddenWatch) }
        if let foldersFirstWatch { NotificationCenter.default.removeObserver(foldersFirstWatch) }
    }

    var folder: URL { history.current }
    var title: String { Self.name(of: folder) }
    var selectedItems: [FileItem] { items.filter { selection.contains($0.url) } }
    /// What Pin to Sidebar pins: the selected folders, or this folder when nothing is selected (S-032).
    var pinTargets: [URL] {
        let targets = selection.isEmpty ? (isVirtual || state != .ready ? [] : [folder]) : selectedItems.filter(\.isFolder).map(\.url)
        return targets.filter { !PinStore.shared.list.contains($0) }
    }
    func pinToSidebar() {
        PinStore.shared.pin(pinTargets)
        publish()
    }
    var canGoUp: Bool { folder.isFileURL && Location(folder).parent != nil }
    var isFailed: Bool { if case .failed = state { true } else { false } }
    var counts: StatusCounts { StatusCounts(items: items, selection: selection, available: available, sizes: folderSizes) }
    /// Folder sizes are being measured.
    var isMeasuring: Bool { sizes.isMeasuring }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        restoreView()
        load(select: Set(startSelection.map(\.canonical)))
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
        let view = Store.views.view(for: folder, inCloud: Cloud.isInCloud(folder))
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
        // smb://server shows its shares; smb://server/share mounts it and goes in (S-055).
        if let server = ServerHost.server(of: url) {
            if ServerHost.share(of: url) != nil { openShare(url) } else { go(to: VirtualPlace.server(server).url) }
            return
        }
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

    /// Shows another place in this history step (a search's new scope or filters).
    func replace(with url: URL) {
        remembered[folder] = selection
        history.replace(with: url)
        restoreView()
        load(select: [])
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
        guard folder.isFileURL, let parent = Location(folder).parent else { return }
        go(to: parent.url, select: [folder])
    }

    /// Opens the selection (or `urls`): one folder opens here, files open in their apps.
    func open(_ urls: [URL]? = nil, newWindow: Bool = false, newTab: Bool = false) {
        let targets = urls.map { list in list.compactMap { url in items.first { $0.url == url.canonical } } } ?? selectedItems
        let folders = targets.filter(\.isFolder)
        let files = targets.filter { !$0.isFolder }
        if !newWindow, !newTab, folders.count == 1, files.isEmpty {
            go(to: folders[0].url)
        } else {
            folders.forEach { openWindow?($0.url, newTab) }
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
        pathText = folder.isFileURL ? PathInput.display(folder) : ""
        pathError = nil
        isEditingPath = true
    }

    func cancelEditingPath() {
        isEditingPath = false
        pathError = nil
        focusList()
    }

    func submitPath() {
        // smb://server, \\server\share and the like go to the server (S-055).
        let typed = pathText.trimmingCharacters(in: .whitespaces)
        if typed.contains("://") || typed.hasPrefix("\\\\"), let server = ServerAddress.parse(typed) {
            isEditingPath = false
            pathError = nil
            go(to: server)
            return
        }
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
            setItems([])
            // A search keeps its words in the field; a folder starts unfiltered.
            let words = VirtualPlace(folder).flatMap { if case .search(let search) = $0 { search.text } else { nil } } ?? ""
            if filterText != words { filterText = words }
            state = .loading
            showsLoading = false
            selection = []
            cloudTask?.cancel()
            cloud = [:]
            cloudVersion += 1
            watch(folder)
            sizes.start(in: folder) { [weak self] in self?.items ?? [] }
            publish()
        }
        // The read starts at once, off the main thread, instead of waiting behind the redraw
        // that clearing the list causes (about 50 ms on 10,000 files).
        let hidden = HiddenFiles.shown
        // Test runs look for tags in the test tree, which Spotlight doesn't index.
        let tagRoot = Store.isOverridden ? Store.seedFolder : nil
        let reading = Task.detached(priority: .userInitiated) {
            await Self.read(folder, order: order, showHidden: hidden, tagRoot: tagRoot)
        }
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
                setItems(list)
                available = space
                state = .ready
                var kept = keep.intersection(list.map(\.url))
                if !keepIDs.isEmpty {
                    kept.formUnion(list.filter { $0.fileID.map(keepIDs.contains) ?? false }.map(\.url))
                }
                selection = kept
                if select != nil { revealToken += 1 }
                // A server page's shares are whole disks across the network: never walked for a size.
                if !isServerPage {
                    sizes.measure(list.filter { ($0.isFolder || $0.isPackage) && folderSizes[$0.url] == nil }.map(\.url))
                } else if select != nil {
                    connectAllShares()
                }
                readCloud(list)
            case .failure(let error):
                setItems([])
                state = .failed(error)
                log.post(error == .denied ? .warning : .error, "Kamiro can't open \(folder.path): \(error)", source: "Browse")
            }
            publish()
        }
    }

    @concurrent
    nonisolated private static func read(_ folder: URL, order: ItemOrder, showHidden: Bool,
                                         tagRoot: URL?) async -> Result<([FileItem], Int64?), FolderError> {
        if case .server(let server) = VirtualPlace(folder) {
            do {
                return .success((order.sorted(try ShareList.items(on: server, mounted: Volumes.mounted())), nil))
            } catch {
                return .failure(.other(String(describing: error)))
            }
        }
        if let place = VirtualPlace(folder) {
            return .success((order.sorted(place.items(showHidden: showHidden, root: tagRoot)), nil))
        }
        do {
            var list = try FolderReader.list(folder, showHidden: showHidden)
            // iCloud Drive shows each app's folder among its own, like the Finder (S-057).
            if folder.path == Cloud.drive.path { list += Cloud.appFolders(showHidden: showHidden) }
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
        let list = allItems
        let measured = folderSizes
        Task {
            let sorted = await Self.sort(list, order: order, sizes: measured)
            guard self.order == order, self.allItems == list else { return }
            setItems(sorted)
        }
    }

    private func setItems(_ list: [FileItem]) {
        allItems = list
        items = NameFilter.apply(list, filterText)
        itemsVersion += 1
    }

    /// The filter changed: show the matching items, and keep only the selection still shown.
    private func showFiltered() {
        items = NameFilter.apply(allItems, filterText)
        itemsVersion += 1
        let shown = Set(items.map(\.url))
        if !selection.isSubset(of: shown) { selection = selection.intersection(shown) }
        publish()
    }

    // MARK: Cloud status (S-058)

    /// Reads each item's cloud status off the main thread, 100 at a time, and only in cloud
    /// folders: it costs about 1 ms an item, a hundred times a plain listing. While something
    /// downloads or uploads, it looks again every 2 seconds.
    private func readCloud(_ list: [FileItem]) {
        cloudTask?.cancel()
        let folder = folder
        guard Cloud.isInCloud(folder) else { return }
        let urls = list.map(\.url)
        cloudTask = Task { [weak self] in
            var moving = false
            for start in stride(from: 0, to: urls.count, by: 100) {
                let part = await Self.cloudStatuses(Array(urls[start..<min(start + 100, urls.count)]))
                guard !Task.isCancelled, let model = self, model.folder == folder else { return }
                model.cloud.merge(part) { $1 }
                model.cloudVersion += 1
                moving = moving || part.values.contains { $0 == .downloading || $0 == .uploading }
            }
            guard moving else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let model = self, model.folder == folder else { return }
            model.readCloud(model.allItems)
        }
    }

    /// Reads the statuses again (after Download Now or Remove Download).
    func refreshCloud() { readCloud(allItems) }

    @concurrent
    nonisolated private static func cloudStatuses(_ urls: [URL]) async -> [URL: CloudStatus] {
        var found: [URL: CloudStatus] = [:]
        for url in urls {
            if let status = CloudStatus.read(url) { found[url] = status }
        }
        return found
    }

    /// For the self-test: wait until every item's status is read.
    func waitForCloud() async {
        await cloudTask?.value
    }

    private func watch(_ folder: URL) {
        guard folder.isFileURL else { watcher = nil; return }
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
    static let showInspector = "showInspector"
    /// The column view's last column for a selected file: its preview, name and facts.
    static let showColumnPreview = "showColumnPreview"
    /// The bundle ID of the app Open in Terminal uses (Settings › General).
    static let terminal = "terminal"
    /// The bundle ID of the code editor Open in Editor uses (Settings › General).
    static let editor = "editor"
    /// Connect to Server's recent addresses, newest first (S-037).
    static let recentServers = "recentServers"
    /// Where things were last copied or moved, newest first (S-046).
    static let recentFolders = "recentFolders"
    /// The sidebar's pinned folders, as paths (S-032).
    static let pins = "pins"
    static let hiddenSidebarSections = "hiddenSidebarSections"
    /// Home lists recent files (Settings › General › Show on Home); on unless turned off.
    static let showRecentFiles = "showRecentFiles"
    /// Where new windows and tabs open: a StartPlace, kept as its name or a path (S-040).
    static let newWindowStart = "newWindowStart"
    /// Network lists each server's mounted shares under it; off, only the servers (S-055).
    static let showConnectedShares = "showConnectedShares"
    /// Opening a server connects all its shares; on unless turned off (S-055).
    static let connectAllShares = "connectAllShares"
    /// The icons picked for servers and disks, by PlaceIcons key (S-056).
    static let placeIcons = "placeIcons"
    /// What the right-click menu leaves out, by MenuEntry and FileTemplate names (S-047).
    static let hiddenMenuEntries = "hiddenMenuEntries"
    static let hiddenTemplates = "hiddenTemplates"
    static let defaults: UserDefaults = Store.isOverridden
        ? UserDefaults(suiteName: "com.mathieuares.kamiro.test") ?? .standard : .standard
}
