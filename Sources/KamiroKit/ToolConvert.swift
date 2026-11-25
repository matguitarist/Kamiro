import Foundation
import ImageIO
import ProcessKit
import Synchronization
import UniformTypeIdentifiers

/// Runs an optional tool (S-049) for a conversion: its output streams to `output` as it
/// comes, Stop ends it, and a failure reports the tool's last words.
public enum ToolRun {
    /// `output` gets each line with its ending, stdout and stderr together.
    @concurrent
    public static func run(_ url: URL, _ arguments: [String], cancel: CancelFlag,
                           output: @escaping @Sendable (String) -> Void = { _ in }) async throws {
        let name = url.lastPathComponent
        let result: Shell.Output
        do {
            result = try await Shell.run(url.path, arguments, options: Shell.Options(
                stderr: .merged, cancel: cancel, onLine: { output($0 + "\n") }))
        } catch is ShellError {
            throw Converter.Failure.failed("Couldn't start \(name).")
        }
        guard result.succeeded else {
            let last = result.lines.last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            throw Converter.Failure.failed("\(name): \(last ?? "failed (\(result.status)).")")
        }
    }
}

/// How far FFmpeg has got, from the "Duration:" it prints first and the "time=" of each
/// progress line (S-051). `limit` caps the length, for a GIF of the first 30 seconds.
public struct FFmpegProgress: Sendable {
    public private(set) var duration: Double?
    public let limit: Double?
    private var pending = ""

    public init(limit: Double? = nil) { self.limit = limit }

    /// The length the "time=" values count toward.
    public var total: Double? {
        guard let duration else { return limit }
        return limit.map { min($0, duration) } ?? duration
    }

    /// Reads the next piece of FFmpeg's output; the latest fraction done, when it has one.
    public mutating func read(_ text: String) -> Double? {
        pending += text
        // Progress lines end with a carriage return, the rest with a newline.
        var lines = pending.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        pending = String(lines.removeLast())
        var latest: Double?
        for line in lines {
            if duration == nil, let found = line.range(of: "Duration: ") {
                duration = Self.seconds(line[found.upperBound...].prefix { $0 != "," })
            }
            if let found = line.range(of: "time="), let time = Self.seconds(line[found.upperBound...].prefix { $0 != " " }),
               let total, total > 0 {
                latest = min(1, max(0, time / total))
            }
        }
        return latest
    }

    /// "01:02:03.45" in seconds; nil for "N/A".
    static func seconds(_ text: Substring) -> Double? {
        let parts = text.split(separator: ":")
        guard parts.count == 3, let hours = Double(parts[0]), let minutes = Double(parts[1]), let seconds = Double(parts[2]),
              hours >= 0 else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
}

/// The conversions done with cwebp (S-050), FFmpeg (S-051) and ImageMagick (S-052).
enum ToolConvert {
    // MARK: ImageMagick

    /// A picture macOS can't read, drawn at its own size as a PNG that ImageIO takes from there.
    static func magick(_ source: URL, tool: URL, staging: URL, cancel: CancelFlag) async throws -> URL {
        // A copy with a plain name: ImageMagick reads brackets and colons in names as options.
        let copy = staging.appending(path: "source." + source.pathExtension.lowercased())
        try FileManager.default.copyItem(at: source, to: copy)
        let png = staging.appending(path: "source.png")
        try await ToolRun.run(tool, magickArguments(copy, png), cancel: cancel)
        return png
    }

    /// The first page, on a transparent background; a GIMP file's layers merged into one picture.
    static func magickArguments(_ input: URL, _ output: URL) -> [String] {
        let layered = input.pathExtension == "xcf"
        return ["-background", "none", input.path + (layered ? "" : "[0]")]
            + (layered ? ["-layers", "merge"] : []) + ["PNG32:" + output.path]
    }

    // MARK: cwebp

