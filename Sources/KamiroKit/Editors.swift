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
        // VS Code and its forks.
        EditorApp(bundleID: "com.microsoft.VSCode", name: "VS Code"),
        EditorApp(bundleID: "com.microsoft.VSCodeInsiders", name: "VS Code Insiders"),
        EditorApp(bundleID: "com.vscodium", name: "VSCodium"),
        EditorApp(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
        EditorApp(bundleID: "com.exafunction.windsurf", name: "Windsurf"),
        // Other editors.
        EditorApp(bundleID: "dev.zed.Zed", name: "Zed"),
        EditorApp(bundleID: "dev.zed.Zed-Preview", name: "Zed Preview"),
        EditorApp(bundleID: "com.sublimetext.4", name: "Sublime Text"),
        EditorApp(bundleID: "com.sublimetext.3", name: "Sublime Text 3"),
        EditorApp(bundleID: "com.panic.Nova", name: "Nova"),
        EditorApp(bundleID: "com.barebones.bbedit", name: "BBEdit"),
        EditorApp(bundleID: "com.macromates.TextMate", name: "TextMate"),
        EditorApp(bundleID: "com.coteditor.CotEditor", name: "CotEditor"),
        EditorApp(bundleID: "org.vim.MacVim", name: "MacVim"),
        EditorApp(bundleID: "org.gnu.Emacs", name: "Emacs"),
        // IDEs: a folder opens as a project.
        EditorApp(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
        EditorApp(bundleID: "com.jetbrains.intellij", name: "IntelliJ IDEA"),
        EditorApp(bundleID: "com.jetbrains.intellij.ce", name: "IntelliJ IDEA CE"),
        EditorApp(bundleID: "com.jetbrains.pycharm", name: "PyCharm"),
        EditorApp(bundleID: "com.jetbrains.pycharm.ce", name: "PyCharm CE"),
        EditorApp(bundleID: "com.jetbrains.WebStorm", name: "WebStorm"),
        EditorApp(bundleID: "com.jetbrains.goland", name: "GoLand"),
        EditorApp(bundleID: "com.jetbrains.rustrover", name: "RustRover"),
        EditorApp(bundleID: "com.jetbrains.CLion", name: "CLion"),
        EditorApp(bundleID: "com.jetbrains.PhpStorm", name: "PhpStorm"),
        EditorApp(bundleID: "com.jetbrains.rider", name: "Rider"),
        EditorApp(bundleID: "com.google.android.studio", name: "Android Studio"),
    ]

    public static func installed(_ isInstalled: (String) -> Bool) -> [EditorApp] {
        known.filter { isInstalled($0.bundleID) }
    }

    /// The chosen editor while it's installed, else the first installed one, else none.
    public static func chosen(_ bundleID: String?, installed: [EditorApp]) -> EditorApp? {
        installed.first { $0.bundleID == bundleID } ?? installed.first
    }

    /// Project files keep opening in the app that owns them (Xcode, Godot, Unity, Rider, Unreal…),
    /// even when they are text underneath.
    public static let projectExtensions: Set<String> = [
        "xcodeproj", "xcworkspace", "playground", "swiftpm",
        "godot", "tscn", "tres",
        "unity", "unitypackage", "prefab", "asset",
        "sln", "csproj", "fsproj", "vbproj",
        "uproject", "uplugin",
    ]

    /// Folders and text (source code, JSON, Markdown…) open in an editor; pictures, PDFs and
    /// project files don't.
    public static func opens(_ url: URL, isFolder: Bool) -> Bool {
        if isFolder { return true }
        if projectExtensions.contains(url.pathExtension.lowercased()) { return false }
        guard !url.pathExtension.isEmpty, let type = UTType(filenameExtension: url.pathExtension) else {
            // No extension: Makefile, LICENSE, dotfiles are text far more often than not.
            return url.pathExtension.isEmpty
        }
        return type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .propertyList)
    }
}
