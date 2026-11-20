import Foundation
import Testing
@testable import KamiroKit

@Test func serverAddressesAreReadLikeTheFinder() {
    #expect(ServerAddress.parse("smb://nas.local/Media")?.absoluteString == "smb://nas.local/Media")
    #expect(ServerAddress.parse("  nas.local ")?.absoluteString == "smb://nas.local")
    #expect(ServerAddress.parse("afp://old-mac")?.absoluteString == "afp://old-mac")
    #expect(ServerAddress.parse("https://dav.example.com/files")?.absoluteString == "https://dav.example.com/files")
    #expect(ServerAddress.parse("\\\\NAS\\Media\\Movies")?.absoluteString == "smb://NAS/Media/Movies")
    #expect(ServerAddress.parse("") == nil)
    #expect(ServerAddress.parse("smb://") == nil)
    #expect(ServerAddress.parse("ssh://box") == nil)
}

@Test func recentServersKeepTheNewestTenOnce() {
    var recent = RecentServers()
    for n in 1...12 { recent.add(URL(string: "smb://server\(n)")!) }
    #expect(recent.addresses.count == 10)
    #expect(recent.addresses.first == "smb://server12")
    recent.add(URL(string: "SMB://Server5")!)
    #expect(recent.addresses.first == "SMB://Server5")
    #expect(recent.addresses.filter { $0.lowercased() == "smb://server5" }.count == 1)
    recent.remove("SMB://Server5")
    #expect(!recent.addresses.contains("SMB://Server5"))
}
