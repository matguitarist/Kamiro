import Foundation
import Synchronization

/// iCloud Drive and the sync apps' folders (Google Drive, OneDrive, Dropbox, Box… in
/// ~/Library/CloudStorage), shown the way the Finder shows them: iCloud Drive at the top of its
/// path with each app's folder in it, and every item's cloud status (S-057, S-058).
public enum Cloud {
    private struct Paths {
        let home: URL
        let fakeStatuses: Bool
        let mobileDocuments: URL
        let drive: URL
        let cloudStorage: URL

        init(home: URL, fakeStatuses: Bool) {
            self.home = home
            self.fakeStatuses = fakeStatuses
            let library = home.canonical.appending(path: "Library")
            mobileDocuments = library.appending(path: "Mobile Documents")
            drive = mobileDocuments.appending(path: "com~apple~CloudDocs")
            cloudStorage = library.appending(path: "CloudStorage")
        }
    }

    private static let paths = Mutex(Paths(home: .homeDirectory, fakeStatuses: false))

    /// Test runs look in a home in /tmp, and read each item's status from its
    /// `com.mathieuares.kamiro.cloud` attribute, since nothing there is really in the cloud.
    public static func configure(home: URL, fakeStatuses: Bool) {
        paths.withLock { $0 = Paths(home: home, fakeStatuses: fakeStatuses) }
    }

    /// Every iCloud container: iCloud Drive's own, and each app's.
    public static var mobileDocuments: URL { paths.withLock { $0.mobileDocuments } }
    /// iCloud Drive.
    public static var drive: URL { paths.withLock { $0.drive } }
    /// Where sync apps built on File Provider keep their folders.
    public static var cloudStorage: URL { paths.withLock { $0.cloudStorage } }
    static var fakeStatuses: Bool { paths.withLock { $0.fakeStatuses } }

    public static let driveName = "iCloud Drive"

    public static var isDriveAvailable: Bool { FileManager.default.fileExists(atPath: drive.path) }

