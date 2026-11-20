import Foundation
import Testing
@testable import KamiroKit

@Test func crumbsGoFromTheRootDown() {
    let location = Location(URL(fileURLWithPath: "/Users/someone/Documents"))
    #expect(location.crumbs.map(\.path) == ["/", "/Users", "/Users/someone", "/Users/someone/Documents"])
    #expect(location.parent?.url.path == "/Users/someone")
    #expect(Location(URL(fileURLWithPath: "/")).parent == nil)
}
