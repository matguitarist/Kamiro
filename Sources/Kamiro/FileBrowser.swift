import AppKit
import KamiroKit
import Quartz

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
