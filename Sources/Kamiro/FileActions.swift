import AppKit
import KamiroKit

/// The files on the pasteboard, and which of them were cut. Cut items draw dimmed until
/// they're pasted, Escape is pressed, or something else is copied.
/// Test runs use their own pasteboard, never the one people copy with.
@Observable
final class FileClipboard {
    static let shared = FileClipboard()

    let pasteboard: NSPasteboard = Store.isOverridden
        ? NSPasteboard(name: NSPasteboard.Name("com.mathieuares.kamiro.test")) : .general
    private(set) var cut: Set<URL> = []
    /// Goes up when the cut items change, so lists redraw their rows.
    private(set) var version = 0
    @ObservationIgnored private var cutChange = -1

    func put(_ urls: [URL], cut isCut: Bool) {
        FilePasteboard.write(urls, to: pasteboard)
        cutChange = pasteboard.changeCount
        cut = isCut ? Set(urls.map(\.canonical)) : []
        version += 1
    }

    var urls: [URL] { FilePasteboard.read(from: pasteboard) }
    var hasFiles: Bool { FilePasteboard.hasFiles(pasteboard) }

    /// Cut items count only while the pasteboard still holds them.
    var isCutActive: Bool { !cut.isEmpty && pasteboard.changeCount == cutChange }

    func isCut(_ url: URL) -> Bool { isCutActive && cut.contains(url) }

    func clearCut() {
        guard !cut.isEmpty else { return }
        cut = []
        version += 1
    }
}

/// One Undo stack for file changes in every window, like the Finder's.
enum FileUndo {
    static let manager = UndoManager()
    private final class Target {}
    private static let target = Target()

    /// Where trashed items go: the real Trash, or /tmp/Kamiro-trash in test runs.
    static var trash: TrashCan {
        Store.isOverridden ? .folder(URL(filePath: "/tmp/Kamiro-trash")) : .system
    }

    static func record(_ change: FileChange, name: String) {
        guard !change.isEmpty else { return }
        manager.registerUndo(withTarget: target) { _ in
            MainActor.assumeIsolated { reverse(change, name: name) }
        }
        manager.setActionName(name)
    }

    /// Undoes `change`; registering its inverse while undoing makes it the Redo.
    private static func reverse(_ change: FileChange, name: String) {
        do {
            record(try change.undo(trash: trash), name: name)
        } catch {
            Store.log.post(.error, "Couldn't undo \(name): \(error.localizedDescription)", source: "Undo")
            NSSound.beep()
        }
    }
}

extension BrowserModel {
    var canPaste: Bool { FileClipboard.shared.hasFiles && state == .ready }

    /// The selection in list order.
    var orderedSelection: [URL] { items.filter { selection.contains($0.url) }.map(\.url) }

    // MARK: Cut, copy, paste (S-011)

    func cutSelection() {
        guard !selection.isEmpty else { return }
        FileClipboard.shared.put(orderedSelection, cut: true)
    }

    func copySelection() {
        guard !selection.isEmpty else { return }
        FileClipboard.shared.put(orderedSelection, cut: false)
    }

    /// Pastes here: cut items move, copied items copy, and ⌥⌘V (`move`) moves copied items.
    func paste(move: Bool = false) {
        let clipboard = FileClipboard.shared
        let urls = clipboard.urls
        guard !urls.isEmpty, state == .ready else { return }
        let cutHere = clipboard.isCutActive && Set(urls).isSubset(of: clipboard.cut)
        transfer(move || cutHere ? .move : .copy, urls, into: folder)
        if move || cutHere { clipboard.clearCut() }
    }

    func transfer(_ kind: TransferKind, _ urls: [URL], into destination: URL) {
        TransferCenter.shared.start(kind, sources: urls, into: destination, browser: self)
    }

    /// A drop from the list, a crumb or the sidebar. ⌥ copies, ⌘ moves (S-018).
    @discardableResult
    func drop(_ urls: [URL], into destination: URL) -> Bool {
        let flags = NSEvent.modifierFlags
        let kind = DropRule.kind(sources: urls, destination: destination,
                                 option: flags.contains(.option), command: flags.contains(.command))
        guard !urls.isEmpty, !DropRule.isNoOp(sources: urls, destination: destination, kind: kind) else { return false }
        transfer(kind, urls, into: destination)
        return true
    }

    // MARK: New items (S-015)

