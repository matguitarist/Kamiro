import AppKit
import KamiroKit

// MARK: - Convert (S-045)

extension Conversion {
    var title: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .heic: "HEIC"
        case .avif: "AVIF"
        case .webp: "WebP"
        case .jpeg2000: "JPEG 2000"
        case .tiff: "TIFF"
        case .gif: "GIF"
        case .bmp: "BMP"
        case .icns: String(localized: "Icon (ICNS)")
        case .ico: String(localized: "Windows Icon (ICO)")
        case .mp4: String(localized: "MP4 Video")
        case .mov: String(localized: "QuickTime Movie")
        case .webm: String(localized: "WebM Video")
        case .animatedGIF: String(localized: "Animated GIF")
        case .audio: String(localized: "Audio Only (M4A)")
        case .m4a: "M4A (AAC)"
        case .mp3: "MP3"
        case .wav: "WAV"
        case .flac: "FLAC"
        case .aiff: "AIFF"
        case .alac: String(localized: "Apple Lossless (ALAC)")
        case .smaller: String(localized: "Smaller for Email")
        }
    }

    /// A video's MP3 is its sound only, and says so beside Audio Only (M4A).
    func title(forVideo: Bool) -> String {
        forVideo && self == .mp3 ? String(localized: "Audio Only (MP3)") : title
    }
}

extension BrowserModel {
    /// What the selection can be converted to: files only, all images, all videos, all sound files, or images and PDFs.
    var convertChoices: [Conversion] {
        let chosen = selectedItems
        guard !chosen.isEmpty, chosen.allSatisfy({ !$0.isFolder && !$0.isPackage }) else { return [] }
        return Conversion.choices(for: chosen.map(\.url), tools: ToolStore.shared.installedIDs)
    }

    /// Each file converts next to itself as its own job in the transfers popover, with Stop and Undo.
    func convertSelection(to conversion: Conversion) {
        let smaller = String(localized: "smaller", comment: "Ends the name of a file made smaller for email: “photo (smaller).jpg”")
        let tools = ToolStore.shared.urls
        for source in orderedSelection where !conversion.isSameFormat(as: source) {
            TransferCenter.shared.startJob(String(localized: "Converting “\(source.lastPathComponent)” to \(conversion.title(forVideo: Media.kind(of: source) == .video))"),
                                           undoName: String(localized: "Convert"),
                                           in: source.deletingLastPathComponent(), browser: self) { cancel, progress in
                try await Converter.convert(source, to: conversion, tools: tools, smallerWord: smaller, cancel: cancel,
                                            progress: progress)
            }
        }
    }

    /// The right-click menu's Convert submenu: formats, then Smaller for Email; a video's sound after its own formats.
    func convertMenuItem() -> NSMenuItem? {
        let choices = convertChoices
        guard !choices.isEmpty else { return nil }
        let videos = selectedItems.allSatisfy { Media.kind(of: $0.url) == .video }
        let menu = NSMenu()
        for choice in choices {
            let startsGroup = choice.group == .email || (videos && choice == .audio)
            if startsGroup, !menu.items.isEmpty { menu.addItem(.separator()) }
            menu.addItem(MenuAction.item(choice.title(forVideo: videos)) { [weak self] in self?.convertSelection(to: choice) })
        }
        let item = NSMenuItem(title: String(localized: "Convert"), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        item.submenu = menu
        return item
    }
}
