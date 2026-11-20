import Foundation
import Testing
@testable import KamiroKit

private let mount = URL(filePath: "/Volumes/Share", directoryHint: .isDirectory)

@Test func disksAndServersKeepTheirUsualIcons() {
    #expect(PlaceIcon.automatic(for: Volume(url: URL(filePath: "/"), name: "Macintosh HD", isRoot: true)) == .internalDrive)
    #expect(PlaceIcon.automatic(for: Volume(url: mount, name: "Backup", isEjectable: true)) == .externalDrive)
    let smb = Volume(url: mount, name: "isos", isNetwork: true, remoteURL: URL(string: "smb://nas.local/isos"), fileSystem: "smbfs")
    #expect(PlaceIcon.automatic(for: smb) == .network)
}

@Test func cloudMountsShowACloud() {
    let dav = Volume(url: mount, name: "files", isNetwork: true, remoteURL: URL(string: "https://dav.example.com/files"), fileSystem: "webdav")
    let fuse = Volume(url: mount, name: "r2", fileSystem: "macfuse")
    let fuseT = Volume(url: mount, name: "r2", fileSystem: "fuse-t")
    let rcloneNFS = Volume(url: mount, name: "s3", isNetwork: true, remoteURL: URL(string: "nfs://localhost:52000/s3"), fileSystem: "nfs")
    let realNFS = Volume(url: mount, name: "data", isNetwork: true, remoteURL: URL(string: "nfs://nas.local/data"), fileSystem: "nfs")
    #expect([dav, fuse, fuseT, rcloneNFS].allSatisfy { PlaceIcon.automatic(for: $0) == .cloud })
    #expect(PlaceIcon.automatic(for: realNFS) == .network)
}

@Test func aServerKeepsItsIconUnderAnySpelling() {
    let bonjour = PlaceIcons.key(server: URL(string: "smb://HomeServer._smb._tcp.local")!)
    #expect(bonjour == PlaceIcons.key(server: URL(string: "smb://homeserver.local")!))
    #expect(bonjour == PlaceIcons.key(server: URL(string: "afp://HomeServer")!))
}

@Test func aShareKeepsItsIconWhereverItMounts() {
    let first = Volume(url: mount, name: "isos", isNetwork: true, remoteURL: URL(string: "smb://user@NAS._smb._tcp.local/isos"))
    let again = Volume(url: URL(filePath: "/Volumes/isos-1"), name: "isos", isNetwork: true, remoteURL: URL(string: "smb://nas.local/ISOS"))
    #expect(PlaceIcons.key(volume: first) == PlaceIcons.key(volume: again))
    let disk = Volume(url: mount, name: "Backup", uuid: "1234")
    #expect(PlaceIcons.key(volume: disk) == "disk:1234")
}

@Test func pickedIconsSaveAndGoBackToAutomatic() {
    var icons = PlaceIcons()
    icons.set(.cloud, for: "server:r2")
    icons.set(.pc, for: "server:gaming")
    let read = PlaceIcons(saved: icons.saved.merging(["server:old": "gone"]) { a, _ in a })
    #expect(read.icon(for: "server:r2") == .cloud && read.icon(for: "server:old") == nil)
    icons.set(nil, for: "server:r2")
    #expect(icons.icon(for: "server:r2") == nil && icons.icon(for: "server:gaming") == .pc)
}
