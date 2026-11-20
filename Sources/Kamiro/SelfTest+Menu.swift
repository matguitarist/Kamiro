import AppKit
import KamiroKit

/// S-033: the right-click menu, and the disks' menus on the Home page.
extension SelfTest {
    static func rightClick(browser: BrowserModel, seed: URL) async {
        func url(_ path: String) -> URL { seed.appending(path: path).canonical }
        func titles(_ menu: NSMenu) -> [String] { menu.items.filter { !$0.isSeparatorItem }.map(\.title) }
        func t(_ key: String.LocalizationValue) -> String { String(localized: key) }
        browser.go(to: seed)
        await browser.waitUntilLoaded()

        // A file.
        browser.selection = [url("Guide.pdf")]
        let fileMenu = browser.contextMenu(onItems: true)
        let file = titles(fileMenu)
        check("a file's menu has Open, Open With, Cut, Copy, Copy Path, Duplicate, Rename, Move to Trash, Tags and Properties",
              [t("Open"), t("Open With"), t("Cut"), t("Copy"), t("Copy Path"), t("Duplicate"), t("Rename"), t("Move to Trash"),
               t("Tags"), t("Properties")].allSatisfy(file.contains), "\(file)")
        check("…and leaves out what's only for folders or empty space",
              ![t("Open in New Tab"), t("Pin to Sidebar"), t("Open in \("Terminal")"), t("New Folder"), t("New File")].contains(where: file.contains),
              "\(file)")
        let openWith = fileMenu.items.first { $0.title == t("Open With") }?.submenu
        let main = ItemActions.apps(for: [url("Guide.pdf")]).default.map(ItemActions.appName) ?? "none"
        check("Open With lists the apps for a PDF, the default first, and ends with Other…",
              (openWith?.items.first?.title.hasPrefix(main) ?? false) && openWith?.items.last?.title == t("Other…"),
              openWith.map(titles).map { "\($0)" } ?? "no submenu")

        // S-036: with ⌥ held, Open With reads Always Open With. Its entries change the system's
        // default, so the self-test only reads them.
        let always = fileMenu.items.first { $0.title == t("Always Open With") }
        check("⌥ turns Open With into Always Open With, with the same apps",
              always?.isAlternate == true && always?.keyEquivalentModifierMask == .option
              && always?.submenu.map(titles) == openWith.map(titles), always.map { "\($0.keyEquivalentModifierMask)" } ?? "missing")
        let openWithIndex = fileMenu.items.firstIndex { $0.title == t("Open With") } ?? -1
        check("…right after Open With, so they share one line", fileMenu.items.indices.contains(openWithIndex + 1)
              && fileMenu.items[openWithIndex + 1] === always)

        // S-034: Copy Info, and Open in the code editor for folders and text only.
        let info = fileMenu.items.first { $0.title == t("Copy Info") }?.submenu
        check("a file's Copy Info offers its name, name without extension, extension and parent folder path",
              info.map(titles) == [t("Name"), t("Name Without Extension"), t("Extension"), t("Parent Folder Path")],
              info.map(titles).map { "\($0)" } ?? "no submenu")
        if let info, let index = info.items.firstIndex(where: { $0.title == t("Name Without Extension") }) {
            info.performActionForItem(at: index)
        }
        check("Name Without Extension copies “Guide”", FileClipboard.shared.pasteboard.string(forType: .string) == "Guide")
        let copyPath = NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items).first { $0.title == t("Copy Path") }
        check("Edit › Copy Path is ⌥⌘C", copyPath?.keyEquivalent == "c" && copyPath?.keyEquivalentModifierMask == [.command, .option])
        if let editor = ItemActions.editor {
            // Earlier steps move and rename some sample files: take a text file still here.
            let textFile = browser.items.first { !$0.isFolder && ["md", "json", "csv", "txt"].contains($0.url.pathExtension) }
            browser.selection = Set(textFile.map { [$0.url] } ?? [])
            let text = titles(browser.contextMenu(onItems: true))
            check("a text file (\(textFile?.name ?? "none")) opens in \(editor.name), a PDF doesn't",
                  text.contains(t("Open in \(editor.name)")) && !file.contains(t("Open in \(editor.name)")), "\(text)")
        }

