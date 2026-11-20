import AppKit
import Foundation
import Synchronization
import Testing
@testable import KamiroKit

private func scratch() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "KamiroOps-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.canonical
}

private func make(_ url: URL, _ text: String = "x") throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

private func names(_ folder: URL) -> Set<String> {
    Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
}

// MARK: S-011

@Test func cutThenPasteMovesAndCopyThenPasteCopies() async throws {
    let root = try scratch()
    let a = root.appending(path: "a"), b = root.appending(path: "b")
    try make(a.appending(path: "one.txt"))
    try make(a.appending(path: "Folder/inner.txt"))
    try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)

    let copied = await TransferEngine.run(.copy, sources: [a.appending(path: "one.txt"), a.appending(path: "Folder")], into: b)
    #expect(copied.failures.isEmpty)
    #expect(names(b) == ["one.txt", "Folder"])
    #expect(exists(b.appending(path: "Folder/inner.txt")))
    #expect(exists(a.appending(path: "one.txt")))

    let c = root.appending(path: "c")
    try FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
    let moved = await TransferEngine.run(.move, sources: [a.appending(path: "one.txt")], into: c)
    #expect(moved.placed == [c.appending(path: "one.txt").canonical])
    #expect(!exists(a.appending(path: "one.txt")))
    #expect(moved.change == .batch([.moved([FileMove(from: a.appending(path: "one.txt"), to: c.appending(path: "one.txt"))])]))
}

@Test func pastingIntoTheSameFolderMakesCopies() async throws {
    let root = try scratch()
    try make(root.appending(path: "report.pdf"))
    try FileManager.default.createDirectory(at: root.appending(path: "Photos"), withIntermediateDirectories: true)
    _ = await TransferEngine.run(.copy, sources: [root.appending(path: "report.pdf"), root.appending(path: "Photos")], into: root)
    _ = await TransferEngine.run(.copy, sources: [root.appending(path: "report.pdf")], into: root)
    #expect(names(root) == ["report.pdf", "report copy.pdf", "report copy 2.pdf", "Photos", "Photos copy"])
    // Moving into the same folder does nothing.
    let moved = await TransferEngine.run(.move, sources: [root.appending(path: "report.pdf")], into: root)
    #expect(moved.change.isEmpty && exists(root.appending(path: "report.pdf")))
}

@Test func namingFollowsTheFinder() {
    let folder = URL(filePath: "/nowhere-\(UUID().uuidString)")
    #expect(Naming.copy(of: "report.pdf", in: folder) == "report copy.pdf")
    #expect(Naming.copy(of: "report.pdf", in: folder, taken: { $0 == "report copy.pdf" }) == "report copy 2.pdf")
    #expect(Naming.copy(of: "v1.2", isFolder: true, in: folder) == "v1.2 copy")
    #expect(Naming.copy(of: "Sample.app", in: folder) == "Sample copy.app")
    #expect(Naming.numbered("report.pdf", in: folder) == "report 2.pdf")
    #expect(Naming.untitled("untitled folder", in: folder, taken: { $0 == "untitled folder" }) == "untitled folder 2")
    #expect(Naming.split(".zshrc").ext == "")
}

@Test func copiedFilesGoOnThePasteboardAsFileURLs() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("KamiroTest-\(UUID().uuidString)"))
    let urls = [URL(filePath: "/tmp/a.txt"), URL(filePath: "/tmp/b c.pdf")]
    FilePasteboard.write(urls, to: pasteboard)
    #expect(FilePasteboard.hasFiles(pasteboard))
    #expect(FilePasteboard.read(from: pasteboard) == urls.map(\.canonical))
    #expect(pasteboard.types?.contains(.fileURL) == true)
    pasteboard.releaseGlobally()
}

// MARK: S-012

@Test func progressCountsBytesUpFrontAndClonesFinish() async throws {
    let root = try scratch()
    let source = root.appending(path: "src")
    try make(source.appending(path: "a.bin"), String(repeating: "a", count: 1000))
    try make(source.appending(path: "sub/b.bin"), String(repeating: "b", count: 500))
    let measured = TransferEngine.measure(source)
    #expect(measured.bytes == 1500 && measured.files == 2)
    let seen = Mutex<[TransferProgress]>([])
    let target = root.appending(path: "dst")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    _ = await TransferEngine.run(.copy, sources: [source], into: target, progress: { p in seen.withLock { $0.append(p) } })
    let all = seen.withLock { $0 }
    #expect(all.first?.totalBytes == 1500)
    #expect(all.last?.doneBytes == 1500 && all.last?.fraction == 1)
}

