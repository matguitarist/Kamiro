import AppKit
import UniformTypeIdentifiers
import KamiroKit

// MARK: - Compress and extract (S-035)

extension BrowserModel {
    /// The selection, when every item sits in one real folder the archive can go in.
    var compressTargets: [URL] {
        let urls = orderedSelection
        guard let parent = urls.first?.deletingLastPathComponent().canonical,
              urls.allSatisfy({ $0.deletingLastPathComponent().canonical == parent }) else { return [] }
        return urls
    }

    /// The selection when it's only zip archives.
    var extractTargets: [URL] {
        let urls = orderedSelection
        return !urls.isEmpty && urls.allSatisfy(Archive.isZip) ? urls : []
    }

    /// "Compress “Photos”", "Compress 3 Items", like the Finder.
    var compressTitle: String {
        let urls = compressTargets
        return urls.count == 1 ? String(localized: "Compress “\(urls[0].lastPathComponent)”")
            : String(localized: "Compress \(urls.count) Items")
    }

    func compressSelection() {
        let urls = compressTargets
        guard let first = urls.first else { return }
        let title = urls.count == 1 ? String(localized: "Compressing “\(first.lastPathComponent)”")
            : String(localized: "Compressing \(urls.count) items")
        let several = String(localized: "Archive")
        TransferCenter.shared.startJob(title, undoName: String(localized: "Compress"),
                                       in: first.deletingLastPathComponent(), browser: self) { cancel, _ in
            try await Archive.compress(urls, several: several, cancel: cancel)
        }
    }

    /// Compress To…: several items into a zip named and placed in a save panel.
    func compressSelectionTo() {
        let urls = compressTargets
        guard urls.count > 1, let parent = urls.first?.deletingLastPathComponent() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.directoryURL = parent
        panel.nameFieldStringValue = Archive.name(for: urls, in: parent, several: String(localized: "Archive"))
        panel.prompt = String(localized: "Compress")
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let target = panel.url else { return }
        compress(urls, to: target)
    }

    /// Zips `urls` into `target`; one already there goes to the Trash (the panel asked).
    func compress(_ urls: [URL], to target: URL) {
        let trash = FileUndo.trash
        TransferCenter.shared.startJob(String(localized: "Compressing to “\(target.lastPathComponent)”"),
                                       undoName: String(localized: "Compress"),
                                       in: target.deletingLastPathComponent(), browser: self) { cancel, _ in
            try await Archive.compress(urls, to: target, trash: trash, cancel: cancel)
        }
    }

    /// Extract Here: each selected zip comes out next to itself.
    func extractSelection() {
        for zip in extractTargets {
            TransferCenter.shared.startJob(String(localized: "Extracting “\(zip.lastPathComponent)”"),
                                           undoName: String(localized: "Extract"),
                                           in: zip.deletingLastPathComponent(), browser: self) { cancel, _ in
                try await Archive.extract(zip, cancel: cancel)
            }
        }
    }
}