        // A folder.
        browser.selection = [url("Projects")]
        let folderInfo = browser.contextMenu(onItems: true).items.first { $0.title == t("Copy Info") }?.submenu
        check("a folder's Copy Info leaves out the extension choices",
              folderInfo.map(titles) == [t("Name"), t("Parent Folder Path")], folderInfo.map(titles).map { "\($0)" } ?? "no submenu")
        let folder = titles(browser.contextMenu(onItems: true))
        check("a folder's menu has Open in New Tab, Open in Terminal and Pin to Sidebar, without Open With",
              [t("Open in New Tab"), t("Open in \("Terminal")")].allSatisfy(folder.contains) && !folder.contains(t("Open With")), "\(folder)")

        // Several items.
        browser.selection = [url("Guide.pdf"), url("Projects")]
        let several = titles(browser.contextMenu(onItems: true))
        check("two items can't be renamed at once, so Rename is left out", !several.contains(t("Rename")) && several.contains(t("Duplicate")))

        // Empty space.
        browser.selection = []
        browser.copyPathOfSelection()
        check("Copy Path with nothing selected copies the folder's path", FileClipboard.shared.pasteboard.string(forType: .string) == seed.canonical.path)
        let empty = browser.contextMenu(onItems: false)
        let space = titles(empty)
        if let editor = ItemActions.editor {
            check("empty space offers Open Folder in \(editor.name)", space.contains(t("Open Folder in \(editor.name)")), "\(space)")
        }
        check("empty space has New Folder, New File, Open Terminal Here, Copy Path and Properties, and nothing for items",
              [t("New Folder"), t("New File"), t("Open \("Terminal") Here"), t("Copy Path"), t("Properties")].allSatisfy(space.contains)
              && ![t("Open"), t("Cut"), t("Rename"), t("Move to Trash")].contains(where: space.contains), "\(space)")
        // Another terminal chosen in Settings names itself in the menu.
        if let other = ItemActions.installedTerminals.last(where: { $0 != .apple }) {
            Prefs.defaults.set(other.bundleID, forKey: Prefs.terminal)
            let spaceOther = titles(browser.contextMenu(onItems: false))
            browser.selection = [url("Projects")]
            let folderOther = titles(browser.contextMenu(onItems: true))
            browser.selection = []
            Prefs.defaults.removeObject(forKey: Prefs.terminal)
            check("with \(other.name) chosen, the menus say Open \(other.name) Here and Open in \(other.name)",
                  spaceOther.contains(t("Open \(other.name) Here")) && folderOther.contains(t("Open in \(other.name)")),
                  "\(spaceOther) \(folderOther)")
        }
        FileClipboard.shared.put([url("Guide.pdf")], cut: false)
        check("…and Paste once something is copied", titles(browser.contextMenu(onItems: false)).first == t("Paste"))

