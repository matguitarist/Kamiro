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
    let groupVersion: Int
    let sizesVersion: Int

    func makeCoordinator() -> DetailsCoordinator { DetailsCoordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = FileTable()
        table.coordinator = context.coordinator
        table.style = .inset
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        // Name grows and shrinks with the window; once it's at its smallest, the next columns give
        // way, so the inspector or a narrow window never pushes Size and Kind out of sight.
        table.columnAutoresizingStyle = .reverseSequentialColumnAutoresizingStyle
        table.focusRingType = .none
        table.allowsTypeSelect = true
        table.floatsGroupRows = true
        // Every column exists; the folder's view says which show, in what order (S-021).
        for column in ListColumn.allCases {
            let tableColumn = NSTableColumn(identifier: column.identifier)
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.minWidth = column.minWidth
            if let key = column.sortKey {
                tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: key.rawValue, ascending: column.ascendingFirst)
            }
            tableColumn.headerCell.alignment = column == .size ? .right : .left
            tableColumn.headerToolTip = column.title
            table.addTableColumn(tableColumn)
        }
        let headerMenu = NSMenu()
        headerMenu.delegate = context.coordinator
        table.headerView?.menu = headerMenu
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
        // Extra columns (S-021) can be wider than the window.
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update()
    }
}

extension ListColumn {
    var identifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier(rawValue) }

    var title: String {
        switch self {
        case .name: String(localized: "Name")
        case .modified: String(localized: "Date Modified")
        case .created: String(localized: "Date Created")
        case .added: String(localized: "Date Added")
        case .size: String(localized: "Size")
        case .kind: String(localized: "Kind")
        case .ext: String(localized: "Extension")
        case .tags: String(localized: "Tags")
        case .comments: String(localized: "Comments")
        }
    }

    var width: CGFloat {
        switch self {
        case .name: 320
        case .modified, .created, .added: 180
        case .size: 84
        case .kind: 150
        case .ext: 84
        case .tags: 120
        case .comments: 200
        }
    }

    var minWidth: CGFloat { self == .name ? 160 : 60 }

    /// Dates and sizes sort newest and biggest first on the first click, like the Finder.
    var ascendingFirst: Bool { ![.modified, .created, .added, .size].contains(self) }
}

