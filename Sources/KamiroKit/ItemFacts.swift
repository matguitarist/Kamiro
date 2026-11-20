import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

/// What the inspector shows beyond the list's columns (S-025): pictures' dimensions, audio and
/// video length, a PDF's pages, and Finder tags. Facts that don't apply stay nil.
public struct MediaFacts: Equatable, Sendable {
    public var width: Int?
    public var height: Int?
    public var duration: TimeInterval?
    public var pages: Int?

    public init(width: Int? = nil, height: Int? = nil, duration: TimeInterval? = nil, pages: Int? = nil) {
        self.width = width
        self.height = height
        self.duration = duration
        self.pages = pages
    }

    /// "4032 × 3024"
    public var dimensionsText: String? {
        guard let width, let height else { return nil }
        return "\(width) × \(height)"
    }

    /// "3:25", or "1:02:07" past an hour.
    public var durationText: String? {
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        let pattern: Duration.TimeFormatStyle.Pattern = duration >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(duration.rounded()).formatted(.time(pattern: pattern))
    }
}

public enum ItemFacts {
    public static func media(of url: URL) async -> MediaFacts {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        guard let type else { return MediaFacts() }
        if type.conforms(to: .pdf) {
            return MediaFacts(pages: CGPDFDocument(url as CFURL)?.numberOfPages)
        }
        if type.conforms(to: .image) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return MediaFacts() }
            return MediaFacts(width: properties[kCGImagePropertyPixelWidth] as? Int,
                              height: properties[kCGImagePropertyPixelHeight] as? Int)
        }
        if type.conforms(to: .audiovisualContent) {
            let asset = AVURLAsset(url: url)
            var facts = MediaFacts()
            if let duration = try? await asset.load(.duration), duration.isNumeric {
                facts.duration = duration.seconds
            }
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let size = try? await track.load(.naturalSize), size.width > 0 {
                facts.width = Int(size.width.rounded())
                facts.height = Int(size.height.rounded())
            }
            return facts
        }
        return MediaFacts()
    }

    public static func tags(of url: URL) -> [String] {
        (try? url.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
    }
}
