import AppKit
import KamiroKit
import Quartz
import SwiftUI

/// What the details, icon and column views share: their keys, renaming in place,
/// the right-click menu, and Quick Look's list of items.

/// The keys every file view handles the same way. Arrow, Return and Delete keys live here,
/// not in the menu bar, where they would fire in the address field or while renaming.
enum FileKeys {
    /// True when the key was handled.
    static func handle(_ event: NSEvent, model: BrowserModel?) -> Bool {
        guard let model else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        switch event.keyCode {
        case 36, 76:
            // ⌥↩ opens Properties, like Alt+Enter in Windows.
            if flags == .option {
                model.showProperties()
                return true
            }
            return model.handleReturn()
        case 120: // F2 renames, like Windows.
            model.beginRename()
            return true
        case 51, 117: // Delete, Forward Delete.
            if flags.contains([.command, .option]) {
                model.askDeleteImmediately()
                return true
            } else if command {
                model.trashSelection()
                return true
            } else if flags.isDisjoint(with: [.shift, .control, .option]) {
                // Delete alone trashes too, the Windows habit.
                model.trashSelection()
                return true
            }
        case 53: // Escape forgets the cut items.
            if FileClipboard.shared.isCutActive {
                FileClipboard.shared.clearCut()
                return true
            }
        case 49 where !command:
            model.quickLook?()
            return true
        case 125 where command:
            model.open()
            return true
        case 126 where command:
            model.goUp()
            return true
        default:
            break
        }
        return false
    }
}

/// Quick Look's items and keys for one view: the selection, and arrows sent back to the view.
final class QuickLookSource: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private let urls: () -> [URL]
    private let key: (NSEvent) -> Void

    init(urls: @escaping () -> [URL], key: @escaping (NSEvent) -> Void) {
        self.urls = urls
        self.key = key
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls().count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        let list = urls()
        return list.indices.contains(index) ? list[index] as NSURL : nil
    }

    /// Arrows in the panel move the selection in the view, and the preview follows.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, [123, 124, 125, 126].contains(event.keyCode) else { return false }
        key(event)
        return true
    }

    /// Shows or hides the panel; `responder` takes the keyboard so the panel finds it.
    static func toggle(from responder: NSResponder, in window: NSWindow?, hasSelection: Bool) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible {
            panel.orderOut(nil)
        } else if hasSelection {
            window?.makeFirstResponder(responder)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    static func reloadIfShown() {
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.reloadData()
        }
    }
}

// MARK: - Rename in place (S-014)

/// Renaming one item in place, in any view: the field turns editable, Return saves, Tab saves
/// and moves on, Escape puts the old name back, and a click elsewhere saves, like the Finder.
final class InlineRename: NSObject, NSTextFieldDelegate {
    let url: URL
    let field: NSTextField
    private let model: BrowserModel
    private let isFolder: Bool
    /// The item `step` places after (1) or before (-1) this one, for Tab.
    private let neighbor: (Int) -> URL?
    /// Called once the field is a label again; the view takes the keyboard back.
    private let finished: () -> Void
    /// Shows why a name can't be used.
    var onError: (String) -> Void = { _ in }
    private var ended = false
    private let oldColor: NSColor?

    init(url: URL, field: NSTextField, model: BrowserModel, isFolder: Bool,
         neighbor: @escaping (Int) -> URL?, finished: @escaping () -> Void) {
        self.url = url
        self.field = field
        self.model = model
        self.isFolder = isFolder
        self.neighbor = neighbor
        self.finished = finished
        oldColor = field.textColor
    }

