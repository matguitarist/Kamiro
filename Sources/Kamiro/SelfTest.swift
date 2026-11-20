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

            // S-001, S-002: the sample tree, Finder's order, folders first.
            browser.go(to: seed)
            await browser.waitUntilLoaded()
            let onDisk = (try? FileManager.default.contentsOfDirectory(atPath: seed.path).filter { !$0.hasPrefix(".") }) ?? []
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
            check("Return doesn't open by default", !browser.handleReturn() && browser.folder == seed)
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

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
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
