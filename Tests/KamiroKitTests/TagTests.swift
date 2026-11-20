import Foundation
import Testing
@testable import KamiroKit

@Test func tagPlacesTravelAsURLs() {
    let place = VirtualPlace.tag("Très important \"A\"")
    #expect(VirtualPlace(place.url) == place)
    #expect(VirtualPlace(URL(filePath: "/tmp")) == nil)
    #expect(place.url.canonical == place.url)
    #expect(place.title == "Très important \"A\"")
}

@Test func spotlightQueriesEscapeTheTag() {
    #expect(TagFinder.query(for: "Red") == "kMDItemUserTags == \"Red\"")
    #expect(TagFinder.query(for: #"a"b\c"#) == #"kMDItemUserTags == "a\"b\\c""#)
}

@Test func taggingAddsAndRemovesOneTagAndAWalkFindsIt() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "KamiroTags-\(UUID().uuidString)").canonical
    try FileManager.default.createDirectory(at: dir.appending(path: "inner"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let a = dir.appending(path: "a.txt"), b = dir.appending(path: "inner/b.txt"), c = dir.appending(path: "c.txt")
    for url in [a, b, c] { try Data("x".utf8).write(to: url) }
    try Tags.set("Work", present: true, on: [a])
    try Tags.set("Red", present: true, on: [a, b])
    #expect(Tags.of(a) == ["Work", "Red"])
    #expect(Set(TagFinder.walk("Red", in: dir)) == [a, b])
    #expect(Set(VirtualPlace.tag("Red").items(showHidden: false, root: dir).map(\.name)) == ["a.txt", "b.txt"])
    try Tags.set("Red", present: false, on: [a])
    #expect(Tags.of(a) == ["Work"])
}
