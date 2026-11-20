import Foundation
import Testing
@testable import KamiroKit

@Test func networkServersMergeAndSort() {
    let list = NetworkServer.merged(smb: ["HomeServer", "batocera"], afp: ["homeserver", "Old Mac"])
    #expect(list.map(\.name) == ["batocera", "HomeServer", "Old Mac"])
    #expect(list.map(\.kind) == [.smb, .smb, .afp])
}

@Test func networkServerAddressIsItsBonjourName() {
    #expect(NetworkServer(name: "HomeServer", kind: .smb).url?.absoluteString == "smb://HomeServer._smb._tcp.local")
    let spaced = NetworkServer(name: "Mathieu’s NAS", kind: .afp).url
    #expect(spaced?.scheme == "afp" && spaced?.host(percentEncoded: false) == "Mathieu’s NAS._afpovertcp._tcp.local")
}

@Test func shareListKeepsDiskShares() {
    let output = """
    Share                                           Type    Comments
    -------------------------------
    appdata                                         Disk    application data
    IPC$                                            Pipe    IPC Service (Media server)
    My Files                                        Disk
    C$                                              Disk    Default share

    3 shares listed
    """
    #expect(ShareList.parse(output).map(\.name) == ["appdata", "My Files"])
    #expect(ShareList.parse(output).first?.comment == "application data")
}

@Test func shareListRetriesWithANewSessionThenAsGuest() throws {
    var tried: [[String]] = []
    let shares = try ShareList.shares(on: URL(string: "smb://HomeServer._smb._tcp.local")!) { options, host in
        tried.append(options)
        #expect(host == "HomeServer._smb._tcp.local")
        if options.contains("-g") { return "isos                Disk    ISO images\n" }
        throw ShareList.Failure.unreachable("smbutil: server rejected the authentication: Authentication error")
    }
    #expect(tried == ShareList.attempts && shares.map(\.name) == ["isos"])
    #expect(throws: ShareList.Failure.self) {
        try ShareList.shares(on: URL(string: "smb://Gone")!) { _, _ in throw ShareList.Failure.unreachable("no") }
    }
}

@Test func serverSpellingsAreOneMachine() {
    let bonjour = URL(string: "smb://GUEST:@HomeServer._smb._tcp.local/isos")!
    #expect(ServerHost.same(bonjour, URL(string: "smb://homeserver.local")!))
    #expect(!ServerHost.same(bonjour, URL(string: "smb://batocera.local")!))
    #expect(ServerHost.server(of: bonjour)?.absoluteString == "smb://HomeServer._smb._tcp.local")
    #expect(ServerHost.share(of: bonjour) == "isos" && ServerHost.share(of: URL(string: "smb://HomeServer")!) == nil)
    #expect(ServerHost.displayName(bonjour) == "HomeServer")
}

@Test func serverPageListsSharesWithMountedOnesInPlace() throws {
    ShareList.fake.withLock { $0 = ["isos", "downloads"] }
    defer { ShareList.fake.withLock { $0 = nil } }
    let server = URL(string: "smb://HomeServer._smb._tcp.local")!
    let mounted = Volume(url: URL(filePath: "/Volumes/isos"), name: "isos", isNetwork: true,
                         remoteURL: URL(string: "smb://me@homeserver.local/isos"))
    let items = try ShareList.items(on: server, mounted: [mounted])
    #expect(items.map(\.url.absoluteString) == ["file:///Volumes/isos", "smb://HomeServer._smb._tcp.local/downloads"])
    #expect(items.allSatisfy { $0.isFolder })
    let place = VirtualPlace.server(server)
    #expect(VirtualPlace(place.url) == place && place.title == "HomeServer")
}

@Test func networkIsASidebarSection() {
    #expect(SidebarSection.allCases == [.home, .pinned, .locations, .network, .tags])
}