@Test func cancelRemovesThePartialCopyAndKeepsTheSources() async throws {
    let root = try scratch()
    let source = root.appending(path: "Big")
    for n in 1...20 { try make(source.appending(path: "file \(n).txt"), "data \(n)") }
    let target = root.appending(path: "dst")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    let cancel = CancelFlag()
    let outcome = await TransferEngine.run(.copy, sources: [source], into: target, cancel: cancel, progress: { p in
        if p.doneBytes > 0 { cancel.cancel() }
    })
    #expect(outcome.cancelled)
    #expect(names(target).isEmpty)
    #expect(names(source).count == 20)
    // A cancelled move leaves its sources where they were too.
    let moved = await TransferEngine.run(.move, sources: [source], into: target, cancel: cancel)
    #expect(moved.cancelled && names(source).count == 20)
}

@Test func aFolderCantGoInsideItself() async throws {
    let root = try scratch()
    try make(root.appending(path: "A/B/x.txt"))
    let outcome = await TransferEngine.run(.move, sources: [root.appending(path: "A")], into: root.appending(path: "A/B"))
    #expect(outcome.failures.count == 1 && exists(root.appending(path: "A/B/x.txt")))
}

// MARK: S-013

@Test func keepBothNumbersAndReplaceTrashesTheOldOne() async throws {
    let root = try scratch()
    let trash = TrashCan.folder(root.appending(path: "Trash"))
    try make(root.appending(path: "a/notes.md"), "new")
    try make(root.appending(path: "b/notes.md"), "old")
    let both = await TransferEngine.run(.copy, sources: [root.appending(path: "a/notes.md")], into: root.appending(path: "b"),
                                        trash: trash) { _ in ConflictAnswer(.keepBoth) }
    #expect(both.placed.map(\.lastPathComponent) == ["notes 2.md"])
    let replaced = await TransferEngine.run(.copy, sources: [root.appending(path: "a/notes.md")], into: root.appending(path: "b"),
                                            trash: trash) { _ in ConflictAnswer(.replace) }
    #expect(replaced.failures.isEmpty)
    #expect(try String(contentsOf: root.appending(path: "b/notes.md"), encoding: .utf8) == "new")
    #expect(try String(contentsOf: root.appending(path: "Trash/notes.md"), encoding: .utf8) == "old")
}

@Test func applyToAllAnswersOnce() async throws {
    let root = try scratch()
    for name in ["1.txt", "2.txt", "3.txt"] {
        try make(root.appending(path: "a/\(name)"))
        try make(root.appending(path: "b/\(name)"))
    }
    let asked = Mutex(0)
    let outcome = await TransferEngine.run(.copy, sources: ["1.txt", "2.txt", "3.txt"].map { root.appending(path: "a/\($0)") },
                                           into: root.appending(path: "b")) { conflict in
        asked.withLock { $0 += 1 }
        #expect(conflict.remaining == 2)
        return ConflictAnswer(.skip, applyToAll: true)
    }
    #expect(asked.withLock { $0 } == 1)
    #expect(outcome.placed.isEmpty && names(root.appending(path: "b")).count == 3)
}

// MARK: S-014

@Test func namesAreCheckedBeforeRenaming() throws {
    let root = try scratch()
    let notes = root.appending(path: "notes.md")
    try make(notes)
    try make(root.appending(path: "other.md"))
    #expect(NameCheck.problem(renaming: notes, to: "  ") == .empty)
    #expect(NameCheck.problem(renaming: notes, to: "a:b.md") == .colon)
    #expect(NameCheck.problem(renaming: notes, to: String(repeating: "a", count: 256)) == .tooLong)
    #expect(NameCheck.problem(renaming: notes, to: "other.md") == .taken)
    #expect(NameCheck.problem(renaming: notes, to: "Notes.md") == nil)
    #expect(NameCheck.problem(renaming: notes, to: "fresh.md") == nil)
    let change = NameCheck.extensionChange(from: "notes.md", to: "notes.txt", isFolder: false)
    #expect(change?.old == "md" && change?.new == "txt")
    #expect(NameCheck.extensionChange(from: "notes.md", to: "plan.MD", isFolder: false) == nil)
    #expect(NameCheck.extensionChange(from: "v1", to: "v1.2", isFolder: true) == nil)
}

