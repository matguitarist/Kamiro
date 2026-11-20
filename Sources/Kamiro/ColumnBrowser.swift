import AppKit
import KamiroKit
import Quartz
import SwiftUI

/// The column view (S-020): NSBrowser, the Finder's own kind of column browser. Columns
/// start at the folder the window was in; the folder holding the selection is the window's
/// folder, so cut, copy, paste and the status bar work as in the other views.
struct ColumnBrowser: NSViewRepresentable {
    let model: BrowserModel
    let version: Int
    let selection: Set<URL>
    let folder: URL
    let focus: Int
    let cutVersion: Int
    let renameToken: Int
    let showPreview: Bool

    func makeCoordinator() -> ColumnCoordinator { ColumnCoordinator(model: model) }

    func makeNSView(context: Context) -> FileBrowser {
        let browser = FileBrowser()
        browser.coordinator = context.coordinator
        browser.delegate = context.coordinator
        browser.target = context.coordinator
        browser.action = #selector(ColumnCoordinator.selectionChanged(_:))
        browser.doubleAction = #selector(ColumnCoordinator.doubleClicked(_:))
        browser.allowsMultipleSelection = true
        browser.allowsEmptySelection = true
        browser.hasHorizontalScroller = true
        browser.autohidesScroller = true
        browser.separatesColumns = true
        browser.isTitled = false
        browser.columnResizingType = .userColumnResizing
        browser.minColumnWidth = 120
        browser.rowHeight = 22
        browser.focusRingType = .none
        browser.registerForDraggedTypes([.fileURL])
        browser.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: true)
        browser.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: false)
        context.coordinator.browser = browser
        context.coordinator.start()
        model.columnView = context.coordinator
        model.quickLook = { [weak browser] in browser?.toggleQuickLook() }
        return browser
    }

    func updateNSView(_ browser: FileBrowser, context: Context) {
        // NSBrowser builds columns, and the SwiftUI preview column, as it goes; doing that inside
        // SwiftUI's own update re-enters observation tracking and crashed (icons → columns).
        let coordinator = context.coordinator
        let showPreview = showPreview
        DispatchQueue.main.async {
            coordinator.setShowsPreview(showPreview)
            coordinator.update()
        }
    }
}

/// One file or folder in the columns; a folder reads its items the first time a column asks.
final class ColumnNode: NSObject {
    let item: FileItem
    private var loaded: [ColumnNode]?
    private let order: () -> ItemOrder

    init(_ item: FileItem, order: @escaping () -> ItemOrder) {
        self.item = item
        self.order = order
    }

    var url: URL { item.url }

    var children: [ColumnNode] {
        if let loaded { return loaded }
        let list = (try? FolderReader.list(url, showHidden: Prefs.defaults.bool(forKey: Prefs.showHidden))) ?? []
        let made = order().sorted(list).map { ColumnNode($0, order: order) }
        loaded = made
        return made
    }

    /// Reads the folder again the next time a column asks.
    func forget() { loaded = nil }

    func child(_ url: URL) -> ColumnNode? { children.first { $0.url == url } }
}

final class ColumnCoordinator: NSObject, NSBrowserDelegate {
    let model: BrowserModel
    weak var browser: FileBrowser?
    private(set) var root: ColumnNode?
    private var version = -1
    private var focus = -1
    private var cutVersion = -1
    private var renameToken = 0
    /// The item whose name is being edited, for the self-test.
    private(set) var renaming: URL?
    private var applying = false
    /// Show the last column for a selected file (View › Show Preview).
    private(set) var showsPreview = Prefs.defaults.object(forKey: Prefs.showColumnPreview) as? Bool ?? true
    /// Widths people gave columns by dragging, by the column's folder; the rest size to their names.
    private var chosenWidths: [URL: CGFloat] = [:]
    private var fitPending = false
    /// The preview column is never narrower than this; past it, it fills the browser's width.
    static let previewMinWidth: CGFloat = 200

    nonisolated(unsafe) private var hiddenWatch: (any NSObjectProtocol)?

