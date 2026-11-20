import AVFoundation
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// What a file is, for Convert (S-045).
public enum Media {
    public enum Kind: Sendable, Equatable { case image, video, pdf }

    private static let readableImages = Set((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? [])
    static let writableImages = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
    /// Movies AVFoundation opens. AVI is left to FFmpeg: the codecs inside are rarely ones macOS plays.
    private static let nativeVideos = Set(AVURLAsset.audiovisualTypes().map(\.rawValue)).subtracting(["public.avi"])
    /// Pictures macOS can't read that ImageMagick can (S-052).
    static let magickExtensions: Set<String> = ["svg", "svgz", "xcf", "eps", "epsf", "ai", "pcx", "xpm", "xbm", "sgi",
                                                "ras", "sun", "mng", "miff", "dpx"]

    public static func type(of url: URL) -> UTType? {
        url.pathExtension.isEmpty ? nil : UTType(filenameExtension: url.pathExtension.lowercased())
    }

    public static func kind(of url: URL) -> Kind? {
        guard let type = type(of: url) else { return nil }
        if type.conforms(to: .image), readableImages.contains(type.identifier) { return .image }
        if magickExtensions.contains(url.pathExtension.lowercased()) { return .image }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .movie) { return .video }
        return nil
    }

    /// macOS reads it itself; otherwise it takes ImageMagick or FFmpeg (S-051, S-052).
    public static func isNative(_ url: URL) -> Bool {
        guard let type = type(of: url), let kind = kind(of: url) else { return false }
        return switch kind {
        case .pdf: true
        case .image: readableImages.contains(type.identifier)
        case .video: nativeVideos.contains(type.identifier)
        }
    }
}

/// One way to convert files, offered in the right-click menu's Convert submenu (S-045, S-048, S-050 to S-052).
public enum Conversion: String, CaseIterable, Sendable, Identifiable {
    case jpeg, png, heic, avif, webp, jpeg2000, tiff, gif, bmp, icns, ico
    case mp4, webm, animatedGIF, audio
    /// Images and PDFs, smaller for email.
    case smaller

    public var id: String { rawValue }

    public enum Group: Sendable { case image, video, email }

    public var group: Group {
        switch self {
        case .mp4, .webm, .animatedGIF, .audio: .video
        case .smaller: .email
        default: .image
        }
    }

    /// The type ImageIO writes for an image conversion.
    public var imageType: UTType? {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        case .avif: UTType("public.avif")
        case .webp: .webP
        case .jpeg2000: UTType("public.jpeg-2000")
        case .tiff: .tiff
        case .gif: .gif
        case .bmp: .bmp
        case .icns: .icns
        case .ico: .ico
        default: nil
        }
    }

    public func ext(for source: URL) -> String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        case .avif: "avif"
        case .webp: "webp"
        case .jpeg2000: "jp2"
        case .tiff: "tiff"
        case .bmp: "bmp"
        case .ico: "ico"
        case .gif, .animatedGIF: "gif"
        case .icns: "icns"
        case .mp4: "mp4"
        case .webm: "webm"
        case .audio: "m4a"
        case .smaller: Media.kind(of: source) == .pdf ? "pdf" : "jpg"
        }
    }

    /// The optional tools converting `source` this way takes (S-049), none when macOS does it all;
    /// nil when it can't be done here at all. What macOS reads stays native even with a tool there.
    public func needs(for source: URL) -> [CommandTool]? {
        guard let kind = Media.kind(of: source) else { return nil }
        let native = Media.isNative(source)
        switch group {
        case .image:
            guard kind == .image else { return nil }
            let reading: [CommandTool] = native ? [] : [.imageMagick]
            if isAvailable { return reading }
            return self == .webp ? reading + [.cwebp] : nil
        case .email:
            if kind == .pdf { return [] }
            return kind == .image ? (native ? [] : [.imageMagick]) : nil
        case .video:
            guard kind == .video else { return nil }
            return native && self != .webm ? [] : [.ffmpeg]
        }
    }

    /// Image formats only when ImageIO on this Mac can write them (macOS 26 reads WebP but can't write it).
    public var isAvailable: Bool {
        guard let type = imageType else { return true }
        return Media.writableImages.contains(type.identifier)
    }

    /// The source is already in this format, so there is nothing to convert.
    public func isSameFormat(as source: URL) -> Bool {
        guard let type = Media.type(of: source) else { return false }
        if let imageType { return type == imageType }
        if self == .webm { return type.identifier == "org.webmproject.webm" }
        return self == .mp4 && type == .mpeg4Movie
    }

    /// What can be done to every one of `urls`; formats all of them are already in are left out,
    /// and so is what needs a tool that isn't in `tools` (installed tools by id).
    public static func choices(for urls: [URL], tools: Set<String> = []) -> [Conversion] {
        let kinds = urls.map(Media.kind(of:))
        guard !urls.isEmpty, !kinds.contains(nil) else { return [] }
        let offered: [Conversion]
        if kinds.allSatisfy({ $0 == .image }) {
            offered = [.jpeg, .png, .heic, .avif, .webp, .jpeg2000, .tiff, .gif, .bmp, .icns, .ico, .smaller]
        } else if kinds.allSatisfy({ $0 == .video }) {
            offered = [.mp4, .webm, .animatedGIF, .audio]
        } else if kinds.allSatisfy({ $0 == .image || $0 == .pdf }) {
            offered = [.smaller]
        } else {
            offered = []
        }
        return offered.filter { choice in
            urls.allSatisfy { source in choice.needs(for: source).map { $0.allSatisfy { tools.contains($0.id) } } ?? false }
                && !urls.allSatisfy { choice.isSameFormat(as: $0) }
        }
    }
}

