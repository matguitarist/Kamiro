import AppKit
import Foundation
import Testing
@testable import KamiroKit

private func board(_ fill: (NSPasteboard) -> Void) -> NSPasteboard {
    let pasteboard = NSPasteboard(name: .init("kamiro.test.\(UUID().uuidString)"))
    pasteboard.clearContents()
    fill(pasteboard)
    return pasteboard
}

@Test func clipboardTextPicksItsType() {
    #expect(ClipboardFile.classify("hello, world").ext == "txt")
    #expect(ClipboardFile.classify("{\"a\": [1, 2]}\n") == .json("{\"a\": [1, 2]}\n"))
    #expect(ClipboardFile.classify("[1, 2").ext == "txt")
    #expect(ClipboardFile.classify("  https://example.com/a?b=1 \n") == .link(URL(string: "https://example.com/a?b=1")!))
    #expect(ClipboardFile.classify("see https://example.com").ext == "txt")
    #expect(ClipboardFile.classify("name\tvalue\nTea, green\t3") == .table("name,value\n\"Tea, green\",3"))
    #expect(ClipboardFile.classify("one\ttab only").ext == "txt")
}

@Test func csvQuotesWhatNeedsIt() {
    #expect(ClipboardFile.csv(fromTabbed: "a\t\tsay \"hi\"\nb\tc\td") == "a,,\"say \"\"hi\"\"\"\nb,c,d")
}

@Test func clipboardBecomesAFile() throws {
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "kamiro-clip-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let json = try #require(ClipboardFile.read(from: board { $0.setString("{\"ok\": true}", forType: .string) }))
    let first = try json.make(in: folder, base: "untitled")
    let second = try json.make(in: folder, base: "untitled")
    #expect(first.lastPathComponent == "untitled.json" && second.lastPathComponent == "untitled 2.json")
    #expect(try JSONSerialization.jsonObject(with: Data(contentsOf: first)) is [String: Any])

    let link = try #require(ClipboardFile.read(from: board { $0.setString("https://example.com", forType: .string) }))
    let webloc = try link.make(in: folder, base: "untitled")
    let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: webloc), format: nil) as? [String: String]
    #expect(webloc.pathExtension == "webloc" && plist?["URL"] == "https://example.com")

    let picture = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
        NSColor.red.setFill(); rect.fill(); return true
    }
    let image = try #require(ClipboardFile.read(from: board { $0.writeObjects([picture]) }))
    let png = try image.make(in: folder, base: "untitled")
    #expect(png.pathExtension == "png" && NSImage(contentsOf: png) != nil)

    // A table from a spreadsheet carries a picture too: the table wins.
    let sheet = board {
        $0.setString("a\tb\n1\t2", forType: .init("public.utf8-tab-separated-values-text"))
        $0.setString("a\tb\n1\t2", forType: .string)
        $0.setData(picture.tiffRepresentation, forType: .tiff)
    }
    #expect(ClipboardFile.read(from: sheet) == .table("a,b\n1,2"))
}

@Test func filesAndEmptyClipboardMakeNothing() {
    #expect(ClipboardFile.read(from: board { _ in }) == nil)
    let files = board { $0.writeObjects([URL(filePath: "/tmp") as NSURL]) }
    #expect(!ClipboardFile.available(in: files) && ClipboardFile.read(from: files) == nil)
}
