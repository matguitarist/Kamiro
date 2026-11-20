import Foundation
import Testing
@testable import KamiroKit

private let a = URL(filePath: "/tmp/a", directoryHint: .isDirectory)
private let b = URL(filePath: "/tmp/b", directoryHint: .isDirectory)
private let c = URL(filePath: "/tmp/c", directoryHint: .isDirectory)
private let d = URL(filePath: "/tmp/d", directoryHint: .isDirectory)

@Test func pinningSkipsFoldersAlreadyPinnedAndInsertsWhereDropped() {
    var pins = PinList([a, b, a])
    #expect(pins.urls == [a, b].map(\.canonical))
    let again = pins.pin([b])
    #expect(!again)
    let added = pins.pin([c, d], at: 1)
    #expect(added)
    #expect(pins.urls == [a, c, d, b].map(\.canonical))
    #expect(pins.contains(URL(filePath: "/tmp/c/")))
    pins.unpin(c)
    #expect(pins.urls == [a, d, b].map(\.canonical))
}

@Test func pinsMoveLikeAListDragAndSurviveSaving() {
    var pins = PinList([a, b, c, d])
    pins.move(fromOffsets: [0], toOffset: 3)
    #expect(pins.urls == [b, c, a, d].map(\.canonical))
    pins.move(fromOffsets: [3], toOffset: 0)
    #expect(pins.urls == [d, b, c, a].map(\.canonical))
    pins.move(fromOffsets: [1, 2], toOffset: 4)
    #expect(pins.urls == [d, a, b, c].map(\.canonical))
    #expect(PinList(paths: pins.paths) == pins)
}

@Test func homeTravelsAsAURL() {
    #expect(VirtualPlace(VirtualPlace.home.url) == .home)
    #expect(VirtualPlace.home.items(showHidden: true).isEmpty)
}

@Test func recentFilesAreTheNewestFirst() throws {
    let now = Date.now
    #expect(RecentFiles.newest([(a, now.addingTimeInterval(-60)), (b, now), (c, now.addingTimeInterval(-3600))], limit: 2) == [b, a])
    let dir = FileManager.default.temporaryDirectory.appending(path: "KamiroRecent-\(UUID().uuidString)").canonical
    try FileManager.default.createDirectory(at: dir.appending(path: "inner"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let old = dir.appending(path: "old.txt"), new = dir.appending(path: "inner/new.txt")
    for url in [old, new] { try Data("x".utf8).write(to: url) }
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-86_400)], ofItemAtPath: old.path)
    #expect(RecentFiles.walk(in: dir) == [new, old])
}
