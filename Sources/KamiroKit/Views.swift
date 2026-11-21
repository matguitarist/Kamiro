import Foundation

/// How a folder shows its items: icons, details (rows with columns), or columns.
public enum ViewMode: String, Codable, Sendable, CaseIterable {
    case icons, details, columns
}

/// The icon view's icon sizes, in points.
public enum IconSize {
    public static let range: ClosedRange<Double> = 32...256
    public static let standard: Double = 64

    /// The thumbnail size to ask for: a few fixed steps, so dragging the slider reuses them.
    public static func thumbnailStep(_ points: Double) -> Double {
        [64, 128, 256].first { $0 >= points } ?? 256
    }
}

/// A column of the details view. Name is always shown.
public enum ListColumn: String, Codable, Sendable, CaseIterable {
    case name, modified, created, added, size, kind, ext, tags, comments, cloud

    /// What a new folder shows: the Finder's four.
    public static let standard: [ListColumn] = [.name, .modified, .size, .kind]

    /// The sort a click on its header gives; Tags and Comments don't sort.
    public var sortKey: SortKey? {
        switch self {
        case .name: .name
        case .modified: .modified
        case .created: .created
        case .added: .added
        case .size: .size
        case .kind: .kind
        case .ext: .ext
        case .tags, .comments, .cloud: nil
        }
    }
}

/// How one folder is shown: the view, the sort, and the details view's columns.
public struct FolderView: Codable, Equatable, Sendable {
    public var mode: ViewMode
    public var order: ItemOrder
    /// Shown columns, left to right; always starts with Name.
    public var columns: [ListColumn]
    /// Column widths people dragged, in points.
    public var widths: [ListColumn: Double]
    public var groupBy: GroupBy

    public init(mode: ViewMode = .details, order: ItemOrder = ItemOrder(), columns: [ListColumn] = ListColumn.standard,
                widths: [ListColumn: Double] = [:], groupBy: GroupBy = .none) {
        self.mode = mode
        self.order = order
        self.columns = Self.clean(columns)
        self.widths = widths
        self.groupBy = groupBy
    }

    /// A file written by an older Kamiro opens: missing settings take their defaults.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let standard = FolderView()
        mode = (try? values.decodeIfPresent(ViewMode.self, forKey: .mode)) ?? standard.mode
        order = (try? values.decodeIfPresent(ItemOrder.self, forKey: .order)) ?? standard.order
        let names = (try? values.decodeIfPresent([String].self, forKey: .columns)) ?? nil
        columns = Self.clean(names.map { $0.compactMap(ListColumn.init(rawValue:)) } ?? standard.columns)
        let sizes = (try? values.decodeIfPresent([String: Double].self, forKey: .widths)) ?? nil
        widths = Dictionary(uniqueKeysWithValues: (sizes ?? [:]).compactMap { key, value in ListColumn(rawValue: key).map { ($0, value) } })
        groupBy = (try? values.decodeIfPresent(GroupBy.self, forKey: .groupBy)) ?? standard.groupBy
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(mode, forKey: .mode)
        try values.encode(order, forKey: .order)
        try values.encode(columns.map(\.rawValue), forKey: .columns)
        try values.encode(Dictionary(uniqueKeysWithValues: widths.map { ($0.key.rawValue, $0.value) }), forKey: .widths)
        try values.encode(groupBy, forKey: .groupBy)
    }

    private enum CodingKeys: String, CodingKey { case mode, order, columns, widths, groupBy }

    /// Name first, each column once.
    static func clean(_ columns: [ListColumn]) -> [ListColumn] {
        var seen: Set<ListColumn> = [.name]
        return [.name] + columns.filter { seen.insert($0).inserted }
    }

    /// Shows or hides a column; a shown one goes at the end. Name can't be hidden.
    public mutating func toggle(_ column: ListColumn) {
        guard column != .name else { return }
        if let index = columns.firstIndex(of: column) {
            columns.remove(at: index)
            if order.key == column.sortKey { order = ItemOrder(foldersFirst: order.foldersFirst) }
        } else {
            columns.append(column)
        }
    }
}

/// Every folder's view, and the one new folders get. Kept in a small JSON file.
public struct ViewMemory: Codable, Equatable, Sendable {
    public var standard: FolderView
    public var folders: [String: FolderView]

    public init(standard: FolderView = FolderView(), folders: [String: FolderView] = [:]) {
        self.standard = standard
        self.folders = folders
    }

    /// A cloud folder never changed shows the Cloud Status column after Name, like the Finder (S-058).
    public func view(for folder: URL, inCloud: Bool = false) -> FolderView {
        if let view = folders[folder.canonical.path] { return view }
        guard inCloud, !standard.columns.contains(.cloud) else { return standard }
        var view = standard
        view.columns.insert(.cloud, at: 1)
        return view
    }

    public mutating func remember(_ view: FolderView, for folder: URL) {
        folders[folder.canonical.path] = view
    }

    /// "Use as Defaults": new folders, and folders never changed, show this.
    public mutating func useAsDefaults(_ view: FolderView) {
        standard = view
    }

    /// The view new folders open in (Settings › Views). Folders already shown keep theirs.
    public mutating func setStandardMode(_ mode: ViewMode) {
        standard.mode = mode
    }

    /// Shows or hides a column in new folders' details (Settings › Views). Name stays.
    public mutating func setStandardColumn(_ column: ListColumn, shown: Bool) {
        guard standard.columns.contains(column) != shown else { return }
        standard.toggle(column)
    }

    /// How new folders sort (Settings › Views): dates and sizes newest and largest first, like the Finder.
    public mutating func setStandardSort(_ key: SortKey) {
        standard.order = ItemOrder(key: key, ascending: key == .name || key == .kind || key == .ext,
                                   foldersFirst: standard.order.foldersFirst)
    }

    public mutating func setStandardGroup(_ group: GroupBy) {
        standard.groupBy = group
    }

    /// Folders on top of files in every folder, sorted any way (Settings › Views), like the
    /// Finder's "Keep folders on top": one choice for all, so folders already shown follow it too.
    public var foldersFirst: Bool { standard.order.foldersFirst }

    public mutating func setFoldersFirst(_ on: Bool) {
        standard.order.foldersFirst = on
        for key in folders.keys { folders[key]?.order.foldersFirst = on }
    }
}

/// Reads and writes ViewMemory. A missing or damaged file starts over with the defaults.
public final class ViewStore {
    public let url: URL
    public private(set) var memory: ViewMemory

    public init(url: URL) {
        self.url = url
        memory = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(ViewMemory.self, from: $0) } ?? ViewMemory()
    }

    public func view(for folder: URL, inCloud: Bool = false) -> FolderView { memory.view(for: folder, inCloud: inCloud) }

    public func remember(_ view: FolderView, for folder: URL) {
        memory.remember(view, for: folder)
        save()
    }

    public func useAsDefaults(_ view: FolderView) {
        memory.useAsDefaults(view)
        save()
    }

    public func setStandardMode(_ mode: ViewMode) {
        memory.setStandardMode(mode)
        save()
    }

    /// Any other change to the defaults or to every folder (Settings › Views), saved at once.
    public func change(_ body: (inout ViewMemory) -> Void) {
        body(&memory)
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(memory) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
