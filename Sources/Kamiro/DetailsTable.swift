import AppKit
import KamiroKit
import Quartz
import SwiftUI

/// The details view: an NSTableView, because SwiftUI's Table hangs on large folders
/// (docs/research/file-managers.md). The values passed in are what SwiftUI watches.
struct DetailsTable: NSViewRepresentable {
    let model: BrowserModel
    let version: Int
    let selection: Set<URL>
    let reveal: Int
    let focus: Int

    func makeCoordinator() -> DetailsCoordinator { DetailsCoordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = FileTable()
        table.coordinator = context.coordinator
        table.style = .inset
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.focusRingType = .none
        table.allowsTypeSelect = true
        for column in DetailsColumn.allCases {
            let tableColumn = NSTableColumn(identifier: column.identifier)
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.minWidth = column.minWidth
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.rawValue, ascending: column.ascendingFirst)
            tableColumn.headerCell.alignment = column == .size ? .right : .left
            table.addTableColumn(tableColumn)
        }
        table.autosaveName = "Kamiro.Details"
        table.autosaveTableColumns = true
        table.sortDescriptors = [NSSortDescriptor(key: model.order.key.rawValue, ascending: model.order.ascending)]
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(DetailsCoordinator.doubleClicked(_:))
        context.coordinator.table = table
        model.quickLook = { [weak table] in table?.toggleQuickLook() }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update()
    }
}

enum DetailsColumn: String, CaseIterable {
    case name, modified, size, kind

    var identifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier(rawValue) }

    var title: String {
        switch self {
        case .name: String(localized: "Name")
        case .modified: String(localized: "Date Modified")
        case .size: String(localized: "Size")
        case .kind: String(localized: "Kind")
        }
    }

    var width: CGFloat {
        switch self {
        case .name: 320
        case .modified: 180
        case .size: 84
        case .kind: 150
        }
    }

    var minWidth: CGFloat { self == .name ? 160 : 60 }

    /// Dates and sizes sort newest and biggest first on the first click, like the Finder.
    var ascendingFirst: Bool { self == .name || self == .kind }
}

final class DetailsCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let model: BrowserModel
    weak var table: FileTable?
    private var items: [FileItem] = []
    private var rowOf: [URL: Int] = [:]
    private var version = -1
    private var reveal = -1
    private var focus = -1
    private var applying = false

    init(model: BrowserModel) { self.model = model }

    func url(at row: Int) -> URL? { items.indices.contains(row) ? items[row].url : nil }

    func update() {
        guard let table else { return }
        applying = true
        defer { applying = false }
        if version != model.itemsVersion {
            version = model.itemsVersion
            items = model.items
            rowOf = Dictionary(items.enumerated().map { ($1.url, $0) }, uniquingKeysWith: { first, _ in first })
            table.reloadData()
        }
        let wanted = IndexSet(model.selection.compactMap { rowOf[$0] })
        if wanted != table.selectedRowIndexes {
            table.selectRowIndexes(wanted, byExtendingSelection: false)
        }
        if reveal != model.revealToken {
            reveal = model.revealToken
            table.scrollRowToVisible(wanted.first ?? 0)
        }
        if focus != model.focusToken {
            focus = model.focusToken
            table.window?.makeFirstResponder(table)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, let column = DetailsColumn(rawValue: tableColumn.identifier.rawValue),
              items.indices.contains(row) else { return nil }
        let item = items[row]
        let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: nil) as? NSTableCellView
            ?? Self.makeCell(column)
        cell.textField?.stringValue = Self.text(column, item)
        if column == .name {
            cell.imageView?.image = IconCache.shared.icon(for: item)
            cell.toolTip = item.name
        }
        // Hidden items show dimmed (S-024).
        cell.alphaValue = item.isHidden ? 0.5 : 1
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !applying, let table else { return }
        model.selection = Set(table.selectedRowIndexes.compactMap(url(at:)))
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.reloadData()
        }
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let first = tableView.sortDescriptors.first, let key = SortKey(rawValue: first.key ?? "") else { return }
        model.order = ItemOrder(key: key, ascending: first.ascending, foldersFirst: model.order.foldersFirst)
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        tableColumn?.identifier == DetailsColumn.name.identifier && items.indices.contains(row) ? items[row].name : nil
    }

    @objc func doubleClicked(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard let url = url(at: row) else { return }
        let option = NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
        model.open([url], newWindow: option)
    }

    // MARK: Cells

    private static func makeCell(_ column: DetailsColumn) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = column.identifier
        let text = NSTextField(labelWithString: "")
        text.translatesAutoresizingMaskIntoConstraints = false
        text.lineBreakMode = column == .name ? .byTruncatingMiddle : .byTruncatingTail
        text.textColor = column == .name ? .labelColor : .secondaryLabelColor
        text.alignment = column == .size ? .right : .left
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cell.addSubview(text)
        cell.textField = text
        var constraints = [
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -Space.xs),
        ]
        if column == .name {
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(image)
            cell.imageView = image
            constraints += [
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: Space.xs),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                image.heightAnchor.constraint(equalToConstant: 16),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: Space.sm - 2),
            ]
        } else {
            constraints.append(text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: Space.xs))
        }
        NSLayoutConstraint.activate(constraints)
        return cell
    }

    private static func text(_ column: DetailsColumn, _ item: FileItem) -> String {
        switch column {
        case .name: item.name
        case .modified: item.modified.map(dates.string(from:)) ?? "--"
        case .size: item.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "--"
        case .kind: KindCache.shared.kind(of: item)
        }
    }

    /// "Today at 14:03", like the Finder.
    private static let dates: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}

/// The table's keys: Space for Quick Look, ⌘↓ to open, ⌘↑ to go up, Return per the setting.
/// Arrow shortcuts live here, not in the menu bar, where they would fire in the address field.
final class FileTable: NSTableView, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    weak var coordinator: DetailsCoordinator?

    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 36, 76:
            if coordinator?.model.handleReturn() == true { return }
        case 49 where !command:
            toggleQuickLook()
            return
        case 125 where command:
            coordinator?.model.open()
            return
        case 126 where command:
            coordinator?.model.goUp()
            return
        default:
            break
        }
        super.keyDown(with: event)
    }

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

/// File icons: one per extension for plain files, one per path for folders and apps
/// (they can have their own icons).
final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]

    func icon(for item: FileItem, size: CGFloat = 16) -> NSImage {
        let ext = item.url.pathExtension.lowercased()
        let key = (item.isFolder || item.isPackage || ext.isEmpty ? item.url.path : "ext:" + ext) + "@\(size)"
        if let hit = cache[key] { return hit }
        let image = NSWorkspace.shared.icon(forFile: item.url.path)
        image.size = NSSize(width: size, height: size)
        cache[key] = image
        return image
    }
}
