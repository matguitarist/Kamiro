import Foundation
import Testing
@testable import KamiroKit

@Test func cloudStatusShowsConflictsFirstThenWhatMoves() {
    #expect(CloudStatus(isUbiquitous: false, downloadingStatus: .notDownloaded, isDownloading: nil, isUploading: nil, hasConflicts: nil) == nil)
    #expect(CloudStatus(isUbiquitous: nil, downloadingStatus: nil, isDownloading: nil, isUploading: nil, hasConflicts: nil) == nil)
    #expect(CloudStatus(isUbiquitous: true, downloadingStatus: .notDownloaded, isDownloading: false, isUploading: false, hasConflicts: false) == .notDownloaded)
    #expect(CloudStatus(isUbiquitous: true, downloadingStatus: .current, isDownloading: false, isUploading: false, hasConflicts: false) == .downloaded)
    // An older copy on the Mac is still on the Mac.
    #expect(CloudStatus(isUbiquitous: true, downloadingStatus: .downloaded, isDownloading: false, isUploading: false, hasConflicts: false) == .downloaded)
    #expect(CloudStatus(isUbiquitous: true, downloadingStatus: .notDownloaded, isDownloading: true, isUploading: false, hasConflicts: false) == .downloading)
    #expect(CloudStatus(isUbiquitous: true, downloadingStatus: .current, isDownloading: false, isUploading: true, hasConflicts: false) == .uploading)
    #expect(CloudStatus(isUbiquitous: true, downloadingStatus: .current, isDownloading: true, isUploading: true, hasConflicts: true) == .conflict)
}

@Test func syncAppsAreNamedLikeTheFinderNamesThem() {
    let storage = URL(filePath: "/nowhere/Library/CloudStorage")
    #expect(Cloud.providerName(of: storage.appending(path: "GoogleDrive-someone@example.com")) == "Google Drive")
    #expect(Cloud.providerName(of: storage.appending(path: "OneDrive-Personal")) == "OneDrive")
    #expect(Cloud.providerName(of: storage.appending(path: "OneDrive-Contoso")) == "OneDrive – Contoso")
    #expect(Cloud.providerName(of: storage.appending(path: "Dropbox")) == "Dropbox")
    #expect(Cloud.appName(of: URL(filePath: "/nowhere/Library/Mobile Documents/iCloud~md~obsidian")) == "Obsidian")
}

@Test func aCloudFolderShowsTheCloudColumnUntilItsViewChanges() {
    var memory = ViewMemory()
    let folder = URL(filePath: "/tmp/cloud")
    #expect(memory.view(for: folder).columns == ListColumn.standard)
    #expect(memory.view(for: folder, inCloud: true).columns == [.name, .cloud, .modified, .size, .kind])
    var view = memory.view(for: folder, inCloud: true)
    view.toggle(.cloud)
    memory.remember(view, for: folder)
    #expect(!memory.view(for: folder, inCloud: true).columns.contains(.cloud))
}

/// These change where Cloud looks, so they run one at a time.
@Suite(.serialized) struct CloudPlaceTests {
    let home = FileManager.default.temporaryDirectory.appending(path: "KamiroCloud-\(UUID().uuidString)")

    private func make(_ path: String, file: Bool = false) throws {
        let url = home.appending(path: path)
        if file {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        } else {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    @Test func iCloudDriveIsATopWithTheAppsFoldersInIt() throws {
        try make("Library/Mobile Documents/com~apple~CloudDocs/Projects")
        try make("Library/Mobile Documents/iCloud~md~obsidian/Documents/Vault/Index.md", file: true)
        try make("Library/Mobile Documents/com~apple~mail/Documents")
        try make("Library/Mobile Documents/iCloud~com~example~hidden/Documents/.settings", file: true)
        try make("Library/CloudStorage/GoogleDrive-someone@example.com/My Drive")
        defer { try? FileManager.default.removeItem(at: home); Cloud.configure(home: .homeDirectory, fakeStatuses: false) }
        Cloud.configure(home: home, fakeStatuses: true)

        let drive = Cloud.drive
        #expect(Cloud.places().map(\.name) == ["iCloud Drive", "Google Drive"])
        let apps = Cloud.appFolders()
        #expect(apps.map(\.name) == ["Obsidian"])
        let obsidian = try #require(apps.first).url
        #expect(obsidian.lastPathComponent == "Documents" && Cloud.isAppFolder(obsidian))
        #expect(!Cloud.isAppFolder(drive.appending(path: "Documents")))
        #expect(Location(drive).parent == nil)
        #expect(Location(obsidian.appending(path: "Vault")).crumbs == [drive, obsidian, obsidian.appending(path: "Vault")].map(\.canonical))
        let google = Cloud.cloudStorage.appending(path: "GoogleDrive-someone@example.com")
        #expect(Location(google.appending(path: "My Drive")).crumbs == [google, google.appending(path: "My Drive")].map(\.canonical))
        #expect(Cloud.displayName(of: drive) == "iCloud Drive" && Cloud.displayName(of: obsidian) == "Obsidian")

        #expect(Cloud.isInCloud(drive.appending(path: "Projects")) && Cloud.isInCloud(google))
        #expect(!Cloud.isInCloud(home.appending(path: "Documents")))
        #expect(CloudStatus.read(home.appending(path: "Library")) == nil)
        let projects = drive.appending(path: "Projects")
        #expect(CloudStatus.read(projects) == .downloaded)
        try Cloud.removeDownload(projects)
        #expect(CloudStatus.read(projects) == .notDownloaded)
        try Cloud.startDownloading(projects)
        #expect(CloudStatus.read(projects) == .downloaded)
    }
}
