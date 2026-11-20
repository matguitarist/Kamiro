import AppKit
import KamiroKit

/// S-049: Settings › Tools, on a run where no tool is installed, then with a fake one.
extension SelfTest {
    static func tools(browser: BrowserModel, seed: URL) async {
        let store = ToolStore.shared
        let folder = URL(filePath: "/tmp/Kamiro-tools")
        try? FileManager.default.removeItem(at: folder)
        await store.refresh()
        let lines = CommandTool.all.filter { store.installed[$0.id] == nil }.map(\.brewLine)
        check("with no tools, Settings › Tools shows three “brew install …” lines",
              store.installed.isEmpty && lines.count == 3 && lines.allSatisfy { $0.hasPrefix("brew install ") }, "\(lines)")
        store.copy(CommandTool.ffmpeg.brewLine)
        check("Copy puts the line on the pasteboard", store.pasteboard.string(forType: .string) == "brew install ffmpeg")
        check("Settings has a Tools tab", SettingsTab.allCases.contains(.tools))

        browser.go(to: seed)
        await browser.waitUntilLoaded()
        browser.selection = [seed.appending(path: "Lotus.png").canonical]
        let lotus = seed.appending(path: "Lotus.png")
        check("with no tools, Convert offers nothing that needs one",
              !browser.convertChoices.isEmpty && browser.convertChoices.allSatisfy { $0.needs(for: lotus) == [] })

        // A tool put where Kamiro looks is found with its version.
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fake = folder.appending(path: "cwebp")
        try? "#!/bin/sh\necho 1.4.0\n".write(to: fake, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        await store.refresh()
        check("an installed tool shows its version", store.installed["cwebp"]?.version == "1.4.0")
        // S-050: with cwebp found, Convert offers WebP (where macOS can't write it itself).
        check("with cwebp found, Convert offers WebP", browser.convertChoices.contains(.webp))
        check("…made with cwebp", Conversion.webp.isAvailable || Conversion.webp.needs(for: lotus) == [.cwebp])
        try? FileManager.default.removeItem(at: folder)
        await store.refresh()
        check("…and is gone once removed", store.installed.isEmpty)
    }
}
