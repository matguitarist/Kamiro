import AVFoundation
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import KamiroKit

private func tempFolder() throws -> URL {
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "kamiro-convert-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

/// A 120 x 80 picture, half transparent, written with ImageIO.
private func picture(_ name: String, in folder: URL, type: UTType = .png) throws -> URL {
    let context = CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 60, height: 80))
    let url = folder.appending(path: name)
    try Converter.write([context.makeImage()!], type: type, to: url)
    return url
}

/// Two seconds of silent video, 64 x 64, made with AVAssetWriter.
private func video(in folder: URL) async throws -> URL {
    let url = folder.appending(path: "clip.mov")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 64,
        kCVPixelBufferHeightKey as String: 64])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<20 {
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        CVPixelBufferLockBaseAddress(buffer!, [])
        memset(CVPixelBufferGetBaseAddress(buffer!), Int32(frame * 12), CVPixelBufferGetDataSize(buffer!))
        CVPixelBufferUnlockBaseAddress(buffer!, [])
        adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
    }
    input.markAsFinished()
    await writer.finishWriting()
    #expect(writer.status == .completed)
    return url
}

@Test func everyImageFormatRoundTrips() async throws {
    let folder = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = try picture("photo.png", in: folder)
    for conversion in Conversion.allCases where conversion.group == .image && conversion.isAvailable && !conversion.isSameFormat(as: source) {
        let made = try await Converter.convert(source, to: conversion)
        let image = CGImageSourceCreateWithURL(made as CFURL, nil)
        #expect(made.lastPathComponent == "photo.\(conversion.ext(for: source))", "\(conversion)")
        #expect(image.map { CGImageSourceGetCount($0) } ?? 0 >= 1, "\(conversion)")
        #expect(image.flatMap { CGImageSourceGetType($0) } as String? == conversion.imageType?.identifier, "\(conversion)")
        if conversion != .icns, let image, let cg = CGImageSourceCreateImageAtIndex(image, 0, nil) {
            #expect(cg.width == 120 && cg.height == 80, "\(conversion)")
        }
    }
    // Back from JPEG to PNG too.
    let back = try await Converter.convert(folder.appending(path: "photo.jpg"), to: .png)
    #expect(back.lastPathComponent == "photo 2.png")
}

@Test func convertedFilesNeverOverwrite() throws {
    let folder = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appending(path: "photo.png")
    #expect(Converter.targetName(for: source, .jpeg) == "photo.jpg")
    FileManager.default.createFile(atPath: folder.appending(path: "photo.jpg").path, contents: Data())
    #expect(Converter.targetName(for: source, .jpeg) == "photo 2.jpg")
    #expect(Converter.targetName(for: source, .smaller, smallerWord: "smaller") == "photo (smaller).jpg")
    #expect(Converter.targetName(for: folder.appending(path: "Guide.pdf"), .smaller) == "Guide (smaller).pdf")
}

@Test func convertOffersWhatFitsTheSelection() {
    let png = URL(filePath: "/p/a.png"), jpg = URL(filePath: "/p/b.jpg"), mov = URL(filePath: "/p/c.mov")
    let mp4 = URL(filePath: "/p/d.mp4"), pdf = URL(filePath: "/p/e.pdf"), txt = URL(filePath: "/p/f.txt")
    #expect(!Conversion.choices(for: [png]).contains(.png) && Conversion.choices(for: [png]).contains(.jpeg))
    #expect(Conversion.choices(for: [png, jpg]).contains(.png) && Conversion.choices(for: [png, jpg]).contains(.smaller))
    #expect(Conversion.choices(for: [mov]) == [.mp4, .animatedGIF, .audio])
    #expect(Conversion.choices(for: [mp4]) == [.animatedGIF, .audio])
    #expect(Conversion.choices(for: [png, pdf]) == [.smaller])
    #expect(Conversion.choices(for: [png, mov]).isEmpty && Conversion.choices(for: [txt]).isEmpty)
    // WebP is offered only where ImageIO can write it.
    #expect(Conversion.choices(for: [png]).contains(.webp) == Conversion.webp.isAvailable)
}

@Test func smallerImageFitsInEmailSize() async throws {
    let folder = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let context = CGContext(data: nil, width: 4000, height: 2000, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let big = folder.appending(path: "big.png")
    try Converter.write([context.makeImage()!], type: .png, to: big)
    let made = try await Converter.convert(big, to: .smaller)
    let image = CGImageSourceCreateWithURL(made as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    #expect(made.lastPathComponent == "big (smaller).jpg" && image?.width == 1600 && image?.height == 800)
}

@Test func videoConvertsWithAVFoundation() async throws {
    let folder = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let clip = try await video(in: folder)
    let mp4 = try await Converter.convert(clip, to: .mp4)
    let tracks = try await AVURLAsset(url: mp4).loadTracks(withMediaType: .video)
    #expect(mp4.lastPathComponent == "clip.mp4" && !tracks.isEmpty)
    let gif = try await Converter.convert(clip, to: .animatedGIF)
    let frames = CGImageSourceCreateWithURL(gif as CFURL, nil).map(CGImageSourceGetCount) ?? 0
    #expect(gif.lastPathComponent == "clip.gif" && frames == 20)
    await #expect(throws: Converter.Failure.self) { try await Converter.convert(clip, to: .audio) }
    #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "clip.m4a").path))
}

@Test func stoppedConversionLeavesNothing() async throws {
    let folder = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let clip = try await video(in: folder)
    let cancel = CancelFlag()
    cancel.cancel()
    await #expect(throws: CancellationError.self) { try await Converter.convert(clip, to: .animatedGIF, cancel: cancel) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["clip.mov"])
}
