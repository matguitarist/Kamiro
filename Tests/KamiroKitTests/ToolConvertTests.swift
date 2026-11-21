import AVFoundation
import Foundation
import ImageIO
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import KamiroKit

private func tempFolder() throws -> URL {
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "kamiro-toolconvert-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

/// A shell script standing in for a tool, that writes its arguments to "<name>.args" beside it.
private func fakeTool(_ name: String, in folder: URL, _ body: String) throws -> URL {
    let url = folder.appending(path: name)
    try "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$0.args\"\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

/// Writes "RIFF" to the file after -o, like cwebp.
private let writesOutput = """
while [ $# -gt 0 ]; do if [ "$1" = -o ]; then shift; printf RIFF > "$1"; fi; shift; done
"""

private func picture(_ name: String, in folder: URL, frames: Int = 1, type: UTType = .png) throws -> URL {
    let url = folder.appending(path: name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, frames, nil)!
    for frame in 0..<frames {
        let context = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: Double(frame) / Double(frames), green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    }
    #expect(CGImageDestinationFinalize(destination))
    return url
}

private func lines(_ url: URL) -> [String] {
    ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
}

private let realTools = URL(filePath: "/opt/homebrew/bin")
private func installed(_ command: String) -> URL? {
    let url = realTools.appending(path: command)
    return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
}

// MARK: S-050 WebP with cwebp

@Test func webpIsMadeWithCwebp() async throws {
    let folder = try tempFolder(), tools = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: tools) }
    let cwebp = try fakeTool("cwebp", in: tools, writesOutput)
    let source = try picture("photo.png", in: folder)
    if !Conversion.webp.isAvailable {
        #expect(!Conversion.choices(for: [source]).contains(.webp))
        #expect(Conversion.choices(for: [source], tools: ["cwebp"]).contains(.webp))
        #expect(Conversion.webp.needs(for: source) == [.cwebp])
    }
    let made = try await Converter.convert(source, to: .webp, tools: ["cwebp": cwebp])
    #expect(made.lastPathComponent == "photo.webp")
    let args = lines(tools.appending(path: "cwebp.args"))
    #expect(Array(args.prefix(4)) == ["-quiet", "-q", "90", "-mt"], "\(args)")
    #expect(args.count == 7 && args[4].hasSuffix("/picture.png") && args[5] == "-o" && args[6].hasSuffix("/converted.webp"), "\(args)")
    let again = try await Converter.convert(source, to: .webp, tools: ["cwebp": cwebp])
    #expect(again.lastPathComponent == "photo 2.webp")
}

@Test func anAnimatedGIFGoesThroughGif2webp() async throws {
    let folder = try tempFolder(), tools = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: tools) }
    let cwebp = try fakeTool("cwebp", in: tools, writesOutput)
    _ = try fakeTool("gif2webp", in: tools, writesOutput)
    let still = try picture("still.gif", in: folder, type: .gif)
    let moving = try picture("moving.gif", in: folder, frames: 3, type: .gif)
    _ = try await Converter.convert(moving, to: .webp, tools: ["cwebp": cwebp])
    #expect(lines(tools.appending(path: "gif2webp.args")).dropLast(2).last?.hasSuffix("/moving.gif") == true)
    #expect(!FileManager.default.fileExists(atPath: tools.appending(path: "cwebp.args").path))
    _ = try await Converter.convert(still, to: .webp, tools: ["cwebp": cwebp])
    #expect(FileManager.default.fileExists(atPath: tools.appending(path: "cwebp.args").path))
}

@Test func stopEndsTheToolAndLeavesNothing() async throws {
    let folder = try tempFolder(), tools = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: tools) }
    let cwebp = try fakeTool("cwebp", in: tools, "exec sleep 30")
    let source = try picture("photo.png", in: folder)
    let cancel = CancelFlag()
    let started = Date.now
    Task { try? await Task.sleep(for: .milliseconds(300)); cancel.cancel() }
    await #expect(throws: CancellationError.self) {
        try await Converter.convert(source, to: .webp, tools: ["cwebp": cwebp], cancel: cancel)
    }
    #expect(Date.now.timeIntervalSince(started) < 5)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["photo.png"])
}

@Test func aFailingToolSaysWhy() async throws {
    let folder = try tempFolder(), tools = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: tools) }
    let cwebp = try fakeTool("cwebp", in: tools, "echo 'Error! Could not process file' >&2; exit 255")
    let source = try picture("photo.png", in: folder)
    await #expect(throws: Converter.Failure.failed("cwebp: Error! Could not process file")) {
        try await Converter.convert(source, to: .webp, tools: ["cwebp": cwebp])
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["photo.png"])
}