        // Shape: groups, icons, one level of submenus.
        let menus = [fileMenu, empty, browser.contextMenu(onItems: false)]
        let wellGrouped = menus.allSatisfy { menu in
            let items = menu.items
            let doubled = zip(items, items.dropFirst()).contains { $0.isSeparatorItem && $1.isSeparatorItem }
            return !doubled && items.first?.isSeparatorItem == false && items.last?.isSeparatorItem == false
        }
        check("groups are separated once, never at the ends", wellGrouped)
        check("every line has an icon",
              menus.allSatisfy { $0.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.image != nil } })
        check("submenus go one level deep at most",
              menus.allSatisfy { $0.items.compactMap(\.submenu).allSatisfy { $0.items.allSatisfy { $0.submenu == nil } } })

        // Copy Path and Duplicate.
        ItemActions.copyPaths([url("Guide.pdf"), url("Projects")])
        check("Copy Path puts the paths on the pasteboard, one per line",
              FileClipboard.shared.pasteboard.string(forType: .string) == "\(url("Guide.pdf").path)\n\(url("Projects").path)")
        let copy = url("Guide \(t("copy")).pdf")
        try? FileManager.default.removeItem(at: copy)
        browser.selection = [url("Guide.pdf")]
        browser.duplicateSelection()
        for _ in 0..<30 where !FileManager.default.fileExists(atPath: copy.path) { try? await Task.sleep(for: .milliseconds(100)) }
        check("Duplicate makes “Guide copy.pdf” beside it (in the app's language)", FileManager.default.fileExists(atPath: copy.path))
        try? FileManager.default.removeItem(at: copy)
        let duplicate = NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items).first { $0.title == t("Duplicate") }
        check("File › Duplicate is ⌘D", duplicate?.keyEquivalent == "d" && duplicate?.keyEquivalentModifierMask == .command)

        // S-035: Compress and Extract Here, as transfers that can be undone.
        func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: url(path).path) }
        browser.selection = [url("Guide.pdf")]
        let one = titles(browser.contextMenu(onItems: true))
        // NSMenuItem turns the no-break spaces of French « » into plain spaces.
        let compressOne = t("Compress “\("Guide.pdf")”").replacingOccurrences(of: "\u{00A0}", with: " ")
        check("one item offers Compress “Guide.pdf”, not Extract Here",
              one.contains(compressOne) && !one.contains(t("Extract Here")), "\(one)")
        browser.compressSelection()
        await TransferCenter.shared.waitUntilIdle()
        for _ in 0..<30 where browser.selection != [url("Guide.zip")] { try? await Task.sleep(for: .milliseconds(100)) }
        check("Compress makes “Guide.zip” beside it, selected", exists("Guide.zip") && browser.selection == [url("Guide.zip")],
              "\(browser.selection.map(\.lastPathComponent))")
        let zipMenu = titles(browser.contextMenu(onItems: true))
        check("a zip offers Extract Here", zipMenu.contains(t("Extract Here")), "\(zipMenu)")
        let fileMenuExtract = NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items).first { $0.title == t("Extract Here") }
        check("File › Extract Here is there", fileMenuExtract != nil)
        browser.extractSelection()
        await TransferCenter.shared.waitUntilIdle()
        check("Extract Here brings out “Guide 2.pdf” next to it, the original kept", exists("Guide 2.pdf") && exists("Guide.pdf"),
              ((try? FileManager.default.contentsOfDirectory(atPath: seed.path)) ?? []).filter { $0.hasPrefix("Guide") }.joined(separator: ", "))
        FileUndo.manager.undo()
        check("Undo takes the extracted file away", !exists("Guide 2.pdf"))
        FileUndo.manager.undo()
        check("Undo again takes the archive away", !exists("Guide.zip"))
        browser.selection = [url("Guide.pdf"), url("Projects")]
        check("two items offer Compress 2 Items", titles(browser.contextMenu(onItems: true)).contains(t("Compress \(2) Items")))
        browser.compressSelection()
        await TransferCenter.shared.waitUntilIdle()
        let archive = t("Archive")
        check("…which makes “\(archive).zip”", exists("\(archive).zip"))
        try? FileManager.default.removeItem(at: url("\(archive).zip"))
        browser.selection = [url("Guide.pdf"), url("Projects")]
        check("two items also offer Compress To…", titles(browser.contextMenu(onItems: true)).contains(t("Compress To…")))
        browser.compress([url("Guide.pdf"), url("Projects")], to: url("Empty/Named.zip"))
        await TransferCenter.shared.waitUntilIdle()
        check("Compress To makes the archive with the chosen name and place", exists("Empty/Named.zip"))
        try? FileManager.default.removeItem(at: url("Empty/Named.zip"))
        browser.selection = [url("Guide.pdf")]
        check("one item has no Compress To…", !titles(browser.contextMenu(onItems: true)).contains(t("Compress To…")))
        await browser.waitUntilLoaded()

        // S-045: Convert, next to the original, as a transfer that can be undone.
        browser.selection = [url("Lotus.png")]
        let convert = browser.contextMenu(onItems: true).items.first { $0.title == t("Convert") }?.submenu
        let formats = convert?.items.map(\.title) ?? []
        check("a picture's Convert submenu has JPEG and Smaller for Email, not PNG",
              formats.contains("JPEG") && formats.contains(t("Smaller for Email")) && !formats.contains("PNG"), "\(formats)")
        browser.convertSelection(to: .jpeg)
        await TransferCenter.shared.waitUntilIdle()
        for _ in 0..<30 where browser.selection != [url("Lotus.jpg")] { try? await Task.sleep(for: .milliseconds(100)) }
        check("Convert › JPEG makes “Lotus.jpg” beside it, selected", exists("Lotus.jpg") && browser.selection == [url("Lotus.jpg")],
              "\(browser.selection.map(\.lastPathComponent))")
        FileUndo.manager.undo()
        check("Undo takes the converted file away", !exists("Lotus.jpg") && exists("Lotus.png"))
        browser.selection = [url("Guide.pdf")]
        check("a PDF offers only Smaller for Email",
              browser.contextMenu(onItems: true).items.first { $0.title == t("Convert") }?.submenu?.items.map(\.title) == [t("Smaller for Email")])
        browser.convertSelection(to: .smaller)
        await TransferCenter.shared.waitUntilIdle()
        let smaller = "Guide (\(t("smaller"))).pdf"
        check("Smaller for Email makes “\(smaller)”", exists(smaller))
        try? FileManager.default.removeItem(at: url(smaller))
        browser.selection = [url("notes.md")]
        check("a text file has no Convert", !titles(browser.contextMenu(onItems: true)).contains(t("Convert")))
        await browser.waitUntilLoaded()

        // S-046: Copy To and Move To, as transfers, remembered as recent folders.
        Prefs.defaults.removeObject(forKey: Prefs.recentFolders)
        let target = url("Empty"), sent = "Send me.txt"
        try? Data("x".utf8).write(to: url(sent))
        for _ in 0..<30 where !browser.items.contains(where: { $0.url == url(sent) }) { try? await Task.sleep(for: .milliseconds(100)) }
        browser.selection = [url(sent)]
        let items = titles(browser.contextMenu(onItems: true))
        check("items offer Copy To and Move To", items.contains(t("Copy To")) && items.contains(t("Move To")), "\(items)")
        browser.send(.copy, [url(sent)], to: target)
        await TransferCenter.shared.waitUntilIdle()
        check("Copy To puts a copy in the folder and keeps the original", exists("Empty/\(sent)") && exists(sent))
        check("…and remembers the folder", FolderHistory.recent.urls.first == target)
        let copyTo = browser.contextMenu(onItems: true).items.first { $0.title == t("Copy To") }?.submenu?.items ?? []
        check("Copy To lists the recent folder, then Other…",
              copyTo.contains { $0.toolTip == target.path } && copyTo.last?.title == t("Other…"), "\(copyTo.map(\.title))")
        try? FileManager.default.removeItem(at: url("Empty/\(sent)"))
        FolderHistory.record(seed)
        let moveTo = browser.contextMenu(onItems: true).items.first { $0.title == t("Move To") }?.submenu?.items.compactMap(\.toolTip) ?? []
        check("Move To leaves out the folder the items are in", !moveTo.contains(seed.path) && moveTo.contains(target.path), "\(moveTo)")
        browser.send(.move, [url(sent)], to: target)
        await TransferCenter.shared.waitUntilIdle()
        check("Move To moves it", exists("Empty/\(sent)") && !exists(sent))
        try? FileManager.default.removeItem(at: url("Empty/\(sent)"))
        Prefs.defaults.removeObject(forKey: Prefs.recentFolders)
        await browser.waitUntilLoaded()

        // S-055: a server's page lists its shares as folders (a fake list: no network in tests).
        ShareList.fake.withLock { $0 = ["isos", "downloads"] }
        let server = URL(string: "smb://Test._smb._tcp.local")!
        browser.go(to: server)
        await browser.waitUntilLoaded()
        check("smb://server opens its page with the shares as folders, A to Z",
              browser.isServerPage && browser.items.map(\.name) == ["downloads", "isos"] && browser.items.allSatisfy { $0.isFolder },
              "\(browser.items.map(\.name))")
        check("the page is named after the server", browser.title == "Test")
        browser.selection = [browser.items[0].url]
        check("a share that isn't mounted only offers Open", titles(browser.contextMenu(onItems: true)) == [t("Open")])
        ShareList.fake.withLock { $0 = nil }
        browser.goBack()
        await browser.waitUntilLoaded()

        // S-037: Go › Connect to Server… (⌘K) opens its sheet on this window.
        let connect = NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items).first { $0.title == t("Connect to Server…") }
        check("Go › Connect to Server… is ⌘K", connect?.keyEquivalent == "k" && connect?.keyEquivalentModifierMask == .command)
        let window = browser.details?.table?.window
        browser.showConnectToServer()
        for _ in 0..<30 where window?.attachedSheet == nil { try? await Task.sleep(for: .milliseconds(100)) }
        check("…and shows the Connect to Server sheet", window?.attachedSheet != nil)
        browser.connectShown = false
        for _ in 0..<30 where window?.attachedSheet != nil { try? await Task.sleep(for: .milliseconds(100)) }

        // Disks: Properties shows space without walking the disk.
        let startup = Volumes.facts(at: URL(filePath: "/"))
        let rows = startup.map(PropertiesFacts.rows) ?? []
        check("a disk's Properties shows its format, capacity, available and used space",
              [t("Format"), t("Capacity"), t("Available"), t("Used")].allSatisfy { label in rows.contains { $0.label == label } },
              "\(rows.map(\.label))")
        check("the startup disk can't be ejected", Volumes.volume(at: URL(filePath: "/")).map { !$0.actions.contains(.eject) } ?? false)
        await diskImage()
        await browser.waitUntilLoaded()
    }

    /// Mounts a small disk image from /tmp, renames it, then ejects it.
    private static func diskImage() async {
        let image = "/tmp/Kamiro-disk.dmg"
        let first = URL(filePath: "/Volumes/Kamiro Disk").canonical
        let renamed = URL(filePath: "/Volumes/Kamiro Disk 2").canonical
        defer {
            for mount in [first, renamed] where FileManager.default.fileExists(atPath: mount.path) {
                _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
            }
            try? FileManager.default.removeItem(atPath: image)
        }
        guard await shell("/usr/bin/hdiutil", ["create", "-size", "8m", "-fs", "APFS", "-volname", "Kamiro Disk", "-ov", image]),
              await shell("/usr/bin/hdiutil", ["attach", image]) else {
            check("a disk image mounts for the disk checks", false)
            return
        }
        guard let disk = await poll({ Volumes.volume(at: first) }) else {
            check("a mounted disk image is listed", false)
            return
        }
        check("a mounted disk image offers Rename and Eject", disk.actions.contains(.rename) && disk.actions.contains(.eject),
              "\(disk.actions)")
        ItemActions.renameVolume(disk, to: "Kamiro Disk 2")
        let after = await poll { Volumes.volume(at: renamed) }
        check("Rename gives the disk its new name", after?.name == "Kamiro Disk 2", Volumes.mounted().map(\.name).joined(separator: ", "))
        do {
            try await ItemActions.unmount(after ?? disk)
            check("Eject takes it off the list", Volumes.volume(at: renamed) == nil && Volumes.volume(at: first) == nil)
        } catch {
            check("Eject takes it off the list", false, error.localizedDescription)
        }
    }

    private static func poll<T>(_ find: () -> T?) async -> T? {
        for _ in 0..<50 {
            if let found = find() { return found }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    private static func shell(_ tool: String, _ arguments: [String]) async -> Bool {
        await Task.detached { run(tool, arguments) }.value
    }

    nonisolated private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
