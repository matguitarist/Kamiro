import Foundation
import Testing
@testable import KamiroKit

private func tree() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "KamiroSizes-\(UUID().uuidString)").canonical
    try FileManager.default.createDirectory(at: dir.appending(path: "inner/deeper"), withIntermediateDirectories: true)
    return dir
}

private func allocated(_ url: URL) -> Int64 {
    Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
}

@Test func sizesAreAllocatedSizeIncludingHiddenFiles() throws {
    let dir = try tree()
    defer { try? FileManager.default.removeItem(at: dir) }
    let small = dir.appending(path: "a.txt")
    let big = dir.appending(path: "inner/deeper/b.bin")
    let hidden = dir.appending(path: "inner/.hidden")
    try Data("x".utf8).write(to: small)
    try Data(repeating: 7, count: 100_000).write(to: big)
    try Data(repeating: 1, count: 5_000).write(to: hidden)
    let expected = allocated(small) + allocated(big) + allocated(hidden)
    #expect(expected >= 1 + 100_000 + 5_000, "allocated size is at least the bytes in the files")
    #expect(try FolderSize.measure(dir) == expected)
}

@Test func hardLinksCountOnce() throws {
    let dir = try tree()
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appending(path: "inner/photo.raw")
    try Data(repeating: 3, count: 200_000).write(to: file)
    let before = try FolderSize.measure(dir)
    try FileManager.default.linkItem(at: file, to: dir.appending(path: "inner/deeper/same photo.raw"))
    try FileManager.default.linkItem(at: file, to: dir.appending(path: "again.raw"))
    #expect(try FolderSize.measure(dir) == before)
}

@Test func measuringStopsWhenCancelled() async throws {
    let dir = try tree()
    defer { try? FileManager.default.removeItem(at: dir) }
    for index in 0..<3_000 {
        FileManager.default.createFile(atPath: dir.appending(path: "inner/f\(index)").path, contents: Data("x".utf8))
    }
    let task = Task.detached { try FolderSize.measure(dir) }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
}

@Test func foldersSortBySizeOnceMeasured() {
    let a = FileItem(url: URL(filePath: "/x/a"), name: "a", isFolder: true)
    let b = FileItem(url: URL(filePath: "/x/b"), name: "b", isFolder: true)
    let c = FileItem(url: URL(filePath: "/x/c"), name: "c", isFolder: true)
    let sizes = [a.url: Int64(10), c.url: Int64(500)]
    #expect(ItemOrder(key: .size, ascending: false).sorted([a, b, c], sizes: sizes).map(\.name) == ["c", "a", "b"])
    let counts = StatusCounts(items: [a, b, c], selection: [a.url, c.url], available: nil, sizes: sizes)
    #expect(counts.selectedBytes == 510)
}

@Test func treeWatcherNamesTheChildThatChanged() {
    let watcher = TreeWatcher(folder: URL(filePath: "/tmp")) { _ in }
    #expect(watcher.child(holding: watcher.root + "/Photos/2026/a.jpg") == "Photos")
    #expect(watcher.child(holding: watcher.root) == nil)
    #expect(watcher.child(holding: "/elsewhere/a") == nil)
}

@Test func aFolderThatCantBeReadHasNoSize() throws {
    let dir = try tree()
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.appending(path: "inner").path)
        try? FileManager.default.removeItem(at: dir)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: dir.appending(path: "inner").path)
    #expect(throws: FolderError.denied) { try FolderSize.measure(dir.appending(path: "inner")) }
}

@Test func busyFoldersAreMeasuredAgainOnlyNowAndThen() {
    #expect(FolderSize.recheckDelay(after: .milliseconds(5)) == .seconds(2))
    #expect(FolderSize.recheckDelay(after: .seconds(3)) == .seconds(30))
    #expect(FolderSize.recheckDelay(after: .seconds(180)) == .seconds(1800))
}

@Test func summaryCountsEveryItemInside() throws {
    let dir = try tree()
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data("a".utf8).write(to: dir.appending(path: "a.txt"))
    try Data("b".utf8).write(to: dir.appending(path: "inner/deeper/b.txt"))
    try Data("c".utf8).write(to: dir.appending(path: "inner/.hidden"))
    // inner, inner/deeper, three files
    #expect(try FolderSize.summary(dir).items == 5)
}

@Test func permissionsReadAsAccess() {
    let p = Permissions(mode: 0o640, owner: "me", group: "staff")
    #expect(p.ownerAccess == .readWrite && p.groupAccess == .readOnly && p.everyoneAccess == .none)
    #expect(Permissions(mode: 0o222, owner: "me", group: "staff").everyoneAccess == .writeOnly)
}

@Test func lockingAndHidingReachTheDisk() throws {
    let dir = try tree()
    let file = dir.appending(path: "a.txt")
    defer {
        try? ItemFlags.setLocked(false, file)
        try? FileManager.default.removeItem(at: dir)
    }
    try Data("a".utf8).write(to: file)
    try ItemFlags.setLocked(true, file)
    #expect(ItemFlags.isLocked(file))
    #expect(throws: (any Error).self) { try FileManager.default.removeItem(at: file) }
    try ItemFlags.setLocked(false, file)
    try ItemFlags.setHidden(true, file)
    #expect(!ItemFlags.isLocked(file) && ItemFlags.isHidden(file))
}
