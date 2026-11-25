import Foundation
import ProcessKit

/// A free command-line tool Kamiro can use when it's installed (Settings › Tools, S-049).
/// Native first: nothing needs one, Kamiro never bundles or downloads one, and what a tool
/// adds shows only once it's found.
public struct CommandTool: Hashable, Sendable, Identifiable {
    public var id: String { command }
    /// The program Kamiro runs ("cwebp", "ffmpeg", "magick").
    public let command: String
    /// The name people know it by.
    public let name: String
    /// The Homebrew formula that installs it.
    public let formula: String
    public let versionArguments: [String]

    public static let cwebp = CommandTool(command: "cwebp", name: "cwebp", formula: "webp", versionArguments: ["-version"])
    public static let ffmpeg = CommandTool(command: "ffmpeg", name: "FFmpeg", formula: "ffmpeg", versionArguments: ["-version"])
    public static let imageMagick = CommandTool(command: "magick", name: "ImageMagick", formula: "imagemagick", versionArguments: ["-version"])

    public static let all: [CommandTool] = [cwebp, ffmpeg, imageMagick]

    /// The line to paste in Terminal.
    public var brewLine: String { "brew install \(formula)" }
}

/// A tool found on this Mac, with the version it reports.
public struct InstalledTool: Hashable, Sendable {
    public let tool: CommandTool
    public let url: URL
    public let version: String
}

public enum ToolFinder {
    /// Where Homebrew (Apple silicon, then Intel) and MacPorts put programs. An app started from
    /// the Dock has none of them on its PATH, so Kamiro looks here itself.
    public static let standardFolders = Shell.standardFolders

    /// The first executable named after the tool in `folders`.
    public static func locate(_ tool: CommandTool, in folders: [URL] = standardFolders) -> URL? {
        folders.lazy.map { $0.appending(path: tool.command) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// The tool, when it's there and answers its version question; a missing or broken tool is nil.
    @concurrent
    public static func find(_ tool: CommandTool, in folders: [URL] = standardFolders) async -> InstalledTool? {
        guard let url = locate(tool, in: folders),
              let output = await run(url, tool.versionArguments),
              let version = version(in: output) else { return nil }
        return InstalledTool(tool: tool, url: url, version: version)
    }

    @concurrent
    public static func findAll(in folders: [URL] = standardFolders) async -> [String: InstalledTool] {
        var found: [String: InstalledTool] = [:]
        for tool in CommandTool.all {
            if let installed = await find(tool, in: folders) { found[tool.id] = installed }
        }
        return found
    }

    /// The first word that starts with a digit, in the first line that has one:
    /// "1.4.0" (cwebp), "ffmpeg version 7.1.1 Copyright…", "Version: ImageMagick 7.1.1-41 Q16-HDRI…".
    public static func version(in output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            for word in line.split(separator: " ") {
                var token = Substring(word)
                if token.first == "n" || token.first == "v", token.dropFirst().first?.isNumber == true { token = token.dropFirst() }
                if token.first?.isNumber == true {
                    return String(token.prefix { $0.isNumber || $0.isLetter || $0 == "." || $0 == "-" })
                }
            }
        }
        return nil
    }

    /// Runs the program for at most a few seconds; its output when it ends well, nil otherwise.
    /// A tool that hangs is stopped, and counts as broken.
    static func run(_ url: URL, _ arguments: [String], seconds: Int = 5) async -> String? {
        let options = Shell.Options(stderr: .merged, timeout: .seconds(seconds))
        guard let output = try? await Shell.run(url.path, arguments, options: options), output.succeeded else { return nil }
        return output.text
    }
}