    func newFolder() {
        guard state == .ready else { return }
        let url = folder.appending(path: Naming.untitled(String(localized: "untitled folder"), in: folder)).canonical
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            FileUndo.record(.made([url]), name: String(localized: "New Folder"))
            show([url], rename: true)
        } catch {
            fail("Couldn't make a folder in \(folder.path)", error)
        }
    }

    func newFile(_ template: FileTemplate) {
        guard state == .ready else { return }
        do {
            let url = try template.make(in: folder, base: String(localized: "untitled"))
            FileUndo.record(.made([url]), name: String(localized: "New File"))
            show([url], rename: true)
        } catch {
            fail("Couldn't make a file in \(folder.path)", error)
        }
    }

    // MARK: Rename (S-014)

    func beginRename() {
        guard let first = orderedSelection.first else { return }
        beginRename(first)
    }

    /// Renames `url` in place; the list waits for it to appear when it was just made.
    func beginRename(_ url: URL) {
        selection = [url.canonical]
        renameTarget = url.canonical
        renameToken += 1
    }

    /// Renames `url`; returns why it can't, or nil. `next` starts renaming that item after.
    @discardableResult
    func rename(_ url: URL, to newName: String, next: URL? = nil) -> String? {
        if let problem = NameCheck.problem(renaming: url, to: newName) { return problem.message(newName) }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != url.lastPathComponent else {
            if let next { beginRename(next) }
            return nil
        }
        let target = url.deletingLastPathComponent().appending(path: name).canonical
        do {
            try FileManager.default.moveItem(at: url, to: target)
            FileUndo.record(.moved([FileMove(from: url, to: target)]), name: String(localized: "Rename"))
            show([next ?? target], rename: next != nil)
            return nil
        } catch {
            fail("Couldn't rename \(url.path)", error)
            return error.localizedDescription
        }
    }

    /// A rename that changes the extension asks first (S-014).
    func askExtension(_ url: URL, newName: String, change: (old: String, new: String), next: URL?) {
        pendingExtension = ExtensionQuestion(url: url, newName: newName, old: change.old, new: change.new, next: next)
    }

    func answerExtension(use: Bool) {
        guard let question = pendingExtension else { return }
        pendingExtension = nil
        var name = question.newName
        if !use {
            // The new name with the old extension (or none, when it had none).
            let stem = question.new.isEmpty ? name : Naming.split(name).stem
            name = question.old.isEmpty ? stem : "\(stem).\(question.old)"
        }
        if let message = rename(question.url, to: name, next: question.next) {
            NSSound.beep()
            log.post(.warning, "Rename refused: \(message)", source: "Rename")
        }
    }

    // MARK: Trash and delete (S-016)

    func trashSelection() {
        let urls = orderedSelection
        guard !urls.isEmpty else { return }
        var moves: [FileMove] = []
        for url in urls {
            do {
                moves.append(FileMove(from: url, to: try FileUndo.trash.put(url)))
            } catch {
                fail("Couldn't move \(url.path) to the Trash", error)
            }
        }
        FileUndo.record(.trashed(moves), name: String(localized: "Move to Trash"))
        refresh()
    }

    func askDeleteImmediately() {
        guard !selection.isEmpty else { return }
        pendingDelete = orderedSelection
    }

    func deleteImmediately() {
        guard let urls = pendingDelete else { return }
        pendingDelete = nil
        for url in urls {
            do {
                try FileManager.default.removeItem(at: url)
                log.post(.info, "Deleted \(url.path)", source: "Delete")
            } catch {
                fail("Couldn't delete \(url.path)", error)
            }
        }
        refresh()
    }

    // MARK: Conflicts (S-013)

    /// Asks in this window's conflict sheet; questions from several transfers wait in line.
    func ask(_ conflict: Conflict, kind: TransferKind) async -> ConflictAnswer {
        await withCheckedContinuation { continuation in
            let question = ConflictQuestion(conflict: conflict, kind: kind) { [weak self] answer in
                self?.conflicts.removeAll { $0.conflict == conflict }
                continuation.resume(returning: answer)
            }
            conflicts.append(question)
        }
    }

    // MARK: Helpers

    /// Reads the folder again with `urls` selected, then starts renaming the first one.
    func show(_ urls: [URL], rename: Bool = false) {
        reload(selecting: Set(urls))
        if rename, let first = urls.first { beginRename(first) }
    }

    func fail(_ what: String, _ error: any Error) {
        log.post(.error, "\(what): \(error.localizedDescription)", source: "Files")
        NSSound.beep()
    }
}

struct ExtensionQuestion: Equatable {
    let url: URL
    let newName: String
    let old: String
    let new: String
    let next: URL?

    var title: String {
        if new.isEmpty { return String(localized: "Are you sure you want to remove the extension “.\(old)”?") }
        if old.isEmpty { return String(localized: "Are you sure you want to add the extension “.\(new)” to the end of the name?") }
        return String(localized: "Are you sure you want to change the extension from “.\(old)” to “.\(new)”?")
    }

    var useTitle: String {
        if new.isEmpty { return String(localized: "Remove") }
        if old.isEmpty { return String(localized: "Add") }
        return String(localized: "Use .\(new)")
    }

    var keepTitle: String {
        old.isEmpty ? String(localized: "Don’t Add") : String(localized: "Keep .\(old)")
    }
}

extension NameProblem {
    func message(_ name: String) -> String {
        switch self {
        case .empty: String(localized: "Give the item a name.")
        case .colon: String(localized: "Names can’t contain “:”.")
        case .tooLong: String(localized: "This name is too long.")
        case .taken: String(localized: "The name “\(name)” is already taken. Choose a different name.")
        }
    }
}

extension FileTemplate {
    var title: String {
        switch id {
        case "empty": String(localized: "Empty File")
        case "text": String(localized: "Text")
        case "rtf": String(localized: "Rich Text")
        case "markdown": String(localized: "Markdown")
        case "shell": String(localized: "Shell Script")
        default: ext.uppercased() == "JS" ? "JavaScript" : ext.uppercased() == "TS" ? "TypeScript"
            : ext.uppercased() == "PY" ? "Python" : ext.uppercased() == "SWIFT" ? "Swift" : ext.uppercased()
        }
    }
}

extension FileTemplate.Group {
    var title: String {
        switch self {
        case .basic: String(localized: "Basic")
        case .data: String(localized: "Data")
        case .web: String(localized: "Web")
        case .code: String(localized: "Code")
        }
    }
}