    init(model: BrowserModel) {
        self.model = model
        super.init()
        // Hidden files shown or hidden (S-024): every column is read again.
        hiddenWatch = NotificationCenter.default.addObserver(forName: HiddenFiles.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.readAgain() }
        }
    }

    deinit {
        if let hiddenWatch { NotificationCenter.default.removeObserver(hiddenWatch) }
    }

    func start() {
        setRoot(model.folder)
    }

    func setShowsPreview(_ shows: Bool) {
        guard shows != showsPreview else { return }
        showsPreview = shows
        readAgain()
    }

    private func readAgain() {
        guard let root else { return }
        setRoot(root.url)
        show(model.folder, selecting: model.selection)
    }

    private func setRoot(_ url: URL) {
        let item = FolderReader.item(at: url) ?? FileItem(url: url, name: url.lastPathComponent, isFolder: true)
        root = ColumnNode(item, order: { [weak model] in model?.order ?? ItemOrder() })
        browser?.loadColumnZero()
    }

    // MARK: The window's folder and selection, both ways

    /// What the columns show: the folder holding the selection (the last column when
    /// nothing is selected there), and the selected items.
    var shown: (folder: URL, selection: Set<URL>)? {
        guard let browser, let root else { return nil }
        let column = browser.selectedColumn
        guard column >= 0, let parent = browser.parentForItems(inColumn: column) as? ColumnNode else {
            return (root.url, [])
        }
        let rows = browser.selectedRowIndexes(inColumn: column) ?? []
        let urls = rows.compactMap { (browser.item(atRow: $0, inColumn: column) as? ColumnNode)?.url }
        return (parent.url, Set(urls))
    }

    /// The window moved (address bar, Back, a refresh): the columns follow.
    func update() {
        guard let browser, let root, !applying else { return }
        if version != model.itemsVersion {
            version = model.itemsVersion
            // The folder on screen was read again: its column is read again too.
            if model.state == .ready, let node = node(for: model.folder) {
                node.forget()
                let column = depth(model.folder) - depth(root.url)
                if column >= 0, column <= browser.lastColumn { browser.reloadColumn(column) }
            }
            cutVersion = FileClipboard.shared.version
        }
        if cutVersion != FileClipboard.shared.version {
            cutVersion = FileClipboard.shared.version
            browser.redrawColumns()
        }
        // While a folder loads, the window has no selection yet: wait for it.
        if model.state == .ready, let shown, shown.folder != model.folder || shown.selection != model.selection {
            show(model.folder, selecting: model.selection)
        }
        if focus != model.focusToken, let window = browser.window {
            focus = model.focusToken
            window.makeFirstResponder(browser)
        }
        if renameToken != model.renameToken {
            renameToken = model.renameToken
            if let target = model.renameTarget { beginRename(target) }
        }
    }

    /// Opens the columns down to `folder` and selects `urls` in its column.
    private func show(_ folder: URL, selecting urls: Set<URL>) {
        guard let browser, var root else { return }
        if folder != root.url, !folder.path.hasPrefix(root.url.path == "/" ? "/" : root.url.path + "/") {
            setRoot(folder)
            guard let newRoot = self.root else { return }
            root = newRoot
        }
        var path = IndexPath()
        var node = root
        for url in Location(folder).crumbs.drop(while: { $0 != root.url }).dropFirst() {
            guard let index = node.children.firstIndex(where: { $0.url == url }) else { break }
            path.append(index)
            node = node.children[index]
        }
        applying = true
        defer { applying = false }
        let rows = urls.compactMap { url in node.children.firstIndex { $0.url == url } }.sorted()
        if rows.isEmpty {
            browser.selectionIndexPath = path.isEmpty ? nil : path
            if path.isEmpty { browser.loadColumnZero() }
        } else {
            // Open the folder's column first: NSBrowser throws when asked to select in a column
            // it hasn't loaded yet.
            browser.selectionIndexPath = path.isEmpty ? nil : path
            if path.isEmpty { browser.loadColumnZero() }
            let column = path.count
            if column <= browser.lastColumn { browser.reloadColumn(column) }
            guard column <= browser.lastColumn, rows.allSatisfy({ browser.item(atRow: $0, inColumn: column) != nil }) else { return }
            browser.selectionIndexPaths = rows.map { path.appending($0) }
        }
        browser.scrollColumnToVisible(browser.lastColumn)
    }

    private func node(for url: URL) -> ColumnNode? {
        guard let root else { return nil }
        if url == root.url { return root }
        var node = root
        for crumb in Location(url).crumbs.drop(while: { $0 != root.url }).dropFirst() {
            guard let next = node.child(crumb) else { return nil }
            node = next
        }
        return node.url == url ? node : nil
    }

    private func depth(_ url: URL) -> Int { Location(url).crumbs.count }

    @objc func selectionChanged(_ sender: Any?) {
        guard !applying, let shown else { return }
        applying = true
        defer { applying = false }
        if shown.folder == model.folder {
            model.selection = shown.selection
        } else {
            model.go(to: shown.folder, select: shown.selection)
        }
        QuickLookSource.reloadIfShown()
    }

    @objc func doubleClicked(_ sender: Any?) {
        guard let browser, browser.clickedRow >= 0,
              let node = browser.item(atRow: browser.clickedRow, inColumn: browser.clickedColumn) as? ColumnNode,
              !node.item.isFolder else { return }
        model.open([node.url], newWindow: NSApp.currentEvent?.modifierFlags.contains(.option) ?? false)
    }

    // MARK: Items

    func rootItem(for browser: NSBrowser) -> Any? { root }

    func browser(_ browser: NSBrowser, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? ColumnNode)?.children.count ?? 0
    }

    func browser(_ browser: NSBrowser, child index: Int, ofItem item: Any?) -> Any {
        (item as? ColumnNode)?.children[index] as Any
    }

    func browser(_ browser: NSBrowser, isLeafItem item: Any?) -> Bool {
        !((item as? ColumnNode)?.item.isFolder ?? false)
    }

    func browser(_ browser: NSBrowser, objectValueForItem item: Any?) -> Any? {
        (item as? ColumnNode)?.item.name
    }

    /// The icon goes in front of the name: NSBrowser draws its rows with plain text cells.
    func browser(_ sender: NSBrowser, willDisplayCell cell: Any, atRow row: Int, column: Int) {
        guard let cell = cell as? NSTextFieldCell, let node = sender.item(atRow: row, inColumn: column) as? ColumnNode else { return }
        let dimmed = node.item.isHidden || FileClipboard.shared.isCut(node.url)
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let attachment = NSTextAttachment()
        let icon = IconCache.shared.icon(for: node.item)
        attachment.image = dimmed ? icon.dimmed : icon
        attachment.bounds = NSRect(x: 0, y: (font.capHeight - 16) / 2, width: 16, height: 16)
        let text = NSMutableAttributedString(attachment: attachment)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if dimmed { attributes[.foregroundColor] = NSColor.labelColor.withAlphaComponent(0.5) }
        text.append(NSAttributedString(string: "  " + node.item.name, attributes: attributes))
        text.addAttribute(.font, value: font, range: NSRange(location: 0, length: 1))
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
        cell.lineBreakMode = .byTruncatingMiddle
        cell.attributedStringValue = text
    }

    /// A column is as wide as its longest name, up to a limit, or as wide as people dragged it.
    /// The preview column fills what's left (fitPreview).
    func browser(_ browser: NSBrowser, shouldSizeColumn columnIndex: Int, forUserResize: Bool, toWidth suggestedWidth: CGFloat) -> CGFloat {
        guard let parent = browser.parentForItems(inColumn: columnIndex) as? ColumnNode else { return suggestedWidth }
        guard parent.item.isFolder else { return Self.previewMinWidth }
        if forUserResize {
            chosenWidths[parent.url] = suggestedWidth
            return suggestedWidth
        }
        return chosenWidths[parent.url] ?? fittingWidth(parent)
    }

    /// As wide as the longest name in the folder, between 160 and 360 points.
    private func fittingWidth(_ parent: ColumnNode) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let longest = parent.children.prefix(2_000).map { ($0.item.name as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        // Icon, gaps, and the arrow at the right edge.
        return min(max(ceil(longest) + 16 + Space.sm * 2 + Space.xxl, 160), 360)
    }

    func browser(_ browser: NSBrowser, previewViewControllerForLeafItem item: Any) -> NSViewController? {
        guard showsPreview, let node = item as? ColumnNode else { return nil }
        return ColumnPreview(item: node.item)
    }

    // MARK: Column widths

    /// Whether people can drag `column`'s right edge: folder columns, not the preview.
    func isResizable(_ column: Int) -> Bool {
        guard let browser, column >= 0, column <= browser.lastColumn else { return false }
        return (browser.parentForItems(inColumn: column) as? ColumnNode)?.item.isFolder ?? false
    }

    /// Sets a folder column's width, kept for that folder while the window is open.
    func setWidth(_ width: CGFloat, ofColumn column: Int) {
        guard let browser, let parent = browser.parentForItems(inColumn: column) as? ColumnNode, parent.item.isFolder else { return }
        let width = max(browser.minColumnWidth, width.rounded())
        chosenWidths[parent.url] = width
        browser.setWidth(width, ofColumn: column)
        fitPreview()
    }

    /// Double-clicking a divider sizes the column to its longest name again.
    func fitWidth(ofColumn column: Int) {
        guard let browser, let parent = browser.parentForItems(inColumn: column) as? ColumnNode, parent.item.isFolder else { return }
        chosenWidths[parent.url] = nil
        browser.setWidth(fittingWidth(parent), ofColumn: column)
        fitPreview()
    }

    /// The preview column, when it's showing.
    var previewColumn: Int? {
        guard let browser, browser.lastColumn >= 0,
              let parent = browser.parentForItems(inColumn: browser.lastColumn) as? ColumnNode, !parent.item.isFolder,
              showsPreview else { return nil }
        return browser.lastColumn
    }

    /// Widens the preview column to the browser's right edge, so no empty space is left
    /// after it; in a narrow window it keeps its smallest width and the columns scroll.
    func fitPreview() {
        guard let browser, let column = previewColumn else { return }
        let left = browser.frame(ofColumn: column).minX
        let width = max(Self.previewMinWidth, (browser.bounds.width - left - 1).rounded(.down))
        if abs(browser.width(ofColumn: column) - width) >= 1 { browser.setWidth(width, ofColumn: column) }
    }

    /// After the browser lays out its columns (a new column, a resized window).
    func fitPreviewSoon() {
        guard !fitPending else { return }
        fitPending = true
        DispatchQueue.main.async { [weak self] in
            self?.fitPending = false
            self?.fitPreview()
        }
    }

    // MARK: Rename in place (S-014)

    func beginRename(_ url: URL) {
        guard let browser, let shown, shown.selection.contains(url) else { return }
        let column = browser.selectedColumn
        guard let row = browser.selectedRowIndexes(inColumn: column)?.first(where: {
            (browser.item(atRow: $0, inColumn: column) as? ColumnNode)?.url == url
        }) else { return }
        var path = browser.indexPath(forColumn: column)
        path.append(row)
        renaming = url
        browser.editItem(at: path, with: nil, select: true)
        // The row shows the icon as an attachment: the field gets the plain name, selected
        // without its extension, like the Finder.
        if let editor = browser.window?.firstResponder as? NSTextView {
            editor.string = url.lastPathComponent
            let stem = Naming.split(url.lastPathComponent, isFolder: url.hasDirectoryPath || isFolder(url)).stem
            editor.selectedRange = NSRange(location: 0, length: (stem as NSString).length)
        }
    }

    private func isFolder(_ url: URL) -> Bool {
        node(for: url.deletingLastPathComponent())?.child(url)?.item.isFolder ?? false
    }

    /// Escape puts the old name back.
    func cancelRename() {
        guard renaming != nil else { return }
        renaming = nil
        browser?.abortEditing()
        browser?.window?.makeFirstResponder(browser)
    }

    func browser(_ browser: NSBrowser, shouldEditItem item: Any?) -> Bool { item is ColumnNode }

    func browser(_ browser: NSBrowser, setObjectValue object: Any?, forItem item: Any?) {
        guard renaming != nil else { return }
        renaming = nil
        let value = (object as? String) ?? (object as? NSAttributedString)?.string
        // Never the icon's attachment character, should the field still hold it.
        guard let node = item as? ColumnNode,
              let name = value?.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespaces),
              name != node.url.lastPathComponent else { return }
        if let problem = NameCheck.problem(renaming: node.url, to: name) {
            if problem != .empty || !name.isEmpty { NSSound.beep() }
            return
        }
        if let change = NameCheck.extensionChange(from: node.url.lastPathComponent, to: name, isFolder: node.item.isFolder) {
            model.askExtension(node.url, newName: name, change: change, next: nil)
        } else {
            model.rename(node.url, to: name)
        }
    }

    // MARK: Drag and drop (S-018)

    func browser(_ browser: NSBrowser, writeRowsWith rowIndexes: IndexSet, inColumn column: Int, to pasteboard: NSPasteboard) -> Bool {
        let urls = rowIndexes.compactMap { (browser.item(atRow: $0, inColumn: column) as? ColumnNode)?.url }
        guard !urls.isEmpty else { return false }
        FilePasteboard.write(urls, to: pasteboard)
        return true
    }

    func browser(_ browser: NSBrowser, validateDrop info: any NSDraggingInfo,
                 proposedRow row: UnsafeMutablePointer<Int>, column: UnsafeMutablePointer<Int>,
                 dropOperation: UnsafeMutablePointer<NSBrowser.DropOperation>) -> NSDragOperation {
        let urls = FilePasteboard.read(from: info.draggingPasteboard)
        guard !urls.isEmpty, let destination = destination(browser, row.pointee, column.pointee, dropOperation.pointee, urls) else { return [] }
        let kind = model.dropKind(urls, into: destination, info: info)
        guard !DropRule.isNoOp(sources: urls, destination: destination, kind: kind) else { return [] }
        return kind == .copy ? .copy : .move
    }

    func browser(_ browser: NSBrowser, acceptDrop info: any NSDraggingInfo, atRow row: Int, column: Int,
                 dropOperation: NSBrowser.DropOperation) -> Bool {
        let urls = FilePasteboard.read(from: info.draggingPasteboard)
        guard !urls.isEmpty, let destination = destination(browser, row, column, dropOperation, urls) else { return false }
        let kind = model.dropKind(urls, into: destination, info: info)
        guard !DropRule.isNoOp(sources: urls, destination: destination, kind: kind) else { return false }
        model.transfer(kind, urls, into: destination)
        return true
    }

    /// On a folder: into it. Anywhere else in a column: into that column's folder.
    private func destination(_ browser: NSBrowser, _ row: Int, _ column: Int, _ operation: NSBrowser.DropOperation, _ urls: [URL]) -> URL? {
        if operation == .on, let node = browser.item(atRow: row, inColumn: column) as? ColumnNode, node.item.isFolder, !urls.contains(node.url) {
            return node.url
        }
        return (browser.parentForItems(inColumn: max(column, 0)) as? ColumnNode)?.url
    }
}

