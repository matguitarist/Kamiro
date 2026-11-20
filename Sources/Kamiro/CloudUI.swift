import AppKit
import KamiroKit

// MARK: - Cloud status and downloads (S-058)

extension CloudStatus {
    /// The Finder's cloud icons; a downloaded item shows none.
    var symbol: String? {
        switch self {
        case .downloaded: nil
        case .notDownloaded: "icloud.and.arrow.down"
        case .downloading: "arrow.down.circle"
        case .uploading: "icloud.and.arrow.up"
        case .conflict: "exclamationmark.icloud"
        }
    }

    var title: String {
        switch self {
        case .downloaded: String(localized: "Downloaded")
        case .notDownloaded: String(localized: "Not Downloaded")
        case .downloading: String(localized: "Downloading")
        case .uploading: String(localized: "Uploading")
        case .conflict: String(localized: "Conflict")
        }
    }

    /// The icon for lists, in the secondary color like the Finder's.
    var image: NSImage? {
        symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: title) }
    }
}

extension BrowserModel {
    /// The selected items that are in the cloud.
    private var cloudSelection: [FileItem] { selectedItems.filter { cloud[$0.url] != nil } }

    /// Download Now: something selected is only in the cloud (a folder may hold such items).
    var canDownload: Bool { cloudSelection.contains { $0.isFolder || cloud[$0.url] == .notDownloaded } }
    /// Remove Download: something selected is on the Mac.
    var canRemoveDownload: Bool { cloudSelection.contains { $0.isFolder || cloud[$0.url] == .downloaded } }

    /// An app's folder in iCloud Drive belongs to its app: it can't be cut, renamed or trashed (S-057).
    var selectionHasAppFolder: Bool { selection.contains(where: Cloud.isAppFolder) }

    func downloadSelection() { changeDownloads(remove: false) }
    func removeDownloadOfSelection() { changeDownloads(remove: true) }

    private func changeDownloads(remove: Bool) {
        let urls = cloudSelection.map(\.url)
        guard !urls.isEmpty else { return }
        Task {
            // Removing a download can wait on the sync app: never on the main thread.
            let failures = await Self.changeDownloads(urls, remove: remove)
            for (url, message) in failures {
                log.post(.error, "Couldn't \(remove ? "remove the download of" : "download") \(url.path): \(message)", source: "Cloud")
            }
            log.post(.info, "\(remove ? "Removed the download of" : "Downloading") \(urls.count - failures.count) items", source: "Cloud")
            refreshCloud()
        }
    }

    @concurrent
    nonisolated private static func changeDownloads(_ urls: [URL], remove: Bool) async -> [(URL, String)] {
        var failures: [(URL, String)] = []
        for url in urls {
            do {
                if remove { try Cloud.removeDownload(url) } else { try Cloud.startDownloading(url) }
            } catch {
                failures.append((url, error.localizedDescription))
            }
        }
        return failures
    }
}
