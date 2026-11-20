import Foundation
import Testing
@testable import KamiroKit

private func scratch() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "KamiroTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.canonical
}

private func file(_ name: String, size: Int64? = 0, folder: Bool = false) -> FileItem {
    FileItem(url: URL(filePath: "/x/\(name)"), name: name, isFolder: folder, size: folder ? nil : size)
}

@Test func crumbsGoFromTheRootDown() {
    let location = Location(URL(fileURLWithPath: "/Users/someone/Documents"))
    #expect(location.crumbs.map(\.path) == ["/", "/Users", "/Users/someone", "/Users/someone/Documents"])
    #expect(location.parent?.url.path == "/Users/someone")
    #expect(Location(URL(fileURLWithPath: "/")).parent == nil)
}

@Test func canonicalDropsTheTrailingSlash() {
    #expect(URL(filePath: "/tmp/a/", directoryHint: .isDirectory).canonical == URL(filePath: "/tmp/a").canonical)
    #expect(URL(filePath: "/").canonical.path == "/")
}

@Test func namesSortLikeFinderWithFoldersFirst() {
    let items = [file("file 10.txt"), file("Zed", folder: true), file("file 2.txt"), file("apple.txt")]
    #expect(ItemOrder().sorted(items).map(\.name) == ["Zed", "apple.txt", "file 2.txt", "file 10.txt"])
    let descending = ItemOrder(key: .name, ascending: false).sorted(items).map(\.name)
    #expect(descending == ["Zed", "file 10.txt", "file 2.txt", "apple.txt"])
}

@Test func sizeSortsBiggestFirstWhenDescending() {
    let items = [file("a", size: 10), file("b", size: 300), file("c", size: 20)]
    #expect(ItemOrder(key: .size, ascending: false).sorted(items).map(\.name) == ["b", "c", "a"])
}

@Test func historyGoesBackForwardAndForgetsForwardOnANewFolder() {
    var history = History(URL(filePath: "/a"))
    history.go(to: URL(filePath: "/b"))
    history.go(to: URL(filePath: "/c"))
    #expect(history.back()?.path == "/b")
    #expect(history.canGoForward)
    #expect(history.forward()?.path == "/c")
    #expect(history.back(2)?.path == "/a")
    history.go(to: URL(filePath: "/d"))
    #expect(!history.canGoForward)
    #expect(history.backList.map(\.path) == ["/a"])
    history.go(to: URL(filePath: "/d/"))
    #expect(history.backList.count == 1)
}

@Test func typedPathsResolve() {
    let home = URL(filePath: "/Users/someone")
    let here = URL(filePath: "/Users/someone/Documents")
    func resolve(_ text: String) -> String? { PathInput.resolve(text, relativeTo: here, home: home)?.path }
    #expect(resolve("~") == "/Users/someone")
    #expect(resolve("~/Desktop") == "/Users/someone/Desktop")
    #expect(resolve("Projects") == "/Users/someone/Documents/Projects")
    #expect(resolve("../Music") == "/Users/someone/Music")
    #expect(resolve("'/Volumes/Backup Disk'") == "/Volumes/Backup Disk")
    #expect(resolve("\"/tmp/a b\"") == "/tmp/a b")
    #expect(resolve("/tmp/My\\ Folder") == "/tmp/My Folder")
    #expect(resolve("file:///tmp/a%20b/") == "/tmp/a b")
    #expect(resolve("   ") == nil)
    #expect(PathInput.display(URL(filePath: "/Users/someone/Documents"), home: home) == "~/Documents")
    #expect(PathInput.display(URL(filePath: "/Users/someoneelse"), home: home) == "/Users/someoneelse")
}

@Test func completionsListMatchingFolders() throws {
    let dir = try scratch()
    for name in ["Projects", "Photos", "Music"] {
        try FileManager.default.createDirectory(at: dir.appending(path: name), withIntermediateDirectories: false)
    }
    try Data().write(to: dir.appending(path: "Pnotes.txt"))
    let found = PathInput.completions(for: dir.path + "/p", relativeTo: dir)
    #expect(found == [dir.path + "/Photos/", dir.path + "/Projects/"])
    #expect(PathInput.commonPrefix(found) == dir.path + "/P")
}

