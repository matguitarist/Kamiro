import Foundation

/// A terminal app that Open in Terminal can use (Settings › General › Terminal).
public struct TerminalApp: Hashable, Sendable, Identifiable {
    /// How the app is told which folder to start in.
    public enum Launch: Hashable, Sendable {
        /// Opened like a document: the app starts a window in the folder (Terminal, Ghostty, iTerm…).
        case openFolder
        /// A new instance with command-line arguments; "{folder}" stands for the folder's path.
        case arguments([String])
    }

    public var id: String { bundleID }
    public let bundleID: String
    public let name: String
    public let launch: Launch

    public init(bundleID: String, name: String, launch: Launch = .openFolder) {
        self.bundleID = bundleID
        self.name = name
        self.launch = launch
    }

    /// Apple's Terminal, always there.
    public static let apple = TerminalApp(bundleID: "com.apple.Terminal", name: "Terminal")

    /// The terminals Kamiro knows, Apple's first.
    public static let known: [TerminalApp] = [
        apple,
        TerminalApp(bundleID: "com.mitchellh.ghostty", name: "Ghostty"),
        TerminalApp(bundleID: "com.googlecode.iterm2", name: "iTerm"),
        TerminalApp(bundleID: "dev.warp.Warp-Stable", name: "Warp"),
        TerminalApp(bundleID: "co.zeit.hyper", name: "Hyper"),
        TerminalApp(bundleID: "net.kovidgoyal.kitty", name: "kitty", launch: .arguments(["--directory", "{folder}"])),
        TerminalApp(bundleID: "org.alacritty", name: "Alacritty", launch: .arguments(["--working-directory", "{folder}"])),
        TerminalApp(bundleID: "com.github.wez.wezterm", name: "WezTerm", launch: .arguments(["start", "--cwd", "{folder}"])),
    ]

    /// The known terminals that `isInstalled` finds, Apple's Terminal always among them.
    public static func installed(_ isInstalled: (String) -> Bool) -> [TerminalApp] {
        known.filter { $0 == apple || isInstalled($0.bundleID) }
    }

    /// The terminal to use: the chosen one while it's installed, Apple's Terminal otherwise.
    public static func chosen(_ bundleID: String?, installed: [TerminalApp]) -> TerminalApp {
        installed.first { $0.bundleID == bundleID } ?? apple
    }

    /// The command-line arguments for `folder`, for terminals launched with arguments.
    public func arguments(for folder: URL) -> [String] {
        guard case .arguments(let list) = launch else { return [] }
        return list.map { $0 == "{folder}" ? folder.path : $0 }
    }
}
