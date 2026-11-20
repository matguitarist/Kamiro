import Foundation

/// Zip archives the Finder's way (S-035): `ditto`, so names, permissions, extended attributes
/// and resource forks survive, and the result opens anywhere. Work happens in a staging folder
/// on the same disk and is moved into place at the end: a stopped or failed job leaves nothing.
public enum Archive {
    public enum Failure: Error, Equatable, LocalizedError {
        case tool(String)

        public var errorDescription: String? {
            switch self { case .tool(let message): message }
        }
    }

    public static func isZip(_ url: URL) -> Bool { url.pathExtension.lowercased() == "zip" }

    /// "report.pdf.zip" for one item, like the Finder; `several` (the localized "Archive")
    /// plus ".zip" for more; numbered when taken.
    public static func name(for sources: [URL], in folder: URL, several: String = "Archive") -> String {
        let base = sources.count == 1 ? sources[0].lastPathComponent : several
        return Naming.free(base + ".zip", in: folder)
    }

    /// Zips `sources` (all in one folder) into that folder and returns the archive.
    @concurrent
    public static func compress(_ sources: [URL], several: String = "Archive", cancel: CancelFlag = CancelFlag()) async throws -> URL {
        guard let first = sources.first else { throw Failure.tool("Nothing to compress.") }
        let folder = first.deletingLastPathComponent().canonical
        let staging = try stagingFolder(near: folder)
        defer { try? FileManager.default.removeItem(at: staging) }
        let archive = staging.appending(path: "archive.zip")
        if sources.count == 1 {
            // --keepParent names a folder's top entry after it; for a file it would also add the
            // file's own parent folder.
            let isFolder = (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            try await run(["-c", "-k", "--sequesterRsrc"] + (isFolder ? ["--keepParent"] : []) + [first.path, archive.path], cancel: cancel)
        } else {
            // ditto archives one folder: the items go in one, as clones on APFS, at its top level.
            let top = staging.appending(path: "items")
            try FileManager.default.createDirectory(at: top, withIntermediateDirectories: false)
            for source in sources {
                if cancel.isCancelled { throw CancellationError() }
                try FileManager.default.copyItem(at: source, to: top.appending(path: source.lastPathComponent))
            }
            try await run(["-c", "-k", "--sequesterRsrc", top.path, archive.path], cancel: cancel)
        }
        let target = folder.appending(path: name(for: sources, in: folder, several: several))
        try FileManager.default.moveItem(at: archive, to: target)
        return target.canonical
    }

    /// Extracts `zip` next to it, like Archive Utility: a lone top-level item comes out as
    /// itself, several go in a folder named after the archive. Returns what was made.
    @concurrent
    public static func extract(_ zip: URL, cancel: CancelFlag = CancelFlag()) async throws -> URL {
        let folder = zip.deletingLastPathComponent().canonical
        let staging = try stagingFolder(near: folder)
        defer { try? FileManager.default.removeItem(at: staging) }
        let out = staging.appending(path: "out")
        try await run(["-x", "-k", zip.path, out.path], cancel: cancel)
        let files = FileManager.default
        // Archives made on a Mac by other tools carry their resource forks in __MACOSX.
        let items = try files.contentsOfDirectory(at: out, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != "__MACOSX" }
        let target: URL
        if items.count == 1 {
            let item = items[0]
            let isFolder = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            target = folder.appending(path: Naming.free(item.lastPathComponent, isFolder: isFolder, in: folder))
            try files.moveItem(at: item, to: target)
        } else {
            let stem = zip.deletingPathExtension().lastPathComponent
            target = folder.appending(path: Naming.free(stem, isFolder: true, in: folder))
            let made = staging.appending(path: "folder")
            try files.createDirectory(at: made, withIntermediateDirectories: false)
            for item in items { try files.moveItem(at: item, to: made.appending(path: item.lastPathComponent)) }
            try files.moveItem(at: made, to: target)
        }
        return target.canonical
    }

    /// A private folder on the same disk as `folder`, so the last step is a rename.
    static func stagingFolder(near folder: URL) throws -> URL {
        if let url = try? FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                  appropriateFor: folder, create: true) {
            return url
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "Kamiro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Runs ditto; stops it when `cancel` is set.
    private static func run(_ arguments: [String], cancel: CancelFlag) async throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = arguments
        let errors = FileManager.default.temporaryDirectory.appending(path: "Kamiro-ditto-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: errors.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: errors) }
        let log = try FileHandle(forWritingTo: errors)
        defer { try? log.close() }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = log
        try process.run()
        while process.isRunning {
            if cancel.isCancelled {
                process.terminate()
                process.waitUntilExit()
                throw CancellationError()
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard process.terminationStatus == 0 else {
            let message = (try? String(contentsOf: errors, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.tool(message?.isEmpty == false ? message! : "ditto failed (\(process.terminationStatus)).")
        }
    }
}
