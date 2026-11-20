import Foundation
import Testing
@testable import KamiroKit

@Test func recentFoldersKeepTheNewestOnce() {
    var recent = RecentFolders()
    for name in ["a", "b", "a"] { recent.add(URL(filePath: "/p/\(name)")) }
    #expect(recent.paths == ["/p/a", "/p/b"])
    for index in 0..<20 { recent.add(URL(filePath: "/q/\(index)")) }
    #expect(recent.paths.count == RecentFolders.limit && recent.paths.first == "/q/19")
}

@Test func copyToLeavesOutWhatWouldDoNothing() {
    let file = URL(filePath: "/p/Docs/a.txt"), folder = URL(filePath: "/p/Docs/Sub")
    #expect(!Destinations.allows(URL(filePath: "/p/Docs"), sources: [file, folder]))
    #expect(Destinations.allows(URL(filePath: "/p"), sources: [file, folder]))
    #expect(!Destinations.allows(folder, sources: [folder]))
    #expect(!Destinations.allows(URL(filePath: "/p/Docs/Sub/Deeper"), sources: [folder]))
    #expect(Destinations.allows(URL(filePath: "/p/Docs/Subway"), sources: [folder]))
    #expect(Destinations.allows(URL(filePath: "/p/Other"), sources: [file]))
}

@Test func copyToListsPinsThenRecentsThatStillExist() {
    let docs = URL(filePath: "/p/Docs"), music = URL(filePath: "/p/Music"), gone = URL(filePath: "/p/Gone")
    let photos = URL(filePath: "/p/Photos")
    let source = URL(filePath: "/p/Docs/a.txt")
    let result = Destinations.choices(pins: [docs, music], recents: [music, gone, photos, docs], sources: [source]) { $0 != gone }
    #expect(result.pinned == [music.canonical])
    #expect(result.recent == [photos.canonical])
}
