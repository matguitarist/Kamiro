import AppKit
import KamiroKit
import LogKitUI
import Quartz

/// Self-test for agents: drives a browser window over the sample tree in /tmp
/// (tools/seed-tree.sh), prints PASS or FAIL per check, and quits with 0 or 1.
///   APP_STORE=/tmp/Kamiro-self.json ~/Applications/Kamiro.app/Contents/MacOS/Kamiro --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(app: AppModel, browser: BrowserModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        let seed = Store.seedFolder
        guard Store.isOverridden, Store.url.path.hasPrefix("/tmp/") || Store.url.path.hasPrefix("/private/tmp/"),
              FileManager.default.fileExists(atPath: seed.path) else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp and run tools/seed-tree.sh first")
            finish(code: 1)
            return
        }
        Task {
            // The log.
            app.log.post(.info, "Self-test line", source: "SelfTest")
            try? await Task.sleep(for: .seconds(0.3))
            check("the app writes a log line", app.log.entries.contains { $0.message == "Self-test line" })
            app.log.flushFile()
            check("the log line reaches the log file",
                  ((try? String(contentsOf: Store.logURL, encoding: .utf8)) ?? "").contains("Self-test line"))

            // S-040: Settings › General › New windows open on.
            check("a test run's new windows open on the sample tree until something is chosen", Store.startFolder == seed)
            for (place, expected) in [(StartPlace.folder(seed.appending(path: "Projects")), seed.appending(path: "Projects").path),
                                      (.folder(seed.appending(path: "Gone")), VirtualPlace.home.url.path),
                                      (.home, VirtualPlace.home.url.path)] {
                Prefs.defaults.set(place.stored, forKey: Prefs.newWindowStart)
                check("New windows open on \(place.title) opens \(expected)", Store.startFolder.path == expected, Store.startFolder.path)
            }
            Prefs.defaults.removeObject(forKey: Prefs.newWindowStart)

            // S-001, S-002: the sample tree, Finder's order, folders first.
            browser.go(to: seed)
            await browser.waitUntilLoaded()
            // Hidden items (dotfiles and the hidden flag) show only with View › Show Hidden Files (S-024).
            let onDisk = ((try? FileManager.default.contentsOfDirectory(at: seed, includingPropertiesForKeys: [.isHiddenKey])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isHiddenKey]).isHidden) != true }
            check("the window lists every visible item", browser.items.count == onDisk.count, "\(browser.items.count) vs \(onDisk.count)")
            let names = browser.items.map(\.name)
            let firstFile = browser.items.firstIndex { !$0.isFolder } ?? 0
            check("folders come first", browser.items.prefix(firstFile).allSatisfy(\.isFolder) && firstFile > 0)
            if let two = names.firstIndex(of: "Track 2.m4a"), let ten = names.firstIndex(of: "Track 10.m4a") {
                check("numbers sort in order (2 before 10)", two < ten)
            } else {
                check("the sample tracks are listed", false)
            }
            check("an app is a file, not a folder", browser.items.first { $0.name == "Sample.app" }.map { !$0.isFolder && $0.isPackage } == true)
            check("the window title names the folder", browser.title == "Kamiro-seed")

            // S-002: a big folder.
            let started = ContinuousClock.now
            browser.go(to: seed.appending(path: "10k"))
            await browser.waitUntilLoaded()
            let took = ContinuousClock.now - started
            check("10,000 files are listed and sorted within 300 ms", browser.items.count == 10_000 && took < .milliseconds(300), "\(took)")
            check("Photo 2 comes before Photo 10", browser.items.prefix(3).map(\.name) == ["Photo 1.jpg", "Photo 2.jpg", "Photo 3.jpg"])

            // S-003: back, forward, up.
            browser.goBack()
            await browser.waitUntilLoaded()
            check("Back returns to the sample tree", browser.folder == seed && browser.history.canGoForward)
            browser.goForward()
            await browser.waitUntilLoaded()
            check("Forward goes to the big folder again", browser.folder == seed.appending(path: "10k"))
            browser.goUp()
            await browser.waitUntilLoaded()
            check("Up selects the folder we came from", browser.folder == seed && browser.selection == [seed.appending(path: "10k")])
            browser.go(to: seed.appending(path: "Projects"))
            await browser.waitUntilLoaded()
            browser.goBack()
            await browser.waitUntilLoaded()
            check("Back restores the selection", browser.selection == [seed.appending(path: "10k")])

            // S-005: typed paths.
            browser.beginEditingPath()
            browser.pathText = "Projects/Kamiro"
            browser.submitPath()
            await browser.waitUntilLoaded()
            check("a relative path goes there", browser.folder == seed.appending(path: "Projects/Kamiro") && !browser.isEditingPath)
            browser.beginEditingPath()
            browser.pathText = "'\(seed.path)/notes.md'"
            browser.submitPath()
            await browser.waitUntilLoaded()
            check("a file's path opens its folder with the file selected",
                  browser.folder == seed && browser.selection == [seed.appending(path: "notes.md")])
            browser.beginEditingPath()
            browser.pathText = "/tmp/Kamiro-seed/Nowhere"
            browser.submitPath()
            check("a path that doesn't exist says so and stays in the field",
                  browser.isEditingPath && browser.pathError == String(localized: "No folder at this path.") && browser.folder == seed)
            browser.cancelEditingPath()
            check("Escape puts the crumbs back", !browser.isEditingPath && browser.pathError == nil)

            // S-006: Return follows the setting.
            Prefs.defaults.set(false, forKey: Prefs.returnOpensItems)
            browser.selection = [seed.appending(path: "Projects")]
            check("Return doesn't open by default, it renames", browser.handleReturn() && browser.folder == seed
                  && browser.renameTarget == seed.appending(path: "Projects"))
            for _ in 0..<20 where browser.details?.renaming == nil { try? await Task.sleep(for: .seconds(0.05)) }
            browser.details?.endRename()
            Prefs.defaults.set(true, forKey: Prefs.returnOpensItems)
            check("with Return opens items on, Return opens the folder", browser.handleReturn())
            await browser.waitUntilLoaded()
            check("…and the folder shows", browser.folder == seed.appending(path: "Projects"))
            Prefs.defaults.removeObject(forKey: Prefs.returnOpensItems)
            browser.goBack()
            await browser.waitUntilLoaded()

            // S-007: Quick Look.
            browser.selection = [seed.appending(path: "notes.md")]
            try? await Task.sleep(for: .seconds(0.3))
            browser.focusList()
            try? await Task.sleep(for: .seconds(0.2))
            browser.quickLook?()
            try? await Task.sleep(for: .seconds(1))
            let panelShown = QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared()?.isVisible == true
            check("Quick Look opens for the selection", panelShown)
            browser.quickLook?()
            try? await Task.sleep(for: .seconds(0.5))
            check("Quick Look closes again", QLPreviewPanel.shared()?.isVisible != true)

            // S-008: the status bar.
            browser.selection = [seed.appending(path: "report.pdf"), seed.appending(path: "Song.m4a")]
            let status = StatusText.make(browser.counts)
            let counts = browser.counts
            let size = ByteCountFormatter.string(fromByteCount: counts.selectedBytes ?? 0, countStyle: .file)
            check("the status bar counts items, the selection and its size",
                  counts.items == browser.items.count && counts.selected == 2 && counts.available != nil
                  && status.hasPrefix(String(localized: "\(counts.items) items")) && status.contains(size), status)

            // S-009: changes made elsewhere.
            let added = seed.appending(path: "Added Elsewhere.txt")
            FileManager.default.createFile(atPath: added.path, contents: Data("hi".utf8))
            try? await Task.sleep(for: .seconds(0.8))
            await browser.waitUntilLoaded()
            check("a file made by another app appears within a second", browser.items.contains { $0.url == added })
            check("the selection stays put", browser.selection.count == 2)
            let renamed = seed.appending(path: "Report Final.pdf")
            try? FileManager.default.moveItem(at: seed.appending(path: "report.pdf"), to: renamed)
            try? await Task.sleep(for: .seconds(0.8))
            await browser.waitUntilLoaded()
            check("a selected file renamed elsewhere stays selected", browser.selection.contains(renamed))

            // S-010: a folder Kamiro can't open.
            browser.go(to: seed.appending(path: "Locked"))
            await browser.waitUntilLoaded()
            check("a closed folder says so instead of looking empty", browser.state == .failed(.denied))
            let purposes = ["NSDesktopFolderUsageDescription", "NSDocumentsFolderUsageDescription", "NSDownloadsFolderUsageDescription",
                            "NSRemovableVolumesUsageDescription", "NSNetworkVolumesUsageDescription"]
            check("Info.plist explains every protected folder", purposes.allSatisfy { Bundle.main.object(forInfoDictionaryKey: $0) != nil })

            await views(browser: browser, seed: seed)
            await fileActions(browser: browser, seed: seed)
            await homeAndPins(browser: browser, seed: seed)
            await cloud(browser: browser, seed: seed)
            await rightClick(browser: browser, seed: seed)
            await tools(browser: browser, seed: seed)
            await externalOpen(browser: browser, seed: seed)

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    // MARK: M2, file actions (S-011 to S-018)

    /// Runs on the sample tree; the Trash is /tmp/Kamiro-trash and the pasteboard a private one.
    private static func fileActions(browser: BrowserModel, seed: URL) async {
        let files = FileManager.default
        let trash = URL(filePath: "/tmp/Kamiro-trash")
        try? files.removeItem(at: trash)
        func url(_ path: String) -> URL { seed.appending(path: path).canonical }
        func exists(_ path: String) -> Bool { files.fileExists(atPath: url(path).path) }
        func pause(_ seconds: Double = 0.3) async { try? await Task.sleep(for: .seconds(seconds)) }
        func open(_ path: String = "") async {
            browser.go(to: path.isEmpty ? seed : url(path))
            await browser.waitUntilLoaded()
            browser.focusList()
            await pause()
        }
        func settle() async {
            await TransferCenter.shared.waitUntilIdle()
            await pause(0.2)
            await browser.waitUntilLoaded()
        }
        var table: FileTable? { browser.details?.table }
        var editor: NSTextView? { table?.window?.firstResponder as? NSTextView }
        func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) {
            guard let table, let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                                         windowNumber: table.window?.windowNumber ?? 0, context: nil,
                                                         characters: "", charactersIgnoringModifiers: "", isARepeat: false,
                                                         keyCode: code) else { return }
            table.keyDown(with: event)
        }
        // The window isn't key when a terminal starts the test, so nil-targeted actions find
        // nothing: walk the window's responder chain, as the menu does for the key window.
        func responder(for action: Selector) -> NSResponder? {
            var next = table?.window?.firstResponder
            while let current = next {
                if current.responds(to: action) { return current }
                next = current.nextResponder
            }
            return nil
        }
        func dimmed(_ path: String) -> Bool {
            guard let table, let row = browser.details?.rowOf[url(path)] else { return false }
            return table.view(atColumn: 0, row: row, makeIfNecessary: true)?.alphaValue == 0.5
        }

        // S-011: cut, copy, paste.
        await open()
        browser.selection = [url("Invoice 1.pdf"), url("Invoice 2.pdf")]
        responder(for: #selector(FileTable.cut(_:)))?.tryToPerform(#selector(FileTable.cut(_:)), with: nil)
        await pause()
        check("⌘X marks the selection cut", FileClipboard.shared.isCut(url("Invoice 1.pdf")) && FileClipboard.shared.urls.count == 2,
              "\(String(describing: responder(for: #selector(FileTable.cut(_:))).map { type(of: $0) }))")
        check("cut items draw at half opacity", dimmed("Invoice 1.pdf") && !dimmed("notes.md"))
        key(53)
        await pause()
        check("Escape forgets the cut", !FileClipboard.shared.isCutActive && !dimmed("Invoice 1.pdf"))
        browser.cutSelection()
        await open("Photos")
        browser.paste()
        await settle()
        check("pasting cut items moves them", exists("Photos/Invoice 1.pdf") && !exists("Invoice 1.pdf"))
        check("…and selects them where they land", browser.selection == [url("Photos/Invoice 1.pdf"), url("Photos/Invoice 2.pdf")])
        browser.copySelection()
        browser.paste()
        await settle()
        check("pasting copies in the same folder makes “name copy”",
              exists("Photos/Invoice 1 \(String(localized: "copy")).pdf") && exists("Photos/Invoice 1.pdf"))

        // S-012: progress and Stop.
        await open()
        browser.transfer(.copy, [url("10k")], into: url("Empty"))
        browser.transfer(.copy, [url("10k")], into: url("Music"))
        var shown = 0
        for _ in 0..<20 where shown < 2 && !TransferCenter.shared.isIdle {
            await pause(0.05)
            shown = TransferCenter.shared.tasks.count
        }
        check("several transfers show in one popover", shown == 2, "\(shown)")
        TransferCenter.shared.tasks.forEach { $0.cancel() }
        await settle()
        check("Stop leaves nothing half-copied", !exists("Empty/10k") && !exists("Music/10k")
              && ((try? files.contentsOfDirectory(atPath: url("10k").path).count) ?? 0) == 10_000)

        // S-013: a name conflict.
        browser.transfer(.copy, [url("notes.md")], into: url("Projects"))
        for _ in 0..<20 where browser.conflicts.isEmpty { await pause(0.05) }
        await pause(0.5)
        let question = browser.conflicts.first
        check("a name conflict asks, showing both items' size and date",
              question?.existing?.size != nil && question?.source?.modified != nil && question?.existing?.size != question?.source?.size
              && table?.window?.attachedSheet != nil)
        question?.answer(ConflictAnswer(.keepBoth))
        await settle()
        check("Keep Both names the copy “notes 2.md”", exists("Projects/notes 2.md") && exists("Projects/notes.md"))

        // S-014: rename in place.
        await open()
        Prefs.defaults.set(false, forKey: Prefs.returnOpensItems)
        browser.selection = [url("notes.md")]
        key(36)
        await pause()
        check("Return starts renaming with the name selected, not its extension",
              browser.details?.renaming == url("notes.md") && editor?.selectedRange() == NSRange(location: 0, length: 5))
        let cutTarget = responder(for: #selector(FileTable.cut(_:)))
        check("⌘X while renaming cuts text, not files", cutTarget is NSText && !MenuState.shared.listFocused)
        editor?.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        await pause()
        check("Escape cancels the rename", browser.details?.renaming == nil && exists("notes.md"))
        key(120)
        await pause()
        editor?.string = "a:b.md"
        editor?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        await pause()
        check("F2 renames too; a name with “:” shows an error and keeps editing",
              browser.details?.renaming == url("notes.md") && browser.details?.renameError != nil)
        editor?.string = "notes renamed.md"
        editor?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        await pause()
        await browser.waitUntilLoaded()
        check("Return saves the new name", exists("notes renamed.md") && !exists("notes.md")
              && browser.selection == [url("notes renamed.md")])
        await pause()
        key(36)
        await pause()
        let row = browser.details?.rowOf[url("notes renamed.md")] ?? 0
        let next = browser.details?.url(at: row + 1)
        editor?.doCommand(by: #selector(NSResponder.insertTab(_:)))
        await pause(0.5)
        check("Tab moves on to the next item", next != nil && browser.details?.renaming == next)
        editor?.string = (next?.deletingPathExtension().lastPathComponent ?? "x") + ".changed"
        editor?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        await pause()
        check("changing an extension asks first", browser.pendingExtension != nil)
        browser.answerExtension(use: false)
        await pause()
        await browser.waitUntilLoaded()
        check("Keep puts the old extension back", next.map { files.fileExists(atPath: $0.path) } ?? false)

        // S-015: new items.
        await open()
        browser.newFolder()
        await browser.waitUntilLoaded()
        for _ in 0..<20 where browser.details?.renaming == nil { await pause(0.05) }
        let untitled = String(localized: "untitled folder")
        check("New Folder makes “untitled folder”, ready to rename",
              exists(untitled) && browser.details?.renaming == url(untitled))
        editor?.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        await pause()
        if let shell = FileTemplate.all.first(where: { $0.id == "shell" }) { browser.newFile(shell) }
        await browser.waitUntilLoaded()
        for _ in 0..<20 where browser.details?.renaming == nil { await pause(0.05) }
        check("New File › Shell Script makes a script ready to run", files.isExecutableFile(atPath: url(String(localized: "untitled") + ".sh").path))
        editor?.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        let titles = Set(FileTemplate.all.map(\.title))
        func templates(_ menu: NSMenu?) -> Int { menu?.items.filter { titles.contains($0.title) }.count ?? 0 }
        let fileMenu = NSApp.mainMenu?.items.compactMap(\.submenu).first { $0.items.contains { $0.title == String(localized: "New Folder") } }
        let menuNewFile = fileMenu?.items.first { $0.title == String(localized: "New File") }?.submenu
        let contextNewFile = browser.details?.contextMenu(onItems: false).items.first { $0.title == String(localized: "New File") }?.submenu
        check("New File is in the File menu and the right-click menu, with every template",
              templates(menuNewFile) == FileTemplate.all.count && templates(contextNewFile) == FileTemplate.all.count,
              "\(templates(menuNewFile)), \(templates(contextNewFile))")
        check("…each template shows its file kind's icon",
              contextNewFile?.items.filter { titles.contains($0.title) }.allSatisfy { $0.image != nil } ?? false)

        // S-044: New File from Clipboard, on the test pasteboard.
        let board = FileClipboard.shared.pasteboard
        board.clearContents()
        board.setString("{\"from\": \"clipboard\"}", forType: .string)
        let fromClipboard = String(localized: "New File from Clipboard")
        check("empty space offers New File from Clipboard when the clipboard has text",
              browser.details?.contextMenu(onItems: false).items.contains { $0.title == fromClipboard } ?? false)
        browser.newFileFromClipboard()
        await browser.waitUntilLoaded()
        for _ in 0..<20 where browser.details?.renaming == nil { await pause(0.05) }
        let clipped = String(localized: "untitled") + ".json"
        check("New File from Clipboard makes JSON into “\(clipped)”, ready to rename",
              exists(clipped) && browser.details?.renaming == url(clipped))
        editor?.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        board.clearContents()
        check("an empty clipboard leaves it out of the menu",
              !(browser.details?.contextMenu(onItems: false).items.contains { $0.title == fromClipboard } ?? true))

        // S-016: Trash and Delete Immediately.
        await open()
        browser.selection = [url("Invoice 12.pdf")]
        key(51, .command)
        await browser.waitUntilLoaded()
        check("⌘⌫ moves to the Trash", !exists("Invoice 12.pdf") && files.fileExists(atPath: trash.appending(path: "Invoice 12.pdf").path))
        FileUndo.manager.undo()
        await pause()
        check("Undo puts it back", exists("Invoice 12.pdf"))
        await open()
        browser.selection = [url("budget.csv")]
        key(51)
        await browser.waitUntilLoaded()
        await pause()
        check("⌫ alone moves to the Trash, like Windows", !exists("budget.csv")
              && files.fileExists(atPath: trash.appending(path: "budget.csv").path))
        FileUndo.manager.undo()
        await pause()
        await open()
        browser.selection = [url("budget.csv")]
        key(117)
        await browser.waitUntilLoaded()
        await pause()
        check("Forward Delete does too", !exists("budget.csv"))
        await open()
        browser.selection = [url("Track 10.m4a"), url("Track 11.m4a")]
        key(51, [.command, .option])
        await pause(0.6)
        check("⌥⌘⌫ asks “Delete 2 Items Immediately?”", browser.pendingDelete?.count == 2 && table?.window?.attachedSheet != nil)
        browser.deleteImmediately()
        await pause(0.5)
        check("…and deletes them for good", !exists("Track 10.m4a") && !files.fileExists(atPath: trash.appending(path: "Track 10.m4a").path))

        // S-017: Undo and Redo.
        await open()
        browser.selection = [url("Track 1.m4a"), url("Track 2.m4a"), url("Track 3.m4a")]
        browser.cutSelection()
        await open("Music")
        browser.paste()
        await settle()
        browser.focusList()
        await pause()
        let undoItem = NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items).first { $0.action == #selector(FileTable.undo(_:)) }
        if let undoItem, let validator = responder(for: #selector(FileTable.undo(_:))) as? any NSUserInterfaceValidations {
            _ = validator.validateUserInterfaceItem(undoItem)
        }
        let expected = FileUndo.manager.undoMenuTitle(forUndoActionName: String(localized: "Move of \(3) Items"))
        check("Edit › Undo says “Undo Move of 3 Items”", undoItem?.title == expected,
              "\(undoItem?.title ?? "no Undo item") action \(String(describing: undoItem?.action)) target \(String(describing: undoItem?.target)) all: \(NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items).filter { $0.title.hasPrefix("Undo") || $0.title.hasPrefix("Annuler") }.map { "\($0.title) \(String(describing: $0.action))" } ?? [])")
        FileUndo.manager.undo()
        await pause()
        check("Undo moves all three back in one step", ["Track 1.m4a", "Track 2.m4a", "Track 3.m4a"].allSatisfy { exists($0) })
        FileUndo.manager.redo()
        await pause()
        check("Redo moves them again", exists("Music/Track 1.m4a") && !exists("Track 1.m4a"))

        // S-018: drops and spring-loaded folders.
        await open()
        check("a drop on a folder moves the item on the same disk", browser.drop([url("data.json")], into: url("Projects")))
        await settle()
        check("…and it lands there", exists("Projects/data.json") && !exists("data.json"))
        if let row = browser.details?.rowOf[url("Photos")] { browser.details?.spring(row) }
        await pause(0.9)
        await browser.waitUntilLoaded()
        check("a folder held under a drag opens after 0.7 s", browser.folder == url("Photos"))
    }

    static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