final class DetailsCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    let model: BrowserModel
    weak var table: FileTable?
    /// Items, with a header row before each group when grouped (S-022).
    private(set) var rows: [ListRow] = []
    private(set) var rowOf: [URL: Int] = [:]
    private var version = -1
    private var groupVersion = -1
    private var sizesVersion = -1

    private var reveal = -1
    private var focus = -1
    private var cutVersion = -1
    private var renameToken = 0
    private var viewVersion = -1
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

    func item(at row: Int) -> FileItem? {
        guard rows.indices.contains(row), case .item(let item) = rows[row] else { return nil }
        return item
    }

    func url(at row: Int) -> URL? { item(at: row)?.url }

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
        if viewVersion != model.viewVersion {
            viewVersion = model.viewVersion
            applyColumns()
        }
        if version != model.itemsVersion || groupVersion != model.groupVersion {
            if version != model.itemsVersion { FileExtras.shared.forget() }
            version = model.itemsVersion
            groupVersion = model.groupVersion
            rows = ListRow.make(model.items, by: model.groupBy, collapsed: model.collapsedGroups, sizes: model.folderSizes)
            rowOf = Dictionary(rows.enumerated().compactMap { index, row in
                if case .item(let item) = row { (item.url, index) } else { nil }
            }, uniquingKeysWith: { first, _ in first })
            table.reloadData()
            cutVersion = FileClipboard.shared.version
            sizesVersion = model.sizesVersion
        }
        if sizesVersion != model.sizesVersion {
            sizesVersion = model.sizesVersion
            let column = table.column(withIdentifier: ListColumn.size.identifier)
            if column >= 0 {
                table.reloadData(forRowIndexes: IndexSet(integersIn: 0..<rows.count), columnIndexes: [column])
            }
        }
        if cutVersion != FileClipboard.shared.version {
            cutVersion = FileClipboard.shared.version
            table.reloadData(forRowIndexes: IndexSet(integersIn: 0..<rows.count),
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

    /// Shows the folder's columns in its order and widths, and its sort.
    private func applyColumns() {
        guard let table else { return }
        let shown = model.columns
        for (index, column) in shown.enumerated() {
            let current = table.column(withIdentifier: column.identifier)
            if current >= 0, current != index { table.moveColumn(current, toColumn: index) }
        }
        for tableColumn in table.tableColumns {
            guard let column = ListColumn(rawValue: tableColumn.identifier.rawValue) else { continue }
            tableColumn.isHidden = !shown.contains(column)
            tableColumn.width = model.widths[column].map { CGFloat($0) } ?? column.width
        }
        // Saved widths can be wider than the room there is: fit them (Name gives first).
        table.sizeToFit()
        let sort = NSSortDescriptor(key: model.order.key.rawValue, ascending: model.order.ascending)
        if table.sortDescriptors.first != sort { table.sortDescriptors = [sort] }
    }

    func tableViewColumnDidMove(_ notification: Notification) {
        guard !applying, let table else { return }
        model.columns = table.tableColumns.filter { !$0.isHidden }.compactMap { ListColumn(rawValue: $0.identifier.rawValue) }
    }

    func tableViewColumnDidResize(_ notification: Notification) {
        // Only widths people drag are remembered, not the Name column following the window.
        guard !applying, table?.inLiveResize == false, (table?.headerView?.resizedColumn ?? -1) >= 0,
              let tableColumn = notification.userInfo?["NSTableColumn"] as? NSTableColumn,
              let column = ListColumn(rawValue: tableColumn.identifier.rawValue), !tableColumn.isHidden else { return }
        model.setWidth(Double(tableColumn.width), of: column)
    }

    // MARK: The header's right-click menu (S-021)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for column in ListColumn.allCases where column != .name {
            let item = MenuAction.item(column.title) { [weak self] in self?.model.toggleColumn(column) }
            item.state = model.columns.contains(column) ? .on : .off
            menu.addItem(item)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if rows.indices.contains(row), case .header = rows[row] { true } else { false }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { item(at: row) != nil }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if rows.indices.contains(row), case .header(let header) = rows[row] {
            let view = tableView.makeView(withIdentifier: GroupHeaderView.identifier, owner: nil) as? GroupHeaderView ?? GroupHeaderView()
            view.show(header) { [weak self] in self?.model.toggleGroup(header.id) }
            return view
        }
        guard let tableColumn, let column = ListColumn(rawValue: tableColumn.identifier.rawValue),
              let item = item(at: row) else { return nil }
        let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: nil) as? NSTableCellView
            ?? Self.makeCell(column)
        cell.textField?.stringValue = Self.text(column, item, sizes: model.folderSizes)
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
        tableColumn?.identifier == ListColumn.name.identifier ? item(at: row)?.name : nil
    }

    @objc func doubleClicked(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard let url = url(at: row) else { return }
        // ⌥ opens a folder in a new window, ⌘ in a new tab (S-030).
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        model.open([url], newWindow: flags.contains(.option), newTab: flags.contains(.command))
    }

    // MARK: Cells

    static func makeCell(_ column: ListColumn) -> NSTableCellView {
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

    /// A folder's size, or "—" until it's measured (S-023).
    static func sizeText(_ item: FileItem, sizes: [URL: Int64]) -> String {
        guard let size = item.size ?? sizes[item.url] else { return "—" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private static func text(_ column: ListColumn, _ item: FileItem, sizes: [URL: Int64]) -> String {
        switch column {
        case .name: item.name
        case .modified: item.modified.map(dates.string(from:)) ?? "--"
        case .created: item.created.map(dates.string(from:)) ?? "--"
        case .added: item.added.map(dates.string(from:)) ?? "--"
        case .size: sizeText(item, sizes: sizes)
        case .kind: KindCache.shared.kind(of: item)
        case .ext: item.isFolder ? "" : item.url.pathExtension
        case .tags: FileExtras.shared.tags(of: item.url).joined(separator: ", ")
        case .comments: FileExtras.shared.comment(of: item.url)
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

/// One row of the details view: an item, or a group's header (S-022).
enum ListRow {
    case header(GroupHeader)
    case item(FileItem)

    static func make(_ items: [FileItem], by: GroupBy, collapsed: Set<String>, sizes: [URL: Int64]) -> [ListRow] {
        guard by != .none else { return items.map(ListRow.item) }
        return Grouping.groups(items, by: by, sizes: sizes).flatMap { group -> [ListRow] in
            let shut = collapsed.contains(group.key.id)
            let header = ListRow.header(GroupHeader(id: group.key.id, title: group.key.title, count: group.items.count, collapsed: shut))
            return shut ? [header] : [header] + group.items.map(ListRow.item)
        }
    }
}

struct GroupHeader {
    let id: String
    let title: String
    let count: Int
    let collapsed: Bool
}

/// A group's header row: a chevron that folds the group, its name and how many items.
final class GroupHeaderView: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("group")
    private let chevron = NSButton()
    private let title = NSTextField(labelWithString: "")
    private let count = NSTextField(labelWithString: "")
    private var toggle: () -> Void = {}

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        chevron.bezelStyle = .flexiblePush
        chevron.isBordered = false
        chevron.imagePosition = .imageOnly
        chevron.target = self
        chevron.action = #selector(clicked)
        chevron.contentTintColor = .secondaryLabelColor
        title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        count.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [chevron, title, count])
        stack.spacing = Space.xs
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.xs),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ header: GroupHeader, toggle: @escaping () -> Void) {
        self.toggle = toggle
        title.stringValue = header.title
        count.stringValue = String(localized: "\(header.count) items")
        let symbol = header.collapsed ? "chevron.right" : "chevron.down"
        chevron.image = NSImage(systemSymbolName: symbol, accessibilityDescription: header.collapsed
                                ? String(localized: "Show Group") : String(localized: "Hide Group"))
        chevron.toolTip = header.collapsed ? String(localized: "Show Group") : String(localized: "Hide Group")
        setAccessibilityLabel(header.title)
    }

    @objc private func clicked() { toggle() }

    /// A click anywhere on the header folds or unfolds the group, like the Finder.
    override func mouseDown(with event: NSEvent) { toggle() }
}

extension GroupKey {
    var title: String {
        switch self {
        case .today: String(localized: "Today")
        case .yesterday: String(localized: "Yesterday")
        case .previous7: String(localized: "Previous 7 Days")
        case .previous30: String(localized: "Previous 30 Days")
        case .month(let year, let month):
            Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)).map {
                let text = Self.months.string(from: $0)
                return text.prefix(1).uppercased() + text.dropFirst()
            } ?? "\(month)"
        case .year(let year): String(year)
        case .noDate: String(localized: "No Date")
        case .kind(let kind): kind
        case .size(let band): band.title
        case .letter(let letter): letter == "0-9" ? "0–9" : letter
        }
    }

    private static let months: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("LLLL")
        return formatter
    }()
}

