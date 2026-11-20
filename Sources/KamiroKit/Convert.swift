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

    public static func type(of url: URL) -> UTType? {
        url.pathExtension.isEmpty ? nil : UTType(filenameExtension: url.pathExtension.lowercased())
    }

    public static func kind(of url: URL) -> Kind? {
        guard let type = type(of: url) else { return nil }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image), readableImages.contains(type.identifier) { return .image }
        if type.conforms(to: .movie) { return .video }
        return nil
    }
}

/// One way to convert files, offered in the right-click menu's Convert submenu.
public enum Conversion: String, CaseIterable, Sendable, Identifiable {
    case jpeg, png, heic, webp, tiff, gif, icns
    case mp4, animatedGIF, audio
    /// Images and PDFs, smaller for email.
    case smaller

    public var id: String { rawValue }

    public enum Group: Sendable { case image, video, email }

    public var group: Group {
        switch self {
        case .mp4, .animatedGIF, .audio: .video
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
        case .webp: .webP
        case .tiff: .tiff
        case .gif: .gif
        case .icns: .icns
        default: nil
        }
    }

    public func ext(for source: URL) -> String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        case .webp: "webp"
        case .tiff: "tiff"
        case .gif, .animatedGIF: "gif"
        case .icns: "icns"
        case .mp4: "mp4"
        case .audio: "m4a"
        case .smaller: Media.kind(of: source) == .pdf ? "pdf" : "jpg"
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
        return self == .mp4 && type == .mpeg4Movie
    }

    /// What can be done to every one of `urls`; formats all of them are already in are left out.
    public static func choices(for urls: [URL]) -> [Conversion] {
        let kinds = urls.map(Media.kind(of:))
        guard !urls.isEmpty, !kinds.contains(nil) else { return [] }
        let offered: [Conversion]
        if kinds.allSatisfy({ $0 == .image }) {
            offered = [.jpeg, .png, .heic, .webp, .tiff, .gif, .icns, .smaller]
        } else if kinds.allSatisfy({ $0 == .video }) {
            offered = [.mp4, .animatedGIF, .audio]
        } else if kinds.allSatisfy({ $0 == .image || $0 == .pdf }) {
            offered = [.smaller]
        } else {
            offered = []
        }
        return offered.filter { choice in choice.isAvailable && !urls.allSatisfy { choice.isSameFormat(as: $0) } }
    }
}

/// Converts on this Mac only, with ImageIO, AVFoundation and PDFKit. The result is made in a
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

    @concurrent
    public static func convert(_ source: URL, to conversion: Conversion, smallerWord: String = "smaller",
                               cancel: CancelFlag = CancelFlag()) async throws -> URL {
        let folder = source.deletingLastPathComponent().canonical
        let staging = try Archive.stagingFolder(near: folder)
        defer { try? FileManager.default.removeItem(at: staging) }
        let out = staging.appending(path: "converted." + conversion.ext(for: source))
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
        if cancel.isCancelled { throw CancellationError() }
        let target = folder.appending(path: targetName(for: source, conversion, smallerWord: smallerWord))
        try FileManager.default.moveItem(at: out, to: target)
        return target.canonical
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
        default: try write([image], type: type, to: out)
        }
    }

    static func smallerImage(_ source: URL, to out: URL) throws {
        let image = try picture(source, maxPixels: emailPixels)
        try write([flattened(image)], type: .jpeg, to: out, properties: [kCGImageDestinationLossyCompressionQuality: 0.7])
    }

    static let iconSizes = [16, 32, 64, 128, 256, 512, 1024]

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