@Test(.enabled(if: installed("cwebp") != nil)) func realCwebpWritesWebP() async throws {
    let folder = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let made = try await Converter.convert(try picture("photo.png", in: folder), to: .webp, tools: ["cwebp": installed("cwebp")!])
    let image = CGImageSourceCreateWithURL(made as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    #expect(image?.width == 40 && image?.height == 30)
}

// MARK: S-051 Any video with FFmpeg

@Test func ffmpegTimeLinesBecomeAFraction() {
    var reader = FFmpegProgress()
    #expect(reader.read("Input #0, matroska,webm, from 'clip.webm':\n  Duration: 00:01:40.00, start: 0.000000, bitrate: 9 kb/s\n") == nil)
    #expect(reader.duration == 100)
    #expect(reader.read("frame=  10 fps=0.0 q=0.0 size=0kB time=00:00:25.00 bitrate=N/A speed=50x\r") == 0.25)
    // A line cut in two arrives whole.
    #expect(reader.read("frame=  20 fps=0.0 q=0.0 size=0kB ti") == nil)
    #expect(reader.read("me=00:00:50.00 bitrate=N/A\rframe= 30 time=N/A bitrate=N/A\r") == 0.5)
    #expect(reader.read("frame= 99 time=00:02:00.00\r") == 1)
    // A GIF of the first 30 seconds counts toward 30 seconds.
    var gif = FFmpegProgress(limit: 30)
    _ = gif.read("  Duration: 00:10:00.00, start: 0\n")
    #expect(gif.read("time=00:00:15.00 \r") == 0.5)
    #expect(FFmpegProgress.seconds("01:02:03.5") == 3723.5 && FFmpegProgress.seconds("N/A") == nil)
}

@Test func videosMacOSCantOpenTakeFFmpeg() {
    let webm = URL(filePath: "/v/a.webm"), mkv = URL(filePath: "/v/b.mkv"), avi = URL(filePath: "/v/c.avi"), flv = URL(filePath: "/v/d.flv")
    let mov = URL(filePath: "/v/e.mov")
    for url in [webm, mkv, avi, flv] {
        #expect(Media.kind(of: url) == .video && !Media.isNative(url), "\(url.lastPathComponent)")
        #expect(Conversion.choices(for: [url]).isEmpty, "\(url.lastPathComponent)")
    }
    #expect(Conversion.choices(for: [webm], tools: ["ffmpeg"]) == [.mp4, .mov, .animatedGIF, .audio, .mp3])
    #expect(Conversion.choices(for: [mkv], tools: ["ffmpeg"]) == [.mp4, .mov, .webm, .animatedGIF, .audio, .mp3])
    #expect(Conversion.choices(for: [mov]) == [.mp4, .animatedGIF, .audio])
    #expect(Conversion.choices(for: [mov], tools: ["ffmpeg"]) == [.mp4, .webm, .animatedGIF, .audio, .mp3])
    #expect(Conversion.mp4.needs(for: mov) == [] && Conversion.webm.needs(for: mov) == [.ffmpeg])
}

@Test func ffmpegArguments() {
    let input = URL(filePath: "/v/in.mkv"), output = URL(filePath: "/s/converted.gif")
    let gif = ToolConvert.ffmpegArguments(.animatedGIF, input, output)
    #expect(Array(gif.prefix(5)) == ["-nostdin", "-hide_banner", "-y", "-i", "/v/in.mkv"] && gif.last == "/s/converted.gif")
    #expect(gif.contains("-t") && gif.contains { $0.contains("palettegen") && $0.contains("fps=10") && $0.contains("480") })
    #expect(ToolConvert.ffmpegArguments(.webm, input, output).contains("libvpx-vp9"))
    #expect(ToolConvert.ffmpegArguments(.mp4, input, output).contains("libx264"))
    #expect(ToolConvert.ffmpegArguments(.audio, input, output).contains("-vn"))
    // A video's MP3 is its sound only; a song's keeps its tags and cover.
    let fromVideo = ToolConvert.ffmpegArguments(.mp3, input, output)
    #expect(fromVideo.contains("libmp3lame") && fromVideo.contains("-vn") && !fromVideo.contains("attached_pic"))
    let song = ToolConvert.ffmpegArguments(.flac, URL(filePath: "/a/song.ogg"), URL(filePath: "/s/converted.flac"))
    #expect(song.contains("-map_metadata") && song.contains("attached_pic") && song.contains("flac"))
    #expect(ToolConvert.ffmpegArguments(.wav, URL(filePath: "/a/song.ogg"), output).contains("pcm_s16le"))
}

// MARK: S-061 Sound files

@Test func soundFilesMacOSCantOpenTakeFFmpeg() {
    let wma = URL(filePath: "/a/song.wma"), ape = URL(filePath: "/a/song.ape"), wav = URL(filePath: "/a/song.wav")
    #expect(Media.kind(of: wma) == .audio && !Media.isNative(wma) && Media.kind(of: ape) == .audio)
    #expect(Conversion.choices(for: [wma]).isEmpty)
    #expect(Conversion.choices(for: [wma], tools: ["ffmpeg"]) == [.m4a, .mp3, .wav, .flac, .aiff, .alac])
    #expect(Media.isNative(wav) && Conversion.choices(for: [wav]) == [.m4a, .flac, .aiff, .alac])
    #expect(Conversion.choices(for: [wav], tools: ["ffmpeg"]) == [.m4a, .mp3, .flac, .aiff, .alac])
    #expect(Conversion.mp3.needs(for: wav) == [.ffmpeg] && Conversion.flac.needs(for: wav) == [])
}

@Test(.enabled(if: installed("ffmpeg") != nil)) func realFFmpegMakesMP3AndKeepsTags() async throws {
    let folder = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let ffmpeg = installed("ffmpeg")!
    let song = folder.appending(path: "song.flac")
    try await ToolRun.run(ffmpeg, ["-nostdin", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=2",
                                   "-metadata", "title=Kamiro Tone", "-c:a", "flac", song.path], cancel: CancelFlag())
    let seen = Mutex<[Double]>([])
    let mp3 = try await Converter.convert(song, to: .mp3, tools: ["ffmpeg": ffmpeg]) { fraction in seen.withLock { $0.append(fraction) } }
    #expect(mp3.lastPathComponent == "song.mp3" && seen.withLock { $0.last ?? 0 } >= 0.85)
    for made in [mp3, try await Converter.convert(song, to: .alac, tools: ["ffmpeg": ffmpeg])] {
        let titles = try await AVURLAsset(url: made).load(.commonMetadata).filter { $0.commonKey == .commonKeyTitle }
        let title = try await titles.first?.load(.stringValue)
        #expect(title == "Kamiro Tone", "\(made.lastPathComponent)")
    }
    #expect(Media.audioCodec(of: folder.appending(path: "song.m4a")) == kAudioFormatAppleLossless)
}

@Test(.enabled(if: installed("ffmpeg") != nil)) func realFFmpegConvertsAWebM() async throws {
    let folder = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let ffmpeg = installed("ffmpeg")!
    let clip = folder.appending(path: "clip.webm")
    try await ToolRun.run(ffmpeg, ["-nostdin", "-y", "-f", "lavfi", "-i", "testsrc=duration=2:size=64x48:rate=10",
                                   "-c:v", "libvpx-vp9", clip.path], cancel: CancelFlag())
    let seen = Mutex<[Double]>([])
    let mp4 = try await Converter.convert(clip, to: .mp4, tools: ["ffmpeg": ffmpeg]) { fraction in seen.withLock { $0.append(fraction) } }
    let tracks = try await AVURLAsset(url: mp4).loadTracks(withMediaType: .video)
    #expect(mp4.lastPathComponent == "clip.mp4" && !tracks.isEmpty)
    #expect(seen.withLock { $0.last ?? 0 } >= 0.85)
    let gif = try await Converter.convert(clip, to: .animatedGIF, tools: ["ffmpeg": ffmpeg])
    #expect(CGImageSourceCreateWithURL(gif as CFURL, nil).map(CGImageSourceGetCount) ?? 0 >= 15)
    await #expect(throws: Converter.Failure.failed("“clip.webm” has no sound.")) {
        try await Converter.convert(clip, to: .audio, tools: ["ffmpeg": ffmpeg])
    }
    #expect(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)) == ["clip.webm", "clip.mp4", "clip.gif"])
}