/// The columns' keys, Edit menu commands, right-click menu and Quick Look. A column's own
/// view has the keyboard; keys it doesn't use, Edit menu commands and right-clicks come up
/// the responder chain to here. The shared keys are caught before the column sees them.
final class FileBrowser: NSBrowser, NSUserInterfaceValidations {
    weak var coordinator: ColumnCoordinator?
    private var model: BrowserModel? { coordinator?.model }
    private var keyMonitor: Any?
    private var responderWatch: NSKeyValueObservation?
    private lazy var quickLookSource = QuickLookSource(
        urls: { [weak self] in self?.model?.orderedSelection ?? [] },
        key: { [weak self] event in self?.window?.firstResponder?.keyDown(with: event) })

    /// The keyboard is in a column (not in a field being edited).
    var hasKeyboard: Bool {
        guard let responder = window?.firstResponder as? NSView, !(responder is NSText) else { return false }
        return responder === self || responder.isDescendant(of: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        responderWatch = nil
        guard let window else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Local monitors run on the main thread.
            let handled = MainActor.assumeIsolated {
                guard let self, event.window === self.window, self.hasKeyboard else { return false }
                return FileKeys.handle(event, model: self.model)
            }
            return handled ? nil : event
        }
        responderWatch = window.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                MenuState.shared.listFocused = self.hasKeyboard
            }
        }
        coordinator?.update()
    }

    override func removeFromSuperview() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        responderWatch = nil
        super.removeFromSuperview()
    }

    // MARK: Dragging a divider (the whole edge, not only the grip at the bottom)

    /// How far from a column's right edge a drag still grabs it.
    private static let grab: CGFloat = 4

    /// The column whose right edge is at `point` (in this view), when it can be resized.
    func divider(at point: NSPoint) -> Int? {
        guard let coordinator, lastColumn >= 0, bounds.contains(point) else { return nil }
        for column in max(firstVisibleColumn, 0)...lastColumn {
            let edge = frame(ofColumn: column).maxX
            // The edge, the 2-point gap after it, and a little on each side.
            if point.x >= edge - Self.grab, point.x <= edge + 2 + Self.grab, coordinator.isResizable(column) { return column }
        }
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let superview, divider(at: convert(point, from: superview)) != nil { return self }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let start = convert(event.locationInWindow, from: nil)
        guard let column = divider(at: start), let coordinator else { super.mouseDown(with: event); return }
        if event.clickCount == 2 {
            coordinator.fitWidth(ofColumn: column)
            return
        }
        let startWidth = width(ofColumn: column)
        NSCursor.resizeLeftRight.push()
        defer { NSCursor.pop() }
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let x = convert(next.locationInWindow, from: nil).x
            coordinator.setWidth(startWidth + x - start.x, ofColumn: column)
            if next.type == .leftMouseUp { break }
        }
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let coordinator, lastColumn >= 0 else { return }
        for column in max(firstVisibleColumn, 0)...lastColumn where coordinator.isResizable(column) {
            let frame = frame(ofColumn: column)
            let zone = NSRect(x: frame.maxX - Self.grab, y: bounds.minY, width: 2 + Self.grab * 2, height: bounds.height)
            addCursorRect(zone.intersection(visibleRect), cursor: .resizeLeftRight)
        }
    }

    override func tile() {
        super.tile()
        window?.invalidateCursorRects(for: self)
        coordinator?.fitPreviewSoon()
    }

    /// Redraws every column, for cut items, without reading anything again.
    func redrawColumns() {
        func mark(_ view: NSView) {
            view.needsDisplay = true
            view.subviews.forEach(mark)
        }
        mark(self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model, let coordinator else { return nil }
        var row = -1
        var column = -1
        let onItem = getRow(&row, column: &column, for: convert(event.locationInWindow, from: nil)) && row >= 0
        if onItem, !(selectedRowIndexes(inColumn: column)?.contains(row) ?? false) {
            selectRow(row, inColumn: column)
            coordinator.selectionChanged(nil)
        }
        return model.contextMenu(onItems: onItem)
    }

    @objc func cut(_ sender: Any?) { model?.cutSelection() }
    @objc func copy(_ sender: Any?) { model?.copySelection() }
    @objc func paste(_ sender: Any?) { model?.paste() }
    @objc func undo(_ sender: Any?) { FileUndo.manager.undo() }
    @objc func redo(_ sender: Any?) { FileUndo.manager.redo() }

    /// Escape while renaming, sent up from the field.
    override func cancelOperation(_ sender: Any?) {
        if coordinator?.renaming != nil { coordinator?.cancelRename() } else { super.cancelOperation(sender) }
    }

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        let undo = FileUndo.manager
        switch item.action {
        case #selector(cut(_:)), #selector(copy(_:)):
            return !(model?.selection.isEmpty ?? true)
        case #selector(paste(_:)):
            return model?.canPaste ?? false
        case #selector(undo(_:)):
            (item as? NSMenuItem)?.title = undo.undoMenuItemTitle
            return undo.canUndo
        case #selector(redo(_:)):
            (item as? NSMenuItem)?.title = undo.redoMenuItemTitle
            return undo.canRedo
        default:
            return responds(to: item.action)
        }
    }

    func toggleQuickLook() {
        let responder = hasKeyboard ? (window?.firstResponder ?? self) : self
        QuickLookSource.toggle(from: responder, in: window, hasSelection: !(model?.selection.isEmpty ?? true))
    }

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = quickLookSource
            panel.delegate = quickLookSource
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }
}

