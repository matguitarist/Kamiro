import Foundation
import Testing
@testable import KamiroKit

private func scratch() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "KamiroOpen-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.canonical
}

@Test func aFolderOpensAndAFileShowsInItsFolder() throws {
    let dir = try scratch()
    let folder = dir.appending(path: "Projects")
    let file = dir.appending(path: "notes.txt")
    let app = dir.appending(path: "Tool.app")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: app.appending(path: "Contents"), withIntermediateDirectories: true)
    try Data("hi".utf8).write(to: file)

    #expect(OpenRequest(folder) == OpenRequest(folder: folder))
    #expect(OpenRequest(file) == OpenRequest(folder: dir, select: file))
    #expect(OpenRequest(app) == OpenRequest(folder: dir, select: app))
    #expect(OpenRequest(folder, reveal: true) == OpenRequest(folder: dir, select: folder))
    #expect(OpenRequest(URL(filePath: "/"), reveal: true) == OpenRequest(folder: URL(filePath: "/")))
    #expect(OpenRequest(dir.appending(path: "gone.txt")) == nil)
    #expect(OpenRequest(URL(string: "https://example.com")!) == nil)
}

@Test func theCommandIsOnlyReplacedWhenKamiroWroteIt() throws {
    let dir = try scratch()
    let id = "com.example.kamiro"
    #expect(CommandLineTool.status(in: dir, bundleID: id) == .missing)
    let file = dir.appending(path: "kamiro")
    try Data(CommandLineTool.script(bundleID: id).utf8).write(to: file)
    #expect(CommandLineTool.status(in: dir, bundleID: id) == .installed)
    #expect(CommandLineTool.status(in: dir, bundleID: "com.example.other") == .outdated)
    try Data("#!/bin/sh\necho mine\n".utf8).write(to: file)
    #expect(CommandLineTool.status(in: dir, bundleID: id) == .foreign)
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createSymbolicLink(atPath: file.path, withDestinationPath: "/nowhere/kamiro")
    #expect(CommandLineTool.status(in: dir, bundleID: id) == .foreign)
}

@Test func theCommandOpensWhatExistsAndSaysWhatDoesnt() async throws {
    let dir = try scratch()
    let bin = dir.appending(path: "bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    // A fake open(1) that prints its arguments.
    let open = bin.appending(path: "open")
    try Data("#!/bin/sh\necho \"$@\"\n".utf8).write(to: open)
    let tool = dir.appending(path: "kamiro")
    try Data(CommandLineTool.script(bundleID: "com.example.kamiro").utf8).write(to: tool)
    for file in [open, tool] { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path) }
    try Data().write(to: dir.appending(path: "a b.txt"))

    func run(_ arguments: [String]) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        process.currentDirectoryURL = dir
        process.environment = ["PATH": bin.path + ":/usr/bin:/bin"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
    let real = (dir.path.hasPrefix("/var/") ? "/private" : "") + dir.path  // the shell sees /private/var
    let none = try run([])
    #expect(none == (0, "-b com.example.kamiro \(real)\n"))
    let two = try run(["a b.txt", "missing"])
    #expect(two.0 == 1)
    #expect(two.1.contains("kamiro: missing: no such file or folder"))
    #expect(two.1.contains("-b com.example.kamiro \(real)/a b.txt"))
}
