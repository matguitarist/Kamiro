import Foundation
import Testing
import UniformTypeIdentifiers
@testable import KamiroKit

@Test func defaultAppKindsAreOnePerContentType() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "KamiroDefault-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir.appending(path: "Folder"), withIntermediateDirectories: true)
    for name in ["a.pdf", "b.pdf", "c.md", "d.PNG"] { try Data().write(to: dir.appending(path: name)) }
    let urls = ["a.pdf", "b.pdf", "c.md", "d.PNG", "Folder"].map { dir.appending(path: $0) }
    let types = DefaultApps.types(of: urls)
    #expect(types.count == 3)
    #expect(types.first == .pdf)
    #expect(types.contains(.png))
    #expect(DefaultApps.types(of: [dir.appending(path: "Folder")]).isEmpty)
}