/// Converts on this Mac only, with ImageIO, AVFoundation and PDFKit, and the optional tools
/// that are installed (cwebp, FFmpeg, ImageMagick; never downloaded). The result is made in a
/// staging folder on the same disk and moved next to the original under a free name at the end,
/// so a stopped or failed conversion leaves nothing and nothing is overwritten.
public enum Converter {
    public enum Failure: Error, Equatable, LocalizedError {
        case unreadable(String)
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let name): "Couldn't read “\(name)”."
            case .failed(let message): message
            }
        }
    }

    /// The longest side of a picture made smaller for email, and of an animated GIF's frames.
    public static let emailPixels = 1600
    static let gifPixels = 480
    static let gifFrameRate = 10.0
    static let gifSeconds = 30.0

    /// "photo.jpg", or "photo 2.jpg" when taken; "photo (smaller).jpg" for email.
    public static func targetName(for source: URL, _ conversion: Conversion, smallerWord: String = "smaller") -> String {
        let stem = source.deletingPathExtension().lastPathComponent
        let base = conversion == .smaller ? "\(stem) (\(smallerWord))" : stem
        return Naming.free(base + "." + conversion.ext(for: source), in: source.deletingLastPathComponent())
    }

    /// `tools` are the installed tools' programs by id. `progress` hears the fraction done, when
    /// the way it converts tells (FFmpeg does).
    @concurrent
    public static func convert(_ source: URL, to conversion: Conversion, tools: [String: URL] = [:],
                               smallerWord: String = "smaller", cancel: CancelFlag = CancelFlag(),
                               progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        guard let needs = conversion.needs(for: source) else {
            throw Failure.failed("Can't convert “\(source.lastPathComponent)” to \(conversion.ext(for: source)).")
        }
        if let missing = needs.first(where: { tools[$0.id] == nil }) {
            throw Failure.failed("Converting “\(source.lastPathComponent)” takes \(missing.name).")
        }
        let folder = source.deletingLastPathComponent().canonical
        let staging = try Archive.stagingFolder(near: folder)
        defer { try? FileManager.default.removeItem(at: staging) }
        let out = staging.appending(path: "converted." + conversion.ext(for: source))
        var input = source
        if needs.contains(.imageMagick), let magick = tools[CommandTool.imageMagick.id] {
            input = try await ToolConvert.magick(source, tool: magick, staging: staging, cancel: cancel)
        }
        if conversion.group == .video, let ffmpeg = tools[CommandTool.ffmpeg.id],
           needs.contains(.ffmpeg) || conversion == .animatedGIF {
            // FFmpeg's palette makes better GIFs than a frame-by-frame copy, so it wins when it's there.
            try await ToolConvert.ffmpeg(input, conversion, tool: ffmpeg, to: out, cancel: cancel, progress: progress)
        } else if conversion == .webp, let cwebp = tools[CommandTool.cwebp.id],
                  needs.contains(.cwebp) || ToolConvert.isAnimatedGIF(input) {
            try await ToolConvert.webp(input, cwebp: cwebp, to: out, staging: staging, cancel: cancel)
        } else {
            try await natively(input, to: conversion, out: out, cancel: cancel)
        }
        if cancel.isCancelled { throw CancellationError() }
        let target = folder.appending(path: targetName(for: source, conversion, smallerWord: smallerWord))
        try FileManager.default.moveItem(at: out, to: target)
        return target.canonical
    }

    static func natively(_ source: URL, to conversion: Conversion, out: URL, cancel: CancelFlag) async throws {
        switch conversion {
        case .mp4: try await export(source, preset: AVAssetExportPresetHighestQuality, as: .mp4, to: out, cancel: cancel)
        case .audio:
            if try await AVURLAsset(url: source).loadTracks(withMediaType: .audio).isEmpty {
                throw Failure.failed("“\(source.lastPathComponent)” has no sound.")
            }
            try await export(source, preset: AVAssetExportPresetAppleM4A, as: .m4a, to: out, cancel: cancel)
        case .animatedGIF: try await gif(fromVideo: source, to: out, cancel: cancel)
        case .smaller:
            if Media.kind(of: source) == .pdf { try smallerPDF(source, to: out) } else { try smallerImage(source, to: out) }
        default:
            guard let type = conversion.imageType else { throw Failure.failed("Can't convert to \(conversion.rawValue).") }
            try image(source, to: type, out: out)
        }
    }

    // MARK: Images

    /// The first picture, turned the way it's shown, no bigger than `maxPixels` on its longest side.
    static func picture(_ source: URL, maxPixels: Int? = nil) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil) else { throw Failure.unreadable(source.lastPathComponent) }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let longest = max(props?[kCGImagePropertyPixelWidth] as? Int ?? 0, props?[kCGImagePropertyPixelHeight] as? Int ?? 0)
        if longest > 0 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: min(maxPixels ?? longest, longest),
            ]
            if let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) { return image }
        }
        guard let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw Failure.unreadable(source.lastPathComponent) }
        return image
    }

    static func image(_ source: URL, to type: UTType, out: URL) throws {
        let image = try picture(source)
        switch type {
        case .jpeg: try write([flattened(image)], type: type, to: out, properties: [kCGImageDestinationLossyCompressionQuality: 0.9])
        case .icns: try write(iconSizes.map { square(image, side: $0) }, type: type, to: out)
        case .ico: try write(windowsIconSizes.map { square(image, side: $0) }, type: type, to: out)
        default: try write([image], type: type, to: out)
        }
    }

    static func smallerImage(_ source: URL, to out: URL) throws {
        let image = try picture(source, maxPixels: emailPixels)
        try write([flattened(image)], type: .jpeg, to: out, properties: [kCGImageDestinationLossyCompressionQuality: 0.7])
    }

    static let iconSizes = [16, 32, 64, 128, 256, 512, 1024]
    /// A Windows icon stops at 256 pixels.
    static let windowsIconSizes = [16, 32, 48, 64, 128, 256]

    static func write(_ images: [CGImage], type: UTType, to out: URL, properties: [CFString: Any] = [:]) throws {
        guard let destination = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, images.count, nil) else {
            throw Failure.failed("This Mac can't write \(type.preferredFilenameExtension ?? type.identifier) files.")
        }
        for image in images { CGImageDestinationAddImage(destination, image, properties as CFDictionary) }
        guard CGImageDestinationFinalize(destination) else { throw Failure.failed("Couldn't write the converted file.") }
    }

    /// JPEG has no transparency: transparent parts become white, not black.
    static func flattened(_ image: CGImage) -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image
        default: break
        }
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }

    /// The picture fitted in a transparent square, for an icon.
    static func square(_ image: CGImage, side: Int) -> CGImage {
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        let scale = Double(side) / Double(max(image.width, image.height))
        let width = Double(image.width) * scale, height = Double(image.height) * scale
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (Double(side) - width) / 2, y: (Double(side) - height) / 2, width: width, height: height))
        return context.makeImage() ?? image
    }

    // MARK: PDF

    static func smallerPDF(_ source: URL, to out: URL) throws {
        guard let document = PDFDocument(url: source) else { throw Failure.unreadable(source.lastPathComponent) }
        guard document.write(to: out, withOptions: [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true]) else {
            throw Failure.failed("Couldn't write the smaller PDF.")
        }
    }

    // MARK: Video

    static func export(_ source: URL, preset: String, as type: AVFileType, to out: URL, cancel: CancelFlag) async throws {
        let asset = AVURLAsset(url: source)
        guard try await asset.load(.isExportable),
              let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw Failure.unreadable(source.lastPathComponent)
        }
        let job = Task { [session] in try await session.export(to: out, as: type) }
        let watcher = Task {
            while !Task.isCancelled {
                if cancel.isCancelled { job.cancel(); return }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        defer { watcher.cancel() }
        do {
            try await job.value
        } catch {
            if cancel.isCancelled { throw CancellationError() }
            throw Failure.failed(error.localizedDescription)
        }
    }

    /// The first 30 seconds at 10 frames a second, 480 pixels at most, looping.
    static func gif(fromVideo source: URL, to out: URL, cancel: CancelFlag) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw Failure.unreadable(source.lastPathComponent) }
        let count = max(1, Int(min(duration, gifSeconds) * gifFrameRate))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: gifPixels, height: gifPixels)
        let tolerance = CMTime(seconds: 0.5 / gifFrameRate, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        guard let destination = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw Failure.failed("Couldn't write the GIF.")
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / gifFrameRate]] as CFDictionary
        let times = (0..<count).map { CMTime(seconds: Double($0) / gifFrameRate, preferredTimescale: 600) }
        var last: CGImage?
        var added = 0
        for await result in generator.images(for: times) {
            if cancel.isCancelled { throw CancellationError() }
            // A frame that can't be read repeats the one before, so the timing stays right.
            if let image = (try? result.image) ?? last {
                CGImageDestinationAddImage(destination, image, frame)
                last = image
                added += 1
            }
        }
        guard added == count, CGImageDestinationFinalize(destination) else { throw Failure.failed("Couldn't read the video's frames.") }
    }
}
