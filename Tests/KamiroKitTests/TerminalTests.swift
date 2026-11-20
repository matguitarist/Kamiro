import Foundation
import Testing
@testable import KamiroKit

@Suite struct TerminalTests {
    @Test func appleTerminalIsAlwaysOffered() {
        let list = TerminalApp.installed { _ in false }
        #expect(list == [TerminalApp.apple])
    }

    @Test func installedKeepsKnownOrder() {
        let list = TerminalApp.installed { ["com.mitchellh.ghostty", "org.alacritty"].contains($0) }
        #expect(list.map(\.name) == ["Terminal", "Ghostty", "Alacritty"])
    }

    @Test func choiceFallsBackToAppleWhenRemoved() {
        let list = TerminalApp.installed { $0 == "com.mitchellh.ghostty" }
        #expect(TerminalApp.chosen("com.mitchellh.ghostty", installed: list).name == "Ghostty")
        #expect(TerminalApp.chosen("com.googlecode.iterm2", installed: list) == .apple)
        #expect(TerminalApp.chosen(nil, installed: list) == .apple)
    }

    @Test func argumentsNameTheFolder() {
        let folder = URL(filePath: "/tmp/My Folder")
        let alacritty = TerminalApp.known.first { $0.name == "Alacritty" }
        #expect(alacritty?.arguments(for: folder) == ["--working-directory", "/tmp/My Folder"])
        #expect(TerminalApp.apple.arguments(for: folder).isEmpty)
    }
}
