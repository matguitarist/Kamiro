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
    let cutVersion: Int
    let renameToken: Int

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
        model.details = context.coordinator
        model.quickLook = { [weak table] in table?.toggleQuickLook() }
        // Drag items out to other apps, and drop files on folders or the list (S-018).
        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: true)
        table.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: false)
        table.draggingDestinationFeedbackStyle = .regular

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
    private(set) var items: [FileItem] = []
    private(set) var rowOf: [URL: Int] = [:]
    private var version = -1
    private var reveal = -1
    private var focus = -1
    private var cutVersion = -1
    private var renameToken = 0
    private var applying = false
    /// The name being edited; the list doesn't reload meanwhile.
    var rename: InlineRename?
    var renaming: URL? { rename?.url }
    /// The last rename error shown, for the self-test.
    var renameError: String?
    var springTask: Task<Void, Never>?
    /// A rename asked for an item the list doesn't show yet (a new folder before the reload).
    var pendingRename: URL?
    var springRow = -1

    init(model: BrowserModel) { self.model = model }

    func url(at row: Int) -> URL? { items.indices.contains(row) ? items[row].url : nil }

    func update() {
        guard let table else { return }
        // A reload would end the rename; it waits until the name is saved. Sending the
        // keyboard back to the list saves it, like a click elsewhere.
        if renaming != nil {
            guard focus != model.focusToken else { return }
            table.window?.makeFirstResponder(table)
            if renaming != nil { endRename() }
            return
        }
        applying = true
        defer { applying = false }
        if version != model.itemsVersion {
            version = model.itemsVersion
            items = model.items
            rowOf = Dictionary(items.enumerated().map { ($1.url, $0) }, uniquingKeysWith: { first, _ in first })
            table.reloadData()
            cutVersion = FileClipboard.shared.version
        }
        if cutVersion != FileClipboard.shared.version {
            cutVersion = FileClipboard.shared.version
            table.reloadData(forRowIndexes: IndexSet(integersIn: 0..<items.count),
                             columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
        }
        let wanted = IndexSet(model.selection.compactMap { rowOf[$0] })
        if wanted != table.selectedRowIndexes {
            table.selectRowIndexes(wanted, byExtendingSelection: false)
        }
        if reveal != model.revealToken {
            reveal = model.revealToken
            table.scrollRowToVisible(wanted.first ?? 0)
        }
        // A new list (after a folder that couldn't open) isn't in its window yet: keep the
        // request until it is (FileTable.viewDidMoveToWindow).
        if focus != model.focusToken, let window = table.window {
            focus = model.focusToken
            window.makeFirstResponder(table)
        }
        if renameToken != model.renameToken {
            renameToken = model.renameToken
            pendingRename = model.renameTarget
        }
        if let target = pendingRename, rowOf[target] != nil {
            pendingRename = nil
            beginRename(target)
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
        // Hidden items (S-024) and cut items (S-011) show dimmed.
        cell.alphaValue = item.isHidden || FileClipboard.shared.isCut(item.url) ? 0.5 : 1
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

    static func makeCell(_ column: DetailsColumn) -> NSTableCellView {
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