    func begin() {
        field.isEditable = true
        field.isSelectable = true
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.textColor = .labelColor
        field.focusRingType = .exterior
        field.delegate = self
        field.window?.makeFirstResponder(field)
        // The name is selected without its extension, like the Finder.
        let stem = Naming.split(url.lastPathComponent, isFolder: isFolder).stem
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: (stem as NSString).length)
    }

    /// Ends editing; `keep` false puts the old name back.
    func end(keep: Bool = false) {
        guard !ended else { return }
        ended = true
        if !keep { field.stringValue = url.lastPathComponent }
        field.isEditable = false
        field.isSelectable = false
        field.drawsBackground = false
        field.textColor = oldColor
        field.focusRingType = .none
        field.delegate = nil
        finished()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === field else { return false }
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            end()
        case #selector(NSResponder.insertNewline(_:)):
            commit(step: 0)
        case #selector(NSResponder.insertTab(_:)):
            commit(step: 1)
        case #selector(NSResponder.insertBacktab(_:)):
            commit(step: -1)
        default:
            return false
        }
        return true
    }

    /// Clicking elsewhere saves the name, like the Finder; a name that can't be used is dropped.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard !ended, notification.object as? NSTextField === field else { return }
        let name = field.stringValue
        if NameCheck.problem(renaming: url, to: name) != nil
            || NameCheck.extensionChange(from: url.lastPathComponent, to: name, isFolder: isFolder) != nil {
            end()
        } else {
            end(keep: true)
            model.rename(url, to: name)
        }
    }

    /// Return saves; Tab saves and renames the next item (`step` 1) or the one before (-1).
    func commit(step: Int) {
        let name = field.stringValue
        let next = step == 0 ? nil : neighbor(step)
        if let problem = NameCheck.problem(renaming: url, to: name) {
            let message = problem.message(name)
            onError(message)
            showError(message)
            NSSound.beep()
            return
        }
        if let change = NameCheck.extensionChange(from: url.lastPathComponent, to: name, isFolder: isFolder) {
            end(keep: true)
            model.askExtension(url, newName: name, change: change, next: next)
            return
        }
        end(keep: true)
        if let message = model.rename(url, to: name, next: next) { onError(message) }
    }

    private func showError(_ message: String) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView:
            Label(message, systemImage: "exclamationmark.triangle")
                .padding(Space.md)
                .fixedSize())
        popover.show(relativeTo: field.bounds, of: field, preferredEdge: .maxY)
    }
}

// MARK: - Right-click menu (the full one comes with S-033)

extension BrowserModel {
    func contextMenu(onItems: Bool) -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ symbol: String, _ action: @escaping () -> Void) {
            let item = MenuAction.item(title, handler: action)
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        if onItems {
            add(String(localized: "Open"), "arrow.up.forward.app") { [weak self] in self?.open() }
            if isVirtual, selection.count == 1 {
                add(String(localized: "Show in Enclosing Folder"), "folder") { [weak self] in self?.showInEnclosingFolder() }
            }
            add(String(localized: "Quick Look"), "eye") { [weak self] in self?.quickLook?() }
            menu.addItem(.separator())
            add(String(localized: "Rename"), "pencil") { [weak self] in self?.beginRename() }
            add(String(localized: "Move to Trash"), "trash") { [weak self] in self?.trashSelection() }
            menu.addItem(.separator())
            add(String(localized: "Cut"), "scissors") { [weak self] in self?.cutSelection() }
            add(String(localized: "Copy"), "doc.on.doc") { [weak self] in self?.copySelection() }
            menu.addItem(.separator())
            let tags = tagsMenu()
            tags.image = NSImage(systemSymbolName: "tag", accessibilityDescription: nil)
            menu.addItem(tags)
            // Folders only: a file can't be pinned (S-032).
            if !selectedItems.isEmpty, selectedItems.allSatisfy(\.isFolder), !pinTargets.isEmpty {
                add(String(localized: "Pin to Sidebar"), "pin") { [weak self] in self?.pinToSidebar() }
            }
        }
        if canPaste { add(String(localized: "Paste"), "doc.on.clipboard") { [weak self] in self?.paste() } }
        if !isVirtual {
            if menu.items.last.map({ !$0.isSeparatorItem }) ?? false { menu.addItem(.separator()) }
            add(String(localized: "New Folder"), "folder.badge.plus") { [weak self] in self?.newFolder() }
            let newFile = NSMenuItem(title: String(localized: "New File"), action: nil, keyEquivalent: "")
            newFile.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil)
            newFile.submenu = Self.templateMenu { [weak self] in self?.newFile($0) }
            menu.addItem(newFile)
        }
        if onItems || !isVirtual {
            menu.addItem(.separator())
            add(String(localized: "Properties"), "info.circle") { [weak self] in self?.showProperties() }
        }
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

    /// ⌥ narrows a drag's operations to copy, ⌘ to generic (a move).
    func dropKind(_ urls: [URL], into destination: URL, info: any NSDraggingInfo) -> TransferKind {
        let mask = info.draggingSourceOperationMask
        return DropRule.kind(sources: urls, destination: destination, option: mask == .copy, command: mask == .generic)
    }
}
