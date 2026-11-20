import AppKit
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
                                       in: first.deletingLastPathComponent(), browser: self) { cancel in
            try await Archive.compress(urls, several: several, cancel: cancel)
        }
    }

    /// Extract Here: each selected zip comes out next to itself.
    func extractSelection() {
        for zip in extractTargets {
            TransferCenter.shared.startJob(String(localized: "Extracting “\(zip.lastPathComponent)”"),
                                           undoName: String(localized: "Extract"),
                                           in: zip.deletingLastPathComponent(), browser: self) { cancel in
                try await Archive.extract(zip, cancel: cancel)
            }
        }
    }
}