    /// Inside iCloud or a sync app's folder, where items have a cloud status.
    public static func isInCloud(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let path = url.path
        let (icloud, storage) = paths.withLock { ($0.mobileDocuments.path, $0.cloudStorage.path) }
        return [icloud, storage].contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// An app's folder in iCloud Drive: its container's Documents folder.
    public static func isAppFolder(_ url: URL) -> Bool {
        guard url.isFileURL, url.lastPathComponent == "Documents" else { return false }
        let container = url.deletingLastPathComponent()
        let (icloud, drive) = paths.withLock { ($0.mobileDocuments.path, $0.drive.path) }
        return container.deletingLastPathComponent().path == icloud && container.path != drive
    }

    /// The top of a path, like a disk: iCloud Drive and each sync app's folder.
    public static func isTop(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        return url.path == drive.path || url.deletingLastPathComponent().path == cloudStorage.path
    }

    /// The folder Up goes to when it isn't the one on disk: iCloud Drive for an app's folder.
    /// nil means the usual parent; `.some(nil)` means none.
    static func parent(of url: URL) -> URL?? {
        if isTop(url) { return .some(nil) }
        if isAppFolder(url) { return .some(drive) }
        return nil
    }

    /// A place's name in the sidebar, the path and the title.
    public struct Place: Hashable, Sendable {
        public let url: URL
        public let name: String
        public let isICloud: Bool
    }

    /// iCloud Drive (when it's on), then each sync app's folder by name.
    public static func places() -> [Place] {
        var list: [Place] = isDriveAvailable ? [Place(url: drive, name: driveName, isICloud: true)] : []
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: cloudStorage, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        list += folders
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { Place(url: $0.canonical, name: providerName(of: $0), isICloud: false) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return list
    }

    /// The name the Finder gives: "iCloud Drive", an app's name for its folder, a sync app's name.
    public static func name(of url: URL) -> String? {
        guard url.isFileURL else { return nil }
        if url.path == drive.path { return driveName }
        if isAppFolder(url) { return appName(of: url.deletingLastPathComponent()) }
        if url.deletingLastPathComponent().path == cloudStorage.path { return providerName(of: url) }
        return nil
    }

    /// Any folder's name as people see it.
    public static func displayName(of url: URL) -> String {
        name(of: url) ?? FileManager.default.displayName(atPath: url.path)
    }

    /// "com~apple~Numbers" is Numbers: macOS knows the app's name; without it, the last word.
    public static func appName(of container: URL) -> String {
        let shown = FileManager.default.displayName(atPath: container.path)
        if shown != container.lastPathComponent { return shown }
        let last = container.lastPathComponent.split(separator: "~").last.map(String.init) ?? container.lastPathComponent
        return last.prefix(1).uppercased() + last.dropFirst()
    }

    /// "GoogleDrive-someone@example.com" is Google Drive, "OneDrive-Personal" OneDrive,
    /// "OneDrive-Contoso" OneDrive – Contoso.
    public static func providerName(of folder: URL) -> String {
        let shown = FileManager.default.displayName(atPath: folder.path)
        if shown != folder.lastPathComponent { return shown }
        let raw = folder.lastPathComponent
        let provider = String(raw.prefix { $0 != "-" })
        let name = knownProviders[provider] ?? provider
        let rest = raw.dropFirst(provider.count + 1)
        return rest.isEmpty || rest.contains("@") || rest == "Personal" ? name : "\(name) – \(rest)"
    }

    static let knownProviders = ["GoogleDrive": "Google Drive", "SynologyDrive": "Synology Drive",
                                 "ProtonDrive": "Proton Drive", "pCloudDrive": "pCloud Drive"]

    /// The apps' folders iCloud Drive shows at its top, named after their app. Like the Finder,
    /// only apps that keep documents there: most containers hold only settings.
    public static func appFolders(showHidden: Bool = false) -> [FileItem] {
        let containers = (try? FileManager.default.contentsOfDirectory(
            at: mobileDocuments, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let drivePath = drive.path
        return containers.compactMap { container in
            guard container.path != drivePath else { return nil }
            let documents = container.appending(path: "Documents")
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: documents.path),
                  names.contains(where: { !$0.hasPrefix(".") }),
                  let item = FolderReader.item(at: documents) else { return nil }
            return item.named(appName(of: container))
        }
    }

    // MARK: Downloads (S-058)

    /// Download Now: the item, or a folder's items, come down from the cloud.
    public static func startDownloading(_ url: URL) throws {
        if fakeStatuses { try CloudStatus.writeFake(.downloaded, to: url); return }
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    /// Remove Download: the item stays in the cloud and leaves the Mac.
    public static func removeDownload(_ url: URL) throws {
        if fakeStatuses { try CloudStatus.writeFake(.notDownloaded, to: url); return }
        try FileManager.default.evictUbiquitousItem(at: url)
    }
}

/// Where an item in iCloud or a sync app's folder stands, as the Finder's cloud icons show it.
public enum CloudStatus: String, Sendable, CaseIterable {
    case downloaded, notDownloaded, downloading, uploading, conflict

    /// nil for an item that isn't in the cloud. A conflict shows first, then what's moving.
    public init?(isUbiquitous: Bool?, downloadingStatus: URLUbiquitousItemDownloadingStatus?, isDownloading: Bool?,
                 isUploading: Bool?, hasConflicts: Bool?) {
        guard isUbiquitous == true else { return nil }
        if hasConflicts == true {
            self = .conflict
        } else if isDownloading == true {
            self = .downloading
        } else if isUploading == true {
            self = .uploading
        } else if downloadingStatus == .notDownloaded {
            self = .notDownloaded
        } else {
            self = .downloaded
        }
    }

    /// These keys cost about 1 ms an item (a plain listing, 0.01 ms): read only in cloud folders.
    public static let keys: Set<URLResourceKey> = [
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey,
        .ubiquitousItemIsUploadingKey, .ubiquitousItemHasUnresolvedConflictsKey,
    ]

    public static func read(_ url: URL) -> CloudStatus? {
        guard Cloud.isInCloud(url) else { return nil }
        if Cloud.fakeStatuses { return readFake(url) }
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        return CloudStatus(isUbiquitous: values.isUbiquitousItem, downloadingStatus: values.ubiquitousItemDownloadingStatus,
                           isDownloading: values.ubiquitousItemIsDownloading, isUploading: values.ubiquitousItemIsUploading,
                           hasConflicts: values.ubiquitousItemHasUnresolvedConflicts)
    }

    static let fakeAttribute = "com.mathieuares.kamiro.cloud"

    /// Test runs: the attribute's status, or downloaded.
    static func readFake(_ url: URL) -> CloudStatus {
        var buffer = [UInt8](repeating: 0, count: 64)
        let length = getxattr(url.path, fakeAttribute, &buffer, buffer.count, 0, 0)
        guard length > 0 else { return .downloaded }
        return CloudStatus(rawValue: String(decoding: buffer.prefix(length), as: UTF8.self)) ?? .downloaded
    }

    static func writeFake(_ status: CloudStatus, to url: URL) throws {
        let bytes = Array(status.rawValue.utf8)
        guard setxattr(url.path, fakeAttribute, bytes, bytes.count, 0, 0) == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
