import Foundation
import Testing
@testable import KamiroKit

@Test func newWindowsOpenWhereChosen() throws {
    let home = URL(filePath: NSTemporaryDirectory()).appending(path: "kamiro-start-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home.appending(path: "Documents"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    // Nothing chosen yet, or something unknown: the Home page.
    #expect(StartPlace(stored: nil) == .home && StartPlace(stored: "nonsense") == .home)
    #expect(StartPlace.home.url(home: home) == VirtualPlace.home.url)
    #expect(StartPlace.documents.url(home: home) == home.appending(path: "Documents"))
    #expect(StartPlace.homeFolder.url(home: home) == home)
    // Every choice is kept and read back the same.
    let chosen = StartPlace.folder(home.appending(path: "Documents"))
    for place in StartPlace.standard + [chosen] { #expect(StartPlace(stored: place.stored) == place, "\(place)") }
    #expect(chosen.url(home: home).path == home.appending(path: "Documents").path)
    // A folder that's gone, or a file, opens Home instead.
    #expect(StartPlace.desktop.url(home: home) == VirtualPlace.home.url)
    let file = home.appending(path: "notes.txt")
    FileManager.default.createFile(atPath: file.path, contents: Data())
    #expect(StartPlace.folder(file).url(home: home) == VirtualPlace.home.url)
}
