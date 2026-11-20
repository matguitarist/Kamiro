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

@Test func networkIsASidebarSection() {
    #expect(SidebarSection.allCases == [.home, .pinned, .locations, .network, .tags])
}
