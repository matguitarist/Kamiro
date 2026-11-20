import AppKit
import KamiroKit
import Quartz
import SwiftUI

/// The list's keys and commands. Arrow, Return and Delete keys live here, not in the menu
/// bar, where they would fire in the address field or while renaming.
/// Cut, Copy, Paste, Select All, Undo and Redo come through the responder chain, so the
/// same Edit menu items still edit text when a text field has the keyboard.
final class FileTable: NSTableView, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    weak var coordinator: DetailsCoordinator?
    private var model: BrowserModel? { coordinator?.model }

    override func keyDown(with event: NSEvent) {
        if FileKeys.handle(event, model: model) { return }
        super.keyDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { coordinator?.update() }
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { MenuState.shared.listFocused = true }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { MenuState.shared.listFocused = false }
        return resigned
    }

    // MARK: Edit menu, through the responder chain

    @objc func cut(_ sender: Any?) { model?.cutSelection() }
    @objc func copy(_ sender: Any?) { model?.copySelection() }
    @objc func paste(_ sender: Any?) { model?.paste() }
    @objc func undo(_ sender: Any?) { FileUndo.manager.undo() }
    @objc func redo(_ sender: Any?) { FileUndo.manager.redo() }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
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
            return super.validateUserInterfaceItem(item)
        }
    }

    // MARK: Right-click menu (the full one comes with S-033)

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 {
            if !selectedRowIndexes.contains(row) { selectRowIndexes([row], byExtendingSelection: false) }
        } else {
            deselectAll(nil)
        }
        window?.makeFirstResponder(self)
        return coordinator?.contextMenu(onItems: row >= 0)
    }

    // MARK: Drag and drop

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        coordinator?.cancelSpring()
        super.draggingExited(sender)
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        coordinator?.cancelSpring()
        super.concludeDragOperation(sender)
    }

    // MARK: Quick Look

    func toggleQuickLook() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible {
            panel.orderOut(nil)
        } else if !selectedRowIndexes.isEmpty {
            window?.makeFirstResponder(self)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private var previewURLs: [URL] { selectedRowIndexes.compactMap { coordinator?.url(at: $0) } }

    // Quick Look calls these on the main thread; AppKit declares them without isolation.
    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = self
            panel.delegate = self
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewURLs[index] as NSURL
    }

    /// Arrows in the panel move the selection in the list, and the preview follows.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, [123, 124, 125, 126].contains(event.keyCode) else { return false }
        keyDown(with: event)
        return true
    }
}

// MARK: - Rename in place (S-014)

extension DetailsCoordinator {
    func beginRename(_ url: URL) {
        guard let table, let row = rowOf[url], rename == nil else { return }
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
        let nameColumn = table.column(withIdentifier: ListColumn.name.identifier)
        guard nameColumn >= 0, let cell = table.view(atColumn: nameColumn, row: row, makeIfNecessary: true) as? NSTableCellView,
              let field = cell.textField else { return }
        let session = InlineRename(url: url, field: field, model: model, isFolder: item(at: row)?.isFolder ?? false,
                                   neighbor: { [weak self] step in self?.neighbor(of: url, step: step) },
                                   finished: { [weak self] in self?.renameEnded() })
        session.onError = { [weak self] in self?.renameError = $0 }
        rename = session
        renameError = nil
        session.begin()
    }

    /// Ends editing; `keep` false puts the old name back.
    func endRename(keep: Bool = false) {
        pendingRename = nil
        rename?.end(keep: keep)
    }

    private func renameEnded() {
        rename = nil
        table?.window?.makeFirstResponder(table)
        update()
    }

    /// The next item up or down, past group headers.
    private func neighbor(of url: URL, step: Int) -> URL? {
        guard var row = rowOf[url] else { return nil }
        repeat { row += step } while rows.indices.contains(row) && item(at: row) == nil
        return self.url(at: row)
    }

    func contextMenu(onItems: Bool) -> NSMenu { model.contextMenu(onItems: onItems) }

    // MARK: Drag and drop (S-018)

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        url(at: row) as NSURL?
    }

    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        let urls = droppedURLs(info)
        guard !urls.isEmpty else { return [] }
        let destination: URL
        if operation == .on, let item = item(at: row), item.isFolder, !urls.contains(item.url) {
            destination = item.url
            spring(row)
        } else {
            tableView.setDropRow(-1, dropOperation: .on)
            destination = model.folder
            cancelSpring()
        }
        let kind = dropKind(urls, into: destination, info: info)
        guard !DropRule.isNoOp(sources: urls, destination: destination, kind: kind) else { return [] }
        return kind == .copy ? .copy : .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        cancelSpring()
        let urls = droppedURLs(info)
        let destination = item(at: row).flatMap { $0.isFolder ? $0.url : nil } ?? model.folder
        let kind = dropKind(urls, into: destination, info: info)
        guard !urls.isEmpty, !DropRule.isNoOp(sources: urls, destination: destination, kind: kind) else { return false }
        model.transfer(kind, urls, into: destination)
        return true
    }

    private func droppedURLs(_ info: any NSDraggingInfo) -> [URL] {
        FilePasteboard.read(from: info.draggingPasteboard)
    }

    private func dropKind(_ urls: [URL], into destination: URL, info: any NSDraggingInfo) -> TransferKind {
        model.dropKind(urls, into: destination, info: info)
    }

    /// A folder held under a drag for 0.7 s opens, so the drop can go deeper.
    func spring(_ row: Int) {
        guard row != springRow, let folder = url(at: row) else { return }
        cancelSpring()
        springRow = row
        springTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self else { return }
            springRow = -1
            model.go(to: folder)
        }
    }

    func cancelSpring() {
        springTask?.cancel()
        springTask = nil
        springRow = -1
    }
}
