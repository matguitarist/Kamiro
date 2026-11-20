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
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        switch event.keyCode {
        case 36, 76:
            if model?.handleReturn() == true { return }
        case 120: // F2 renames, like Windows.
            model?.beginRename()
            return
        case 51, 117: // Delete, Forward Delete.
            if flags.contains([.command, .option]) {
                model?.askDeleteImmediately()
                return
            } else if command {
                model?.trashSelection()
                return
            } else if flags.isDisjoint(with: [.shift, .control, .option]),
                      Prefs.defaults.bool(forKey: Prefs.returnOpensItems) {
                // Delete alone trashes in the Windows habit (S-016).
                model?.trashSelection()
                return
            }
        case 53: // Escape forgets the cut items.
            if FileClipboard.shared.isCutActive {
                FileClipboard.shared.clearCut()
                return
            }
        case 49 where !command:
            toggleQuickLook()
            return
        case 125 where command:
            model?.open()
            return
        case 126 where command:
            model?.goUp()
            return
        default:
            break
        }
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

extension DetailsCoordinator: NSTextFieldDelegate {
    func beginRename(_ url: URL) {
        guard let table, let row = rowOf[url], renaming == nil else { return }
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
        let nameColumn = table.column(withIdentifier: DetailsColumn.name.identifier)
        guard nameColumn >= 0, let cell = table.view(atColumn: nameColumn, row: row, makeIfNecessary: true) as? NSTableCellView,
              let field = cell.textField else { return }
        renaming = url
        renameField = field
        renameError = nil
        field.isEditable = true
        field.isSelectable = true
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.textColor = .labelColor
        field.focusRingType = .exterior
        field.delegate = self
        table.window?.makeFirstResponder(field)
        // The name is selected without its extension, like the Finder.
        let item = items[row]
        let stem = Naming.split(item.name, isFolder: item.isFolder).stem
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: (stem as NSString).length)
    }

    /// Ends editing; `keep` false puts the old name back.
    func endRename(keep: Bool = false) {
        pendingRename = nil
        guard let field = renameField, let url = renaming else { return }
        renaming = nil
        renameField = nil
        if !keep { field.stringValue = url.lastPathComponent }
        field.isEditable = false
        field.isSelectable = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = nil
        table?.window?.makeFirstResponder(table)
        update()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === renameField else { return false }
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            endRename()
        case #selector(NSResponder.insertNewline(_:)):
            commitRename(step: 0)
        case #selector(NSResponder.insertTab(_:)):
            commitRename(step: 1)
        case #selector(NSResponder.insertBacktab(_:)):
            commitRename(step: -1)
        default:
            return false
        }
        return true
    }

    /// Clicking elsewhere saves the name, like the Finder; a name that can't be used is dropped.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === renameField, let url = renaming else { return }
        let name = field.stringValue
        if NameCheck.problem(renaming: url, to: name) != nil
            || NameCheck.extensionChange(from: url.lastPathComponent, to: name, isFolder: isFolder(url)) != nil {
            endRename()
        } else {
            endRename(keep: true)
            model.rename(url, to: name)
        }
    }

    /// Return saves; Tab saves and renames the next item (`step` 1) or the one before (-1).
    func commitRename(step: Int) {
        guard let field = renameField, let url = renaming, let row = rowOf[url] else { return }
        let name = field.stringValue
        let neighbor = step == 0 ? nil : items.indices.contains(row + step) ? items[row + step].url : nil
        if let problem = NameCheck.problem(renaming: url, to: name) {
            renameError = problem.message(name)
            showError(renameError ?? "", on: field)
            NSSound.beep()
            return
        }
        if let change = NameCheck.extensionChange(from: url.lastPathComponent, to: name, isFolder: isFolder(url)) {
            endRename(keep: true)
            model.askExtension(url, newName: name, change: change, next: neighbor)
            return
        }
        endRename(keep: true)
        if let message = model.rename(url, to: name, next: neighbor) {
            renameError = message
        }
    }

    private func isFolder(_ url: URL) -> Bool {
        rowOf[url].map { items[$0].isFolder } ?? false
    }

    private func showError(_ message: String, on field: NSTextField) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView:
            Label(message, systemImage: "exclamationmark.triangle")
                .padding(Space.md)
                .fixedSize())
        popover.show(relativeTo: field.bounds, of: field, preferredEdge: .maxY)
    }

    // MARK: Right-click menu

    func contextMenu(onItems: Bool) -> NSMenu {
        let menu = NSMenu()
        let model = model
        func add(_ title: String, _ action: @escaping () -> Void) {
            menu.addItem(MenuAction.item(title, handler: action))
        }
        if onItems {
            add(String(localized: "Open")) { model.open() }
            add(String(localized: "Quick Look")) { model.quickLook?() }
            menu.addItem(.separator())
            add(String(localized: "Rename")) { model.beginRename() }
            add(String(localized: "Move to Trash")) { model.trashSelection() }
            menu.addItem(.separator())
            add(String(localized: "Cut")) { model.cutSelection() }
            add(String(localized: "Copy")) { model.copySelection() }
        }
        if model.canPaste { add(String(localized: "Paste")) { model.paste() } }
        if menu.items.last.map({ !$0.isSeparatorItem }) ?? false { menu.addItem(.separator()) }
        add(String(localized: "New Folder")) { model.newFolder() }
        let newFile = NSMenuItem(title: String(localized: "New File"), action: nil, keyEquivalent: "")
        newFile.submenu = Self.templateMenu { model.newFile($0) }
        menu.addItem(newFile)
        return menu
    }

    static func templateMenu(_ make: @escaping (FileTemplate) -> Void) -> NSMenu {
        let menu = NSMenu()
        for group in FileTemplate.Group.allCases {
            menu.addItem(.sectionHeader(title: group.title))
            for template in FileTemplate.all where template.group == group {
                menu.addItem(MenuAction.item(template.title) { make(template) })
            }
        }
        return menu
    }

    // MARK: Drag and drop (S-018)

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        url(at: row) as NSURL?
    }

    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        let urls = droppedURLs(info)
        guard !urls.isEmpty else { return [] }
        let destination: URL
        if operation == .on, items.indices.contains(row), items[row].isFolder, !urls.contains(items[row].url) {
            destination = items[row].url
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
        let destination = row >= 0 && items.indices.contains(row) && items[row].isFolder ? items[row].url : model.folder
        let kind = dropKind(urls, into: destination, info: info)
        guard !urls.isEmpty, !DropRule.isNoOp(sources: urls, destination: destination, kind: kind) else { return false }
        model.transfer(kind, urls, into: destination)
        return true
    }

    private func droppedURLs(_ info: any NSDraggingInfo) -> [URL] {
        FilePasteboard.read(from: info.draggingPasteboard)
    }

    /// ⌥ narrows the operations to copy, ⌘ to generic (a move).
    private func dropKind(_ urls: [URL], into destination: URL, info: any NSDraggingInfo) -> TransferKind {
        let mask = info.draggingSourceOperationMask
        return DropRule.kind(sources: urls, destination: destination, option: mask == .copy, command: mask == .generic)
    }

    /// A folder held under a drag for 0.7 s opens, so the drop can go deeper.
    func spring(_ row: Int) {
        guard row != springRow, items.indices.contains(row) else { return }
        cancelSpring()
        springRow = row
        let folder = items[row].url
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
