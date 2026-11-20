import Foundation
import Testing
@testable import KamiroKit

@Test func thumbnailsComeInThreeSizeSteps() {
    #expect(IconSize.thumbnailStep(32) == 64)
    #expect(IconSize.thumbnailStep(64) == 64)
    #expect(IconSize.thumbnailStep(65) == 128)
    #expect(IconSize.thumbnailStep(256) == 256)
}
