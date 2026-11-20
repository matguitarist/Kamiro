import Foundation
import Testing
@testable import KamiroKit

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func day(_ text: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.date(from: text + "Z")!
}

private let now = day("2026-11-19T15:00:00")

@Test func dateGroupsGoTodayYesterdayPrevious7And30ThenMonthsThenYears() {
    func key(_ text: String) -> GroupKey { Grouping.dateKey(day(text), now: now, calendar: calendar) }
    #expect(key("2026-11-19T00:00:00") == .today)
    #expect(key("2026-11-19T14:59:00") == .today)
    #expect(key("2026-11-18T23:59:00") == .yesterday)
    #expect(key("2026-11-18T00:00:00") == .yesterday)
    #expect(key("2026-11-17T12:00:00") == .previous7)
    #expect(key("2026-11-12T00:00:00") == .previous7)
    #expect(key("2026-11-11T12:00:00") == .previous30)
    #expect(key("2026-10-20T12:00:00") == .previous30)
    #expect(key("2026-10-19T12:00:00") == .month(year: 2026, month: 10))
    #expect(key("2026-01-02T12:00:00") == .month(year: 2026, month: 1))
    #expect(key("2025-12-31T12:00:00") == .year(2025))
    #expect(Grouping.dateKey(nil, now: now, calendar: calendar) == .noDate)
}

@Test func dateGroupsComeNewestFirstAndKeepTheItemsOrder() {
    func item(_ name: String, _ date: String) -> FileItem {
        FileItem(url: URL(filePath: "/x/\(name)"), name: name, isFolder: false, modified: day(date))
    }
    let items = [item("a", "2024-05-01T00:00:00"), item("b", "2026-11-19T09:00:00"), item("c", "2026-03-01T00:00:00"),
                 item("d", "2026-11-18T09:00:00"), item("e", "2026-11-19T10:00:00"), item("f", "2026-09-01T00:00:00")]
    let groups = Grouping.groups(items, by: .modified, now: now, calendar: calendar)
    #expect(groups.map(\.key) == [.today, .yesterday, .month(year: 2026, month: 9), .month(year: 2026, month: 3), .year(2024)])
    #expect(groups[0].items.map(\.name) == ["b", "e"])
}

@Test func sizeKindAndNameGroups() {
    let items = [
        FileItem(url: URL(filePath: "/x/zed.txt"), name: "zed.txt", isFolder: false, size: 0),
        FileItem(url: URL(filePath: "/x/Élan.mov"), name: "Élan.mov", isFolder: false, size: 2_000_000_000),
        FileItem(url: URL(filePath: "/x/2024.pdf"), name: "2024.pdf", isFolder: false, size: 50_000),
        FileItem(url: URL(filePath: "/x/_tmp"), name: "_tmp", isFolder: true),
        FileItem(url: URL(filePath: "/x/apple.txt"), name: "apple.txt", isFolder: false, size: 5_000_000),
    ]
    let sizes = Grouping.groups(items, by: .size, sizes: [URL(filePath: "/x/_tmp").canonical: 300_000_000])
    #expect(sizes.map(\.key) == [.size(.huge), .size(.large), .size(.medium), .size(.small), .size(.empty)])
    #expect(Grouping.groups(items, by: .name).map(\.key) == [.letter("#"), .letter("0-9"), .letter("A"), .letter("E"), .letter("Z")])
    let kinds = Grouping.groups(items, by: .kind).map(\.key)
    #expect(kinds.count == 4 && kinds.allSatisfy { if case .kind = $0 { true } else { false } })
    #expect(Grouping.groups(items, by: .none).first?.items.count == 5)
}

@Test func groupingIsSavedWithTheFolderView() throws {
    var view = FolderView()
    view.groupBy = .kind
    let data = try JSONEncoder().encode(view)
    #expect(try JSONDecoder().decode(FolderView.self, from: data).groupBy == .kind)
    #expect(try JSONDecoder().decode(FolderView.self, from: Data("{}".utf8)).groupBy == GroupBy.none)
}
