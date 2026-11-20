import Foundation
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

@Test func archiveNamesFollowTheFinder() throws {
    let dir = try scratch()
    let report = dir.appending(path: "report.pdf")
    #expect(Archive.name(for: [report], in: dir) == "report.pdf.zip")
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

@Test func oneFileComesBackAsItself() async throws {
    let dir = try scratch()
    let file = dir.appending(path: "Guide.pdf")
    try Data("pdf".utf8).write(to: file)
    let zip = try await Archive.compress([file])
    #expect(zip.lastPathComponent == "Guide.pdf.zip")
    let out = try await Archive.extract(zip)
    #expect(out == dir.appending(path: "Guide 2.pdf").canonical)
    #expect(try String(contentsOf: out, encoding: .utf8) == "pdf")
    #expect(try names(dir) == ["Guide.pdf", "Guide.pdf.zip", "Guide 2.pdf"])
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

@Test func aStoppedJobLeavesNothing() async throws {
    let dir = try scratch()
    let big = dir.appending(path: "big.bin")
    try Data(count: 64 * 1024 * 1024).write(to: big)
    let cancel = CancelFlag()
    cancel.cancel()
    await #expect(throws: CancellationError.self) { try await Archive.compress([big], cancel: cancel) }
    #expect(try names(dir) == ["big.bin"])
}
