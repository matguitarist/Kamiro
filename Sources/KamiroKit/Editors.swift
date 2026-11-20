import Foundation
import UniformTypeIdentifiers

/// A code editor that Open in Editor can use (Settings › General › Code Editor, S-034).
public struct EditorApp: Hashable, Sendable, Identifiable {
    public var id: String { bundleID }
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    /// The editors Kamiro knows, in the order the first installed one is picked.
    public static let known: [EditorApp] = [
        EditorApp(bundleID: "com.microsoft.VSCode", name: "VS Code"),
        EditorApp(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
        EditorApp(bundleID: "dev.zed.Zed", name: "Zed"),
        EditorApp(bundleID: "com.sublimetext.4", name: "Sublime Text"),
        EditorApp(bundleID: "com.panic.Nova", name: "Nova"),
        EditorApp(bundleID: "com.barebones.bbedit", name: "BBEdit"),
        EditorApp(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
    ]

    public static func installed(_ isInstalled: (String) -> Bool) -> [EditorApp] {
        known.filter { isInstalled($0.bundleID) }
    }

    /// The chosen editor while it's installed, else the first installed one, else none.
    public static func chosen(_ bundleID: String?, installed: [EditorApp]) -> EditorApp? {
        installed.first { $0.bundleID == bundleID } ?? installed.first
    }

    /// Folders and text (source code, JSON, Markdown…) open in an editor; pictures and PDFs don't.
    public static func opens(_ url: URL, isFolder: Bool) -> Bool {
        if isFolder { return true }
        guard !url.pathExtension.isEmpty, let type = UTType(filenameExtension: url.pathExtension) else {
            // No extension: Makefile, LICENSE, dotfiles are text far more often than not.
            return url.pathExtension.isEmpty
        }
        return type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .propertyList)
    }
}