@Test func readerListsSkipsHiddenAndSpotsPackages() throws {
    let dir = try scratch()
    try FileManager.default.createDirectory(at: dir.appending(path: "Folder"), withIntermediateDirectories: false)
    try FileManager.default.createDirectory(at: dir.appending(path: "Tool.app/Contents"), withIntermediateDirectories: true)
    try Data("hello".utf8).write(to: dir.appending(path: "note.txt"))
    try Data().write(to: dir.appending(path: ".hidden"))
    let items = try FolderReader.list(dir)
    #expect(Set(items.map(\.name)) == ["Folder", "Tool.app", "note.txt"])
    let app = try #require(items.first { $0.name == "Tool.app" })
    #expect(app.isPackage && !app.isFolder)
    #expect(items.first { $0.name == "note.txt" }?.size == 5)
    #expect(items.first { $0.name == "Folder" }?.size == nil)
    #expect(try FolderReader.list(dir, showHidden: true).count == 4)
}

@Test func listedURLsAreCanonicalHoweverTheFolderIsSpelled() throws {
    let dir = try scratch()
    try FileManager.default.createDirectory(at: dir.appending(path: "Folder"), withIntermediateDirectories: false)
    try Data().write(to: dir.appending(path: "Photo 1.jpg"))
    let spellings = [dir, URL(filePath: "/private" + dir.path), URL(filePath: dir.path + "/", directoryHint: .isDirectory),
                     dir.appending(path: "Folder/..")]
    let expected: Set<URL> = [dir.appending(path: "Folder").canonical, dir.appending(path: "Photo 1.jpg").canonical]
    for folder in spellings {
        let items = try FolderReader.list(folder)
        #expect(Set(items.map(\.url)) == expected, "\(folder.path)")
        #expect(items.allSatisfy { $0.url == $0.url.canonical })
    }
    let root = try FolderReader.list(URL(filePath: "/"))
    #expect(!root.isEmpty && root.allSatisfy { $0.url == $0.url.canonical && !$0.url.path.hasPrefix("//") })
}

@Test func aClosedFolderIsDenied() throws {
    let dir = try scratch().appending(path: "Locked")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: dir.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
    #expect(throws: FolderError.denied) { try FolderReader.list(dir) }
    #expect(throws: FolderError.missing) { try FolderReader.list(dir.deletingLastPathComponent().appending(path: "nope")) }
}

@Test func kindsComeFromTheExtension() {
    let kinds = KindCache()
    #expect(kinds.kind(of: file("Zed", folder: true)) == KindCache.folder)
    #expect(!kinds.kind(of: file("a.txt")).isEmpty)
    #expect(kinds.kind(of: file("a.txt")) == kinds.kind(of: file("b.TXT")))
}

@Test func statusCountsTheSelection() {
    let items = [file("a", size: 1_000), file("b", size: 2_000), file("F", folder: true)]
    let counts = StatusCounts(items: items, selection: [items[0].url, items[1].url], available: 5)
    #expect(counts.items == 3 && counts.selected == 2 && counts.selectedBytes == 3_000 && counts.available == 5)
    #expect(StatusCounts(items: items, selection: [items[2].url], available: nil).selectedBytes == nil)
}

@Test func watcherSeesANewFile() async throws {
    let dir = try scratch()
    let seen = AsyncStream<Void>.makeStream()
    let watcher = FolderWatcher(folder: dir) { seen.continuation.yield() }
    try await Task.sleep(for: .milliseconds(300))
    try Data().write(to: dir.appending(path: "new.txt"))
    let got = await withTaskGroup(of: Bool.self) { group in
        group.addTask { for await _ in seen.stream { return true }; return false }
        group.addTask { try? await Task.sleep(for: .seconds(3)); return false }
        let first = await group.next() ?? false
        group.cancelAll()
        return first
    }
    #expect(got)
    _ = watcher
}
