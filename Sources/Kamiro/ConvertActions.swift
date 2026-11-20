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
        case .animatedGIF: String(localized: "Animated GIF")
        case .audio: String(localized: "Audio Only (M4A)")
        case .smaller: String(localized: "Smaller for Email")
        }
    }
}

extension BrowserModel {
    /// What the selection can be converted to: files only, all images, all videos, or images and PDFs.
    var convertChoices: [Conversion] {
        let chosen = selectedItems
        guard !chosen.isEmpty, chosen.allSatisfy({ !$0.isFolder && !$0.isPackage }) else { return [] }
        return Conversion.choices(for: chosen.map(\.url), tools: ToolStore.shared.installedIDs)
    }

    /// Each file converts next to itself as its own job in the transfers popover, with Stop and Undo.
    func convertSelection(to conversion: Conversion) {
        let smaller = String(localized: "smaller", comment: "Ends the name of a file made smaller for email: “photo (smaller).jpg”")
        for source in orderedSelection where !conversion.isSameFormat(as: source) {
            TransferCenter.shared.startJob(String(localized: "Converting “\(source.lastPathComponent)” to \(conversion.title)"),
                                           undoName: String(localized: "Convert"),
                                           in: source.deletingLastPathComponent(), browser: self) { cancel in
                try await Converter.convert(source, to: conversion, smallerWord: smaller, cancel: cancel)
            }
        }
    }

    /// The right-click menu's Convert submenu: formats, then Smaller for Email.
    func convertMenuItem() -> NSMenuItem? {
        let choices = convertChoices
        guard !choices.isEmpty else { return nil }
        let menu = NSMenu()
        for choice in choices {
            if choice.group == .email, !menu.items.isEmpty { menu.addItem(.separator()) }
            menu.addItem(MenuAction.item(choice.title) { [weak self] in self?.convertSelection(to: choice) })
        }
        let item = NSMenuItem(title: String(localized: "Convert"), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        item.submenu = menu
        return item
    }
}
