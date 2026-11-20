import Foundation
import Testing
@testable import KamiroKit

private let backup = URL(filePath: "/Volumes/Backup", directoryHint: .isDirectory)

@Test func anEjectableDiskOffersEjectAndRename() {
    let disk = Volume(url: backup, name: "Backup", isEjectable: true, canRename: true)
    #expect(disk.actions == [.open, .openInNewTab, .openInTerminal, nil, .rename, .copyPath, .properties, nil, .eject])
}

@Test func theStartupDiskNeverOffersEject() {
    let root = Volume(url: URL(filePath: "/"), name: "Macintosh HD", isRoot: true, isEjectable: true, canRename: true)
    #expect(!root.actions.contains(.eject))
    #expect(root.actions.contains(.rename))
}

@Test func aReadOnlyImageHasNoRenameButEjects() {
    let image = Volume(url: backup, name: "Installer", isEjectable: true, canRename: false)
    #expect(!image.actions.contains(.rename))
    #expect(image.actions.last == .eject)
}

@Test func aServerEjects() {
    let share = Volume(url: backup, name: "Share", isNetwork: true)
    #expect(share.actions.last == .eject)
}

@Test func diskNamesFollowFileNameRules() {
    #expect(Volumes.problem(naming: "  ") == .empty)
    #expect(Volumes.problem(naming: "a:b") == .colon)
    #expect(Volumes.problem(naming: String(repeating: "x", count: 300)) == .tooLong)
    #expect(Volumes.problem(naming: "Backup 2") == nil)
}

@Test func theStartupDiskTellsItsSpace() throws {
    let facts = try #require(Volumes.facts(at: URL(filePath: "/")))
    #expect((facts.capacity ?? 0) > 0)
    #expect(facts.used != nil)
    #expect(Volumes.facts(at: URL(filePath: "/tmp")) == nil)
    #expect(Volumes.isVolumeRoot(URL(filePath: "/")))
}

@Test func usedSpaceIsCapacityLessAvailable() {
    let facts = VolumeFacts(name: "X", format: "APFS", capacity: 100, available: 30, isReadOnly: false)
    #expect(facts.used == 70)
}
