import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import KamiroKit

private func folder() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "KamiroFacts-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test func picturesHaveTheirDimensions() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "wide.png")
    let context = try #require(CGContext(data: nil, width: 64, height: 24, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = try #require(context.makeImage())
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    let facts = await ItemFacts.media(of: url)
    #expect(facts.dimensionsText == "64 × 24")
    #expect(facts.duration == nil)
}

@Test func soundsHaveTheirLength() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    // 3 seconds of silence, 8 kHz mono 16-bit WAV.
    let rate = 8_000, seconds = 3
    let samples = Data(count: rate * seconds * 2)
    var wav = Data()
    func add(_ text: String) { wav.append(contentsOf: Array(text.utf8)) }
    func add32(_ value: Int) { withUnsafeBytes(of: UInt32(value).littleEndian) { wav.append(contentsOf: $0) } }
    func add16(_ value: Int) { withUnsafeBytes(of: UInt16(value).littleEndian) { wav.append(contentsOf: $0) } }
    add("RIFF"); add32(36 + samples.count); add("WAVE")
    add("fmt "); add32(16); add16(1); add16(1); add32(rate); add32(rate * 2); add16(2); add16(16)
    add("data"); add32(samples.count)
    wav.append(samples)
    let url = dir.appending(path: "quiet.wav")
    try wav.write(to: url)
    let facts = await ItemFacts.media(of: url)
    #expect(facts.durationText == "0:03")
    #expect(facts.dimensionsText == nil)
}

@Test func pdfsHaveTheirPageCount() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "two.pdf")
    var box = CGRect(x: 0, y: 0, width: 200, height: 200)
    let pdf = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
    for _ in 0..<2 { pdf.beginPDFPage(nil); pdf.endPDFPage() }
    pdf.closePDF()
    #expect(await ItemFacts.media(of: url).pages == 2)
}

@Test func otherFilesHaveNoMediaFacts() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "notes.txt")
    try Data("hello".utf8).write(to: url)
    #expect(await ItemFacts.media(of: url) == MediaFacts())
}

@Test func longDurationsShowHours() {
    #expect(MediaFacts(duration: 3727).durationText == "1:02:07")
    #expect(MediaFacts(duration: 205).durationText == "3:25")
}
