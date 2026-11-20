import Foundation
import Testing
@testable import KamiroKit

private func folder() throws -> URL {
    let url = URL(filePath: NSTemporaryDirectory()).appending(path: "kamiro-tools-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A shell script standing in for a tool.
private func script(_ name: String, in folder: URL, _ body: String, executable: Bool = true) throws {
    let url = folder.appending(path: name)
    try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
}

@Test func toolsAreLookedForWhereHomebrewAndMacPortsPutThem() {
    #expect(ToolFinder.standardFolders.map(\.path) == ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"])
    #expect(CommandTool.all.map(\.brewLine) == ["brew install webp", "brew install ffmpeg", "brew install imagemagick"])
}

@Test func aToolIsFoundWithItsVersion() async throws {
    let first = try folder(), second = try folder()
    defer { try? FileManager.default.removeItem(at: first); try? FileManager.default.removeItem(at: second) }
    try script("cwebp", in: second, "echo 1.4.0")
    let found = await ToolFinder.find(.cwebp, in: [first, second])
    #expect(found?.version == "1.4.0" && found?.url.deletingLastPathComponent().lastPathComponent == second.lastPathComponent)
    // The first folder wins.
    try script("cwebp", in: first, "echo 1.5.0")
    #expect(await ToolFinder.find(.cwebp, in: [first, second])?.version == "1.5.0")
}

@Test func aMissingOrBrokenToolIsNotInstalled() async throws {
    let tools = try folder()
    defer { try? FileManager.default.removeItem(at: tools) }
    #expect(await ToolFinder.find(.ffmpeg, in: [tools]) == nil)
    try script("ffmpeg", in: tools, "echo 'dyld: Library not loaded' >&2; exit 1")
    #expect(await ToolFinder.find(.ffmpeg, in: [tools]) == nil)
    try script("magick", in: tools, "echo 'Version: ImageMagick 7.1.1-41 Q16-HDRI'", executable: false)
    #expect(await ToolFinder.find(.imageMagick, in: [tools]) == nil)
    #expect(await ToolFinder.findAll(in: [tools]).isEmpty)
}

@Test func versionsReadTheWayEachToolPrintsThem() {
    #expect(ToolFinder.version(in: "1.4.0\nlibsharpyuv: 0.4.0") == "1.4.0")
    #expect(ToolFinder.version(in: "ffmpeg version 7.1.1 Copyright (c) 2000-2025") == "7.1.1")
    #expect(ToolFinder.version(in: "ffmpeg version n6.0 Copyright") == "6.0")
    #expect(ToolFinder.version(in: "Version: ImageMagick 7.1.1-41 Q16-HDRI aarch64") == "7.1.1-41")
    #expect(ToolFinder.version(in: "usage: tool [options]") == nil)
}
