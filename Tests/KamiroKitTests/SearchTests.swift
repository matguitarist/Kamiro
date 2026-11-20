import Foundation
import Testing
import UniformTypeIdentifiers
@testable import KamiroKit

@Test func searchesTravelAsURLs() {
    let search = Search(text: "invoice 2", scope: URL(filePath: "/tmp/Some Folder"), kind: .pdf, date: .week)
    #expect(VirtualPlace(VirtualPlace.search(search).url) == .search(search))
    let mac = Search(text: "x")
    #expect(VirtualPlace(VirtualPlace.search(mac).url) == .search(mac))
}

@Test func spotlightQueryHasEveryWordKindAndDate() {
    let now = ISO8601DateFormatter().date(from: "2026-11-20T12:00:00Z")!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let query = Search(text: "inv \"2*", kind: .image, date: .today).query(now: now)
    #expect(query.contains(#"kMDItemFSName == "*inv*"cd"#))
    #expect(query.contains(#"kMDItemFSName == "*\"2\**"cd"#))
    #expect(query.contains(#"kMDItemContentTypeTree == "public.image""#))
    #expect(query.contains("kMDItemFSContentChangeDate >= $time.iso("))
    #expect(SearchDate.week.start(now: now, calendar: calendar) == ISO8601DateFormatter().date(from: "2026-11-13T00:00:00Z"))
}

@Test func walkFindsNamesKindsAndDatesInSubfolders() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "KamiroSearch-\(UUID().uuidString)").canonical
    try FileManager.default.createDirectory(at: dir.appending(path: "inner"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let old = dir.appending(path: "invoice old.pdf"), new = dir.appending(path: "inner/Invoice new.txt")
    try Data("x".utf8).write(to: old)
    try Data("x".utf8).write(to: new)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -90 * 86_400)], ofItemAtPath: old.path)
    #expect(Set(Search(text: "INVOICE").walk(in: dir)) == [old, new])
    #expect(Search(text: "invoice", kind: .pdf).walk(in: dir) == [old])
    #expect(Search(text: "invoice", date: .month).walk(in: dir) == [new])
}