// MARK: S-052 More pictures with ImageMagick

@Test func picturesMacOSCantReadTakeImageMagick() {
    let svg = URL(filePath: "/p/logo.svg"), xcf = URL(filePath: "/p/art.xcf"), png = URL(filePath: "/p/a.png")
    #expect(Media.kind(of: svg) == .image && !Media.isNative(svg) && Media.kind(of: xcf) == .image)
    #expect(Conversion.choices(for: [svg]).isEmpty)
    let choices = Conversion.choices(for: [svg], tools: ["magick"])
    #expect(choices.contains(.png) && choices.contains(.jpeg) && choices.contains(.smaller))
    #expect(Conversion.png.needs(for: svg) == [.imageMagick])
    // What ImageIO reads stays native, ImageMagick or not.
    #expect(Conversion.jpeg.needs(for: png) == [] && Media.isNative(png))
    #expect(ToolConvert.magickArguments(URL(filePath: "/s/source.svg"), URL(filePath: "/s/source.png"))
        == ["-background", "none", "/s/source.svg[0]", "PNG32:/s/source.png"])
    #expect(ToolConvert.magickArguments(URL(filePath: "/s/source.xcf"), URL(filePath: "/s/source.png"))
        == ["-background", "none", "/s/source.xcf", "-layers", "merge", "PNG32:/s/source.png"])
}

@Test(.enabled(if: installed("magick") != nil)) func anSVGBecomesAPNGOfItsOwnSize() async throws {
    let folder = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let svg = folder.appending(path: "logo [draft].svg")
    try """
    <svg xmlns="http://www.w3.org/2000/svg" width="120" height="70"><rect x="10" y="10" width="50" height="50" fill="#36c"/></svg>
    """.write(to: svg, atomically: true, encoding: .utf8)
    let made = try await Converter.convert(svg, to: .png, tools: ["magick": installed("magick")!])
    let image = CGImageSourceCreateWithURL(made as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    #expect(made.lastPathComponent == "logo [draft].png" && image?.width == 120 && image?.height == 70)
}
