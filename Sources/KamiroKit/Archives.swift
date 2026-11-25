import ArchiveKit
import Foundation
import ProcessKit

/// Zip archives the Finder's way (S-035), through ArchiveKit: ditto, so names, permissions, extended
/// attributes and resource forks survive, and the result opens anywhere. Work happens in a staging folder
/// on the same disk and is moved into place at the end: a stopped or failed job leaves nothing.
public enum Archive {
    public enum Failure: Error, Equatable, LocalizedError {
        case tool(String)

        public var errorDescription: String? {
            switch self { case .tool(let message): message }
        }
    }

    public static func isZip(_ url: URL) -> Bool { url.pathExtension.lowercased() == "zip" }

    /// "report.zip" for one file (its extension dropped), "My.Project.zip" for a folder;
    /// `several` (the localized "Archive") plus ".zip" for more; numbered when taken.
    public static func name(for sources: [URL], in folder: URL, several: String = "Archive") -> String {
        let base: String
        if sources.count == 1 {
            let values = try? sources[0].resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            let isFolder = values?.isDirectory == true && values?.isPackage != true
            base = Naming.split(sources[0].lastPathComponent, isFolder: isFolder).stem
        } else {
            base = several
        }
        return Naming.free(base + ".zip", in: folder)
    }

    /// Zips `sources` (all in one folder) into that folder, or into `target` (Compress To…),
    /// and returns the archive. A `target` already there goes to `trash` at the end: the save
    /// panel asked first.
    @concurrent
    public static func compress(_ sources: [URL], to target: URL? = nil, several: String = "Archive",
                                trash: TrashCan = .system, cancel: CancelFlag = CancelFlag()) async throws -> URL {
        guard let first = sources.first else { throw Failure.tool("Nothing to compress.") }
        let folder = (target?.deletingLastPathComponent() ?? first.deletingLastPathComponent()).canonical
        let staging = try stagingFolder(near: folder)
        defer { try? FileManager.default.removeItem(at: staging) }
        let archive = staging.appending(path: "archive.zip")
        try await sentence {
            if sources.count == 1 {
                // A folder's top entry is named after it; a file sits at the top on its own.
                let isFolder = (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                try await Zip.pack(first, to: archive, keepParent: isFolder, cancel: cancel)
            } else {
                try await Zip.pack(first.deletingLastPathComponent(), to: archive, items: sources.map(\.lastPathComponent),
                                   cancel: cancel)
            }
        }
        if cancel.isCancelled { throw CancellationError() }
        let destination = target ?? folder.appending(path: name(for: sources, in: folder, several: several))
        if target != nil, FileManager.default.fileExists(atPath: destination.path) { _ = try trash.put(destination) }
        try FileManager.default.moveItem(at: archive, to: destination)
        return destination.canonical
    }

    /// Extracts `zip` next to it, like Archive Utility: a lone top-level item comes out as
    /// itself, several go in a folder named after the archive. Returns what was made. A zip
    /// with an entry that would land outside its folder is refused before anything is written.
    @concurrent
    public static func extract(_ zip: URL, cancel: CancelFlag = CancelFlag()) async throws -> URL {
        let folder = zip.deletingLastPathComponent().canonical
        let staging = try stagingFolder(near: folder)
        defer { try? FileManager.default.removeItem(at: staging) }
        let out = staging.appending(path: "out")
        try await sentence { try await Zip.unpack(zip, into: out, cancel: cancel) }
        if cancel.isCancelled { throw CancellationError() }
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

    /// Runs ArchiveKit's `work` (stopped by its `cancel` flag, or by cancelling the task); its errors
    /// become `Failure.tool` with ArchiveKit's sentence, in the app's language, or the tool's last words.
    private static func sentence(_ work: () async throws -> Void) async throws {
        do {
            try await work()
        } catch let error as ArchiveError {
            throw Failure.tool(error.localizedDescription)
        }
    }
}