    /// An animated GIF becomes an animated WebP with gif2webp (installed with cwebp); any other
    /// picture is drawn the way it's shown and handed to cwebp.
    static func webp(_ input: URL, cwebp: URL, to out: URL, staging: URL, cancel: CancelFlag) async throws {
        let gif2webp = cwebp.deletingLastPathComponent().appending(path: "gif2webp")
        if isAnimatedGIF(input), FileManager.default.isExecutableFile(atPath: gif2webp.path) {
            try await ToolRun.run(gif2webp, webpArguments(input, out), cancel: cancel)
            return
        }
        let png = staging.appending(path: "picture.png")
        try Converter.write([Converter.picture(input)], type: .png, to: png)
        try await ToolRun.run(cwebp, webpArguments(png, out), cancel: cancel)
    }

    static func webpArguments(_ input: URL, _ output: URL) -> [String] {
        ["-quiet", "-q", "90", "-mt", input.path, "-o", output.path]
    }

    static func isAnimatedGIF(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(source) as String? == UTType.gif.identifier else { return false }
        return CGImageSourceGetCount(source) > 1
    }

    // MARK: FFmpeg

    static func ffmpeg(_ input: URL, _ conversion: Conversion, tool: URL, to out: URL, cancel: CancelFlag,
                       progress: @escaping @Sendable (Double) -> Void) async throws {
        let reader = Mutex(FFmpegProgress(limit: conversion == .animatedGIF ? Converter.gifSeconds : nil))
        let heard = Mutex("")
        do {
            try await ToolRun.run(tool, ffmpegArguments(conversion, input, out), cancel: cancel) { text in
                if let fraction = reader.withLock({ $0.read(text) }) { progress(fraction) }
                heard.withLock { $0 = String(($0 + text).suffix(8000)) }
            }
        } catch Converter.Failure.failed where [.audio, .mp3].contains(conversion) && heard.withLock({ $0.contains("matches no streams") }) {
            throw Converter.Failure.failed("“\(input.lastPathComponent)” has no sound.")
        }
    }

    static func ffmpegArguments(_ conversion: Conversion, _ input: URL, _ output: URL) -> [String] {
        let start = ["-nostdin", "-hide_banner", "-y", "-i", input.path]
        // A song keeps its tags, and its cover where the format holds one; a video gives only its sound.
        let song = Media.kind(of: input) == .audio
        let tags = ["-map", "0:a:0", "-map_metadata", "0"]
        let cover = song ? ["-map", "0:v:0?", "-c:v", "copy", "-disposition:v:0", "attached_pic"] : ["-vn"]
        let depth = song ? Media.bitDepth(of: input) : 16
        let middle: [String] = switch conversion {
        case .m4a: tags + cover + ["-c:a", "aac", "-b:a", "256k"]
        case .alac: tags + cover + ["-c:a", "alac"]
        case .flac: tags + cover + ["-c:a", "flac"]
        case .mp3: tags + cover + ["-c:a", "libmp3lame", "-q:a", "2", "-id3v2_version", "3"]
        case .wav: tags + ["-vn", "-c:a", depth > 16 ? "pcm_s24le" : "pcm_s16le"]
        case .aiff: tags + ["-vn", "-c:a", depth > 16 ? "pcm_s24be" : "pcm_s16be"]
        case .webm:
            ["-map", "0:v:0", "-map", "0:a:0?", "-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-row-mt", "1",
             "-deadline", "good", "-cpu-used", "4", "-c:a", "libopus", "-b:a", "128k"]
        case .audio:
            ["-map", "0:a:0", "-vn", "-c:a", "aac", "-b:a", "192k"]
        case .animatedGIF:
            // One palette made from the video itself: far better colors than a fixed one.
            ["-t", "\(Int(Converter.gifSeconds))", "-filter_complex",
             "fps=\(Int(Converter.gifFrameRate)),scale=\(Converter.gifPixels):\(Converter.gifPixels):force_original_aspect_ratio=decrease:flags=lanczos,"
                + "split[a][b];[a]palettegen[p];[b][p]paletteuse",
             "-loop", "0"]
        default:
            // H.264 wants even sides.
            ["-map", "0:v:0", "-map", "0:a:0?", "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", "-c:v", "libx264",
             "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart"]
        }
        return start + middle + [output.path]
    }
}