extension SizeBand {
    var title: String {
        switch self {
        case .huge: String(localized: "Over 1 GB")
        case .large: String(localized: "100 MB to 1 GB")
        case .medium: String(localized: "1 MB to 100 MB")
        case .small: String(localized: "Under 1 MB")
        case .empty: String(localized: "Zero Bytes")
        case .unknown: String(localized: "Size Unknown")
        }
    }
}

extension GroupBy {
    var title: String {
        switch self {
        case .none: String(localized: "None")
        case .kind: String(localized: "Kind")
        case .modified: String(localized: "Date Modified")
        case .size: String(localized: "Size")
        case .name: String(localized: "Name")
        }
    }
}

/// Tags and Finder comments, read only for the rows on screen (they're slow to read for a
/// whole folder: docs/research, Benchmark), and forgotten when the folder is read again.
final class FileExtras {
    static let shared = FileExtras()
    private var tags: [URL: [String]] = [:]
    private var comments: [URL: String] = [:]

    func forget() {
        tags.removeAll()
        comments.removeAll()
    }

    func tags(of url: URL) -> [String] {
        if let hit = tags[url] { return hit }
        let names = (try? url.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
        tags[url] = names
        return names
    }

    func comment(of url: URL) -> String {
        if let hit = comments[url] { return hit }
        let item = MDItemCreateWithURL(nil, url as CFURL)
        let text = item.flatMap { MDItemCopyAttribute($0, kMDItemFinderComment) as? String } ?? ""
        comments[url] = text
        return text
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
