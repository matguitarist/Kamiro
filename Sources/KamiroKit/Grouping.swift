import Foundation

/// What the details view groups by (View › Group By, S-022).
public enum GroupBy: String, Codable, Sendable, CaseIterable {
    case none, kind, modified, size, name
}

/// Size groups, biggest first.
public enum SizeBand: Int, Sendable, CaseIterable, Comparable {
    case huge, large, medium, small, empty, unknown

    public init(_ bytes: Int64?) {
        guard let bytes else { self = .unknown; return }
        switch bytes {
        case 0: self = .empty
        case ..<1_000_000: self = .small
        case ..<100_000_000: self = .medium
        case ..<1_000_000_000: self = .large
        default: self = .huge
        }
    }

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// One group's place: dates like the Finder's (Today, Yesterday, Previous 7 Days,
/// Previous 30 Days, then this year's months, then years), a kind, a size band, a letter.
public enum GroupKey: Hashable, Sendable {
    case today, yesterday, previous7, previous30
    case month(year: Int, month: Int)
    case year(Int)
    case noDate
    case kind(String)
    case size(SizeBand)
    /// A letter, "0-9" for digits, "#" for anything else.
    case letter(String)

    /// Stays the same between reads of a folder, for collapsed groups.
    public var id: String {
        switch self {
        case .today: "today"
        case .yesterday: "yesterday"
        case .previous7: "previous7"
        case .previous30: "previous30"
        case .month(let year, let month): "month-\(year)-\(month)"
        case .year(let year): "year-\(year)"
        case .noDate: "nodate"
        case .kind(let kind): "kind-\(kind)"
        case .size(let band): "size-\(band.rawValue)"
        case .letter(let letter): "letter-\(letter)"
        }
    }

    /// Dates newest first, sizes biggest first, kinds and letters A to Z.
    fileprivate func comesBefore(_ other: GroupKey) -> Bool {
        switch (self, other) {
        case (.kind(let a), .kind(let b)), (.letter(let a), .letter(let b)):
            return a.localizedStandardCompare(b) == .orderedAscending
        case (.size(let a), .size(let b)):
            return a < b
        default:
            return dateRank < other.dateRank
        }
    }

    private var dateRank: Int {
        switch self {
        case .today: 0
        case .yesterday: 1
        case .previous7: 2
        case .previous30: 3
        case .month(let year, let month): 100_000_000 - (year * 12 + month)
        case .year(let year): 200_000_000 - year
        case .noDate: Int.max
        default: 0
        }
    }
}

public struct ItemGroup: Equatable, Sendable {
    public let key: GroupKey
    public var items: [FileItem]
}

public enum Grouping {
    /// Splits sorted items into groups; each group keeps the items' order.
    /// `sizes` adds folder sizes as they're computed (S-023).
    public static func groups(_ items: [FileItem], by: GroupBy, sizes: [URL: Int64] = [:], kinds: KindCache = .shared,
                              now: Date = .now, calendar: Calendar = .current) -> [ItemGroup] {
        guard by != .none else { return [ItemGroup(key: .noDate, items: items)] }
        var order: [GroupKey] = []
        var members: [GroupKey: [FileItem]] = [:]
        for item in items {
            let key: GroupKey = switch by {
            case .kind: .kind(kinds.kind(of: item))
            case .modified: dateKey(item.modified, now: now, calendar: calendar)
            case .size: .size(SizeBand(item.size ?? sizes[item.url]))
            case .name: letterKey(item.name)
            case .none: .noDate
            }
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(item)
        }
        return order.sorted { $0.comesBefore($1) }.map { ItemGroup(key: $0, items: members[$0] ?? []) }
    }

    public static func dateKey(_ date: Date?, now: Date, calendar: Calendar) -> GroupKey {
        guard let date else { return .noDate }
        let today = calendar.startOfDay(for: now)
        if date >= today { return .today }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: today).day ?? 0
        if days <= 1 { return .yesterday }
        if days <= 7 { return .previous7 }
        if days <= 30 { return .previous30 }
        let parts = calendar.dateComponents([.year, .month], from: date)
        let year = parts.year ?? 0
        if year == calendar.component(.year, from: now) { return .month(year: year, month: parts.month ?? 1) }
        return .year(year)
    }

    static func letterKey(_ name: String) -> GroupKey {
        guard let first = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).first else { return .letter("#") }
        if first.isNumber { return .letter("0-9") }
        if first.isLetter { return .letter(String(first).uppercased()) }
        return .letter("#")
    }
}