// MARK: S-015

@Test func everyTemplateWritesAValidFile() throws {
    let root = try scratch()
    #expect(Set(FileTemplate.all.map(\.group)) == Set(FileTemplate.Group.allCases))
    for template in FileTemplate.all {
        let url = try template.make(in: root, base: "untitled")
        #expect(exists(url))
        #expect(url.pathExtension == template.ext)
    }
    let json = try Data(contentsOf: root.appending(path: "untitled.json"))
    #expect((try? JSONSerialization.jsonObject(with: json)) != nil)
    #expect(XMLParser(data: try Data(contentsOf: root.appending(path: "untitled.xml"))).parse())
    let shell = root.appending(path: "untitled.sh")
    #expect(try String(contentsOf: shell, encoding: .utf8).hasPrefix("#!"))
    #expect(FileManager.default.isExecutableFile(atPath: shell.path))
    // A second one gets the next name.
    #expect(try FileTemplate.all[1].make(in: root, base: "untitled").lastPathComponent == "untitled 2.txt")
}

// MARK: S-016, S-017

@Test func trashCanPutsBackAndUndoReversesEachChange() throws {
    let root = try scratch()
    let trash = TrashCan.folder(root.appending(path: "Trash"))
    let a = root.appending(path: "a.txt")
    try make(a)

    // Trash, then undo puts it back, redo trashes it again.
    let trashed = FileChange.trashed([FileMove(from: a, to: try trash.put(a))])
    #expect(!exists(a))
    let putBack = try trashed.undo(trash: trash)
    #expect(exists(a))
    _ = try putBack.undo(trash: trash)
    #expect(!exists(a))
    _ = try FileChange.trashed([FileMove(from: a, to: root.appending(path: "Trash/a.txt"))]).undo(trash: trash)

    // Rename.
    let b = root.appending(path: "b.txt")
    try FileManager.default.moveItem(at: a, to: b)
    let redo = try FileChange.moved([FileMove(from: a, to: b)]).undo(trash: trash)
    #expect(exists(a) && !exists(b))
    _ = try redo.undo(trash: trash)
    #expect(exists(b) && !exists(a))

    // New item: undo trashes it.
    let folder = root.appending(path: "untitled folder")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    _ = try FileChange.made([folder]).undo(trash: trash)
    #expect(!exists(folder))
}

@Test func aBatchMoveUndoesAsOneStep() async throws {
    let root = try scratch()
    let trash = TrashCan.folder(root.appending(path: "Trash"))
    for name in ["1.txt", "2.txt", "3.txt"] { try make(root.appending(path: "a/\(name)")) }
    try make(root.appending(path: "b/3.txt"), "old")
    let outcome = await TransferEngine.run(.move, sources: ["1.txt", "2.txt", "3.txt"].map { root.appending(path: "a/\($0)") },
                                           into: root.appending(path: "b"), trash: trash) { _ in ConflictAnswer(.replace) }
    #expect(names(root.appending(path: "a")).isEmpty)
    let redo = try outcome.change.undo(trash: trash)
    #expect(names(root.appending(path: "a")) == ["1.txt", "2.txt", "3.txt"])
    #expect(try String(contentsOf: root.appending(path: "b/3.txt"), encoding: .utf8) == "old")
    _ = try redo.undo(trash: trash)
    #expect(names(root.appending(path: "a")).isEmpty && names(root.appending(path: "b")).count == 3)
}

// MARK: S-018

@Test func dropsMoveOnTheSameDiskAndCopyWithOption() throws {
    let root = try scratch()
    let source = [root.appending(path: "x.txt")]
    try make(source[0])
    #expect(DropRule.kind(sources: source, destination: root, option: false, command: false) == .move)
    #expect(DropRule.kind(sources: source, destination: root, option: true, command: false) == .copy)
    #expect(DropRule.kind(sources: source, destination: root, option: false, command: true) == .move)
    #expect(DropRule.isNoOp(sources: source, destination: root, kind: .move))
    #expect(!DropRule.isNoOp(sources: source, destination: root, kind: .copy))
    #expect(DropRule.isNoOp(sources: [root], destination: root, kind: .copy))
}