/// The last column for a selected file: its preview, name, kind, size and date. SwiftUI
/// lays it out in whatever width the browser gives the column.
final class ColumnPreview: NSHostingController<PreviewColumn> {
    init(item: FileItem) {
        super.init(rootView: PreviewColumn(item: item))
        sizingOptions = []
        // The browser sets the column's size on this view; it starts at zero otherwise.
        view.frame = NSRect(x: 0, y: 0, width: 240, height: 480)
        view.autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

struct PreviewColumn: View {
    let item: FileItem

    var body: some View {
        VStack(spacing: Space.md) {
            // The preview takes all the room the column has: a whole page of text, or the
            // picture as large as it fits.
            QuickLookPreview(url: item.url, style: .normal)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Radius.control))
            VStack(spacing: Space.xs) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(3)
                Group {
                    Text(summary)
                    if let modified = item.modified {
                        Text("Modified \(modified.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summary: String {
        let kind = KindCache.shared.kind(of: item)
        guard let size = item.size else { return kind }
        return "\(kind) – \(size.bytesText)"
    }
}

/// Quick Look's own preview of one file.
struct QuickLookPreview: NSViewRepresentable {
    let url: URL
    /// .compact draws a small thumbnail-like card; .normal shows the whole document, scrollable.
    var style: QLPreviewViewStyle = .compact

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: style) ?? QLPreviewView()
        view.shouldCloseWithWindow = false
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url { view.previewItem = url as NSURL }
    }
}

extension NSImage {
    /// The same image at half opacity, for hidden and cut items.
    var dimmed: NSImage {
        NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.5)
            return true
        }
    }
}
