import Foundation
import ProcessKit
import Testing
@testable import KamiroKit

private func scratch() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "KamiroArchive-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.canonical
}

private func names(_ folder: URL) throws -> Set<String> {
    Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
}

@Test func archiveNamesDropAFilesExtension() throws {
    let dir = try scratch()
    let report = dir.appending(path: "report.pdf")
    try Data().write(to: report)
    #expect(Archive.name(for: [report], in: dir) == "report.zip")
    let shot = dir.appending(path: "Capture d’écran 2026-11-17 at 18.25.11.png")
    try Data().write(to: shot)
    #expect(Archive.name(for: [shot], in: dir) == "Capture d’écran 2026-11-17 at 18.25.11.zip")
    let dotted = dir.appending(path: "My.Project")
    try FileManager.default.createDirectory(at: dotted, withIntermediateDirectories: true)
    #expect(Archive.name(for: [dotted], in: dir) == "My.Project.zip")
    try Data().write(to: dir.appending(path: "report.zip"))
    #expect(Archive.name(for: [report], in: dir) == "report 2.zip")
    #expect(Archive.name(for: [report, dir.appending(path: "b")], in: dir) == "Archive.zip")
    try Data().write(to: dir.appending(path: "Archive.zip"))
    #expect(Archive.name(for: [report, dir.appending(path: "b")], in: dir) == "Archive 2.zip")
    #expect(Archive.isZip(URL(filePath: "/x/A.ZIP")) && !Archive.isZip(URL(filePath: "/x/a.tar")))
}

@Test func oneItemCompressesAndExtractsAsItself() async throws {
    let dir = try scratch()
    let folder = dir.appending(path: "Project")
    try FileManager.default.createDirectory(at: folder.appending(path: "Sources"), withIntermediateDirectories: true)
    try Data("print(1)".utf8).write(to: folder.appending(path: "Sources/main.swift"))
    let zip = try await Archive.compress([folder])
    #expect(zip == dir.appending(path: "Project.zip").canonical)
    #expect(try names(dir) == ["Project", "Project.zip"])
    // Project is still there, so the extracted copy takes the next free name.
    let out = try await Archive.extract(zip)
    #expect(out == dir.appending(path: "Project 2").canonical)
    #expect(try String(contentsOf: out.appending(path: "Sources/main.swift"), encoding: .utf8) == "print(1)")
}

@Test func compressToNamesTheArchive() async throws {
    let dir = try scratch()
    let a = dir.appending(path: "a.txt"), b = dir.appending(path: "b.txt")
    try Data("a".utf8).write(to: a)
    try Data("b".utf8).write(to: b)
    let out = dir.appending(path: "Out")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let target = out.appending(path: "Holiday notes.zip")
    #expect(try await Archive.compress([a, b], to: target) == target.canonical)
    // Replacing (the save panel asked): the old one goes to the trash folder, not lost.
    let trash = dir.appending(path: "Trash")
    #expect(try await Archive.compress([a], to: target, trash: .folder(trash)) == target.canonical)
    #expect(try names(trash) == ["Holiday notes.zip"])
    #expect(try names(dir) == ["a.txt", "b.txt", "Out", "Trash"])
}

@Test func oneFileComesBackAsItself() async throws {
    let dir = try scratch()
    let file = dir.appending(path: "Guide.pdf")
    try Data("pdf".utf8).write(to: file)
    let zip = try await Archive.compress([file])
    #expect(zip.lastPathComponent == "Guide.zip")
    let out = try await Archive.extract(zip)
    #expect(out == dir.appending(path: "Guide 2.pdf").canonical)
    #expect(try String(contentsOf: out, encoding: .utf8) == "pdf")
    #expect(try names(dir) == ["Guide.pdf", "Guide.zip", "Guide 2.pdf"])
}

@Test func severalItemsGoInAFolderNamedAfterTheArchive() async throws {
    let dir = try scratch()
    try Data("a".utf8).write(to: dir.appending(path: "a.txt"))
    try Data("b".utf8).write(to: dir.appending(path: "b.txt"))
    let zip = try await Archive.compress([dir.appending(path: "a.txt"), dir.appending(path: "b.txt")], several: "Archive")
    #expect(zip.lastPathComponent == "Archive.zip")
    let out = try await Archive.extract(zip)
    #expect(out.lastPathComponent == "Archive")
    #expect(try names(out) == ["a.txt", "b.txt"])
    #expect(try names(dir) == ["a.txt", "b.txt", "Archive.zip", "Archive"])
}

@Test func aBrokenArchiveFailsAndLeavesNothing() async throws {
    let dir = try scratch()
    let bad = dir.appending(path: "bad.zip")
    try Data("not a zip".utf8).write(to: bad)
    await #expect(throws: Archive.Failure.self) { try await Archive.extract(bad) }
    #expect(try names(dir) == ["bad.zip"])
}

@Test func aZipThatWritesOutsideItsFolderIsRefused() async throws {
    let dir = try scratch()
    let made = dir.appending(path: "made")
    try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(atPath: made.appending(path: "escape").path, withDestinationPath: "/etc")
    try Shell.runSync("/usr/bin/zip", ["-qy", dir.appending(path: "evil.zip").path, "escape"], in: made).check()
    try FileManager.default.removeItem(at: made)
    await #expect(throws: Archive.Failure.self) { try await Archive.extract(dir.appending(path: "evil.zip")) }
    #expect(try names(dir) == ["evil.zip"])
}

@Test func aStoppedJobLeavesNothing() async throws {
    let dir = try scratch()
    let big = dir.appending(path: "big.bin")
    try Data(count: 64 * 1024 * 1024).write(to: big)
    let cancel = CancelFlag()
    cancel.cancel()
    await #expect(throws: CancellationError.self) { try await Archive.compress([big], cancel: cancel) }
    #expect(try names(dir) == ["big.bin"])
}
