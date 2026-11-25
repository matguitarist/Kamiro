import AppKit
import AppTestKit
import KamiroKit
import SwiftUI

/// Screenshot mode for agents (tools/snap.sh builds the sample tree first):
///   APP_STORE=/tmp/Kamiro-test.json APP_SEED=1 APP_SNAPSHOT=/tmp/Kamiro-shots ~/Applications/Kamiro.app/Contents/MacOS/Kamiro
/// writes <page>-light.png and <page>-dark.png for every page below, the Log window, and
/// settings-<tab>-light.png and -dark.png for every Settings tab, then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// APP_SNAPSHOT_PAGES=browse,details-10k limits the pages. Add "log" and "settings" to include them.
/// Add APP_ACCENT=<id> to see the pages in another accent.
/// Add APP_SNAPSHOT_MIN=1 to shrink the main window to its smallest size first.
enum Snapshot {
    /// The pages, each a place in the sample tree (tools/seed-tree.sh).
    enum Page: String, CaseIterable {
        case browse, selected, details10k = "details-10k", addressEdit = "address-edit", accessDenied = "access-denied", empty
        case cutDimmed = "cut-dimmed", rename, transferProgress = "transfer-progress", conflictSheet = "conflict-sheet"
        case deleteConfirm = "delete-confirm", connectServer = "connect-server"
        case icons, columns
        case columnsMenu = "columns-menu"
        case grouped, hidden, inspector
        case properties, propertiesFolder = "properties-folder", propertiesDisk = "properties-disk"
        case tags, filter
        case searchResults = "search-results"
        case tabs
        case home
        case icloud
        case icloudIcons = "icloud-icons"
        case diskUsage = "disk-usage"

        /// Pages shot in their own window instead of the main one.
        var windowID: String? {
            switch self {
            case .properties, .propertiesFolder, .propertiesDisk: KamiroApp.propertiesID
            case .diskUsage: KamiroApp.diskUsageID
            default: nil
            }
        }

        @MainActor
        func show(in browser: BrowserModel) async {
            let seed = Store.seedFolder
            if browser.isEditingPath { browser.cancelEditingPath() }
            switch self {
            case .browse: browser.go(to: seed)
            case .selected: browser.go(to: seed, select: [seed.appending(path: "report.pdf"), seed.appending(path: "Song.m4a")])
            case .details10k: browser.go(to: seed.appending(path: "10k"))
            case .addressEdit:
                browser.go(to: seed.appending(path: "Projects/Kamiro"))
                await browser.waitUntilLoaded()
                browser.beginEditingPath()
            case .accessDenied: browser.go(to: seed.appending(path: "Locked"))
            case .empty: browser.go(to: seed.appending(path: "Empty"))
            case .cutDimmed, .deleteConfirm:
                browser.go(to: seed, select: [seed.appending(path: "Invoice 1.pdf"), seed.appending(path: "Invoice 2.pdf")])
            case .rename: browser.go(to: seed, select: [seed.appending(path: "notes.md")])
            case .transferProgress, .conflictSheet, .connectServer: browser.go(to: seed)
            case .icons:
                browser.go(to: seed, select: [seed.appending(path: "Owl.jpg")])
                browser.mode = .icons
            case .columns:
                browser.go(to: seed)
                await browser.waitUntilLoaded()
                browser.mode = .columns
                try? await Task.sleep(for: .seconds(0.3))
                browser.go(to: seed.appending(path: "Projects"), select: [seed.appending(path: "Projects/notes.md")])
            case .columnsMenu:
                browser.go(to: seed)
                await browser.waitUntilLoaded()
                browser.toggleColumn(.created)
                browser.toggleColumn(.ext)
            case .grouped:
                browser.go(to: seed)
                await browser.waitUntilLoaded()
                browser.groupBy = .kind
                // One group folded, to show both states.
                if let last = browser.details?.rows.reversed().first(where: { if case .header = $0 { true } else { false } }),
                   case .header(let header) = last {
                    browser.toggleGroup(header.id)
                }
            case .properties, .propertiesFolder:
                let name = self == .properties ? "Owl.jpg" : "Photos"
                browser.go(to: seed, select: [seed.appending(path: name)])
                await browser.waitUntilLoaded()
                browser.showProperties()
                try? await Task.sleep(for: .seconds(1.5))
            case .diskUsage:
                browser.go(to: seed)
                await browser.waitUntilLoaded()
                browser.openDiskUsage?(seed)
                for _ in 0..<50 where DiskUsageModel.latest?.state != .ready { try? await Task.sleep(for: .seconds(0.1)) }
                if let model = DiskUsageModel.latest, let photos = model.shown?.children.first(where: { $0.name == "Photos" }) {
                    model.selection = photos.id
                }
                try? await Task.sleep(for: .seconds(0.5))
            case .propertiesDisk:
                browser.openProperties?(URL(filePath: "/"))
                try? await Task.sleep(for: .seconds(1.5))
            case .searchResults:
                browser.go(to: seed)
                await browser.waitUntilLoaded()
                browser.filterText = "notes"
                browser.searchEverywhere()
                await browser.waitUntilLoaded()
                browser.selection = [seed.appending(path: "Projects/notes.md").canonical]
            case .filter:
                browser.go(to: seed)
                await browser.waitUntilLoaded()
                browser.filterText = "invoice"
            case .home:
                PinStore.shared.pin([seed.appending(path: "Projects"), seed.appending(path: "Photos")])
                browser.go(to: VirtualPlace.home.url)
                try? await Task.sleep(for: .seconds(1))
            case .icloud, .icloudIcons:
                browser.go(to: Cloud.drive, select: [Cloud.drive.appending(path: "Scan.pdf")])
                await browser.waitUntilLoaded()
                await browser.waitForCloud()
                if self == .icloudIcons { browser.mode = .icons }
            case .tabs:
                browser.go(to: seed)
                await browser.waitUntilLoaded()
                browser.open([seed.appending(path: "Projects")], newTab: true)
                try? await Task.sleep(for: .seconds(1.5))
            case .tags:
                let red = ColorTag.red.name
                try? Tags.set(red, present: true, on: ["Owl.jpg", "Lotus.png", "notes.md"].map { seed.appending(path: $0) })
                try? Tags.set(ColorTag.blue.name, present: true, on: [seed.appending(path: "notes.md")])
                browser.go(to: ColorTag.red.place.url)
                await browser.waitUntilLoaded()
                if !browser.columns.contains(.tags) { browser.toggleColumn(.tags) }
                try? await Task.sleep(for: .seconds(0.5))
            case .inspector:
                Prefs.defaults.set(true, forKey: Prefs.showInspector)
                try? await Task.sleep(for: .seconds(1))
                browser.go(to: seed, select: [seed.appending(path: "Owl.jpg")])
                try? await Task.sleep(for: .seconds(1.5))
            case .hidden:
                browser.go(to: seed)
                await browser.waitUntilLoaded()
                HiddenFiles.set(true)
                try? await Task.sleep(for: .seconds(0.3))
                await browser.waitUntilLoaded()
                browser.go(to: seed, select: [seed.appending(path: ".hidden-notes")])
            }
            await browser.waitUntilLoaded()
            if self != .addressEdit { browser.focusList() }
            try? await Task.sleep(for: .seconds(0.3))
            switch self {
            case .cutDimmed: browser.cutSelection()
            case .rename: browser.beginRename()
            case .transferProgress: TransferCenter.shared.showSample()
            case .conflictSheet:
                let conflict = Conflict(source: seed.appending(path: "notes.md"), existing: seed.appending(path: "Projects/notes.md"), remaining: 2)
                browser.conflicts = [ConflictQuestion(conflict: conflict, kind: .copy) { _ in browser.conflicts = [] }]
            case .deleteConfirm: browser.askDeleteImmediately()
            case .connectServer:
                // Snapshots run on the test settings: these addresses never reach the real ones.
                ServerHistory.recent = RecentServers(["smb://nas.local/Media", "afp://old-mac.local", "https://dav.example.com/files"])
                browser.showConnectToServer()
            default: break
            }
        }

        /// Puts things back after the page's snapshot.
        @MainActor
        func cleanUp(in browser: BrowserModel) async {
            switch self {
            case .cutDimmed: FileClipboard.shared.clearCut()
            case .rename: browser.details?.endRename()
            case .transferProgress: TransferCenter.shared.hideSample()
            case .conflictSheet: browser.conflicts = []
            case .deleteConfirm: browser.pendingDelete = nil
            case .connectServer:
                browser.connectShown = false
                ServerHistory.recent = RecentServers()
            case .icons, .icloudIcons: browser.mode = .details
            case .columns:
                // Views are kept per folder: put the sample folder back in details, not Projects.
                browser.go(to: Store.seedFolder)
                await browser.waitUntilLoaded()
                browser.mode = .details
            case .columnsMenu:
                browser.toggleColumn(.created)
                browser.toggleColumn(.ext)
            case .grouped: browser.groupBy = .none
            case .hidden: HiddenFiles.set(false)
            case .inspector: Prefs.defaults.set(false, forKey: Prefs.showInspector)
            case .filter: browser.filterText = ""
            case .tabs:
                let main = browser.details?.table?.window
                main?.tabbedWindows?.filter { $0 !== main }.forEach { $0.close() }
                main?.makeKeyAndOrderFront(nil)
            case .searchResults:
                browser.go(to: Store.seedFolder)
                await browser.waitUntilLoaded()
            case .home:
                Prefs.defaults.removeObject(forKey: Prefs.pins)
                PinStore.shared.reload()
                browser.go(to: Store.seedFolder)
                await browser.waitUntilLoaded()
            case .tags:
                let seed = Store.seedFolder
                for name in ["Owl.jpg", "Lotus.png", "notes.md"] {
                    try? Tags.set(ColorTag.red.name, present: false, on: [seed.appending(path: name)])
                }
                try? Tags.set(ColorTag.blue.name, present: false, on: [seed.appending(path: "notes.md")])
                browser.go(to: seed)
                await browser.waitUntilLoaded()
            case .properties, .propertiesFolder, .propertiesDisk:
                NSApp.windows.filter { $0.identifier?.rawValue.contains(KamiroApp.propertiesID) == true }.forEach { $0.close() }
            case .diskUsage:
                NSApp.windows.filter { $0.identifier?.rawValue.contains(KamiroApp.diskUsageID) == true }.forEach { $0.close() }
            default: return
            }
            try? await Task.sleep(for: .seconds(0.5))
        }
    }

    static func runIfRequested(app: AppModel, browser: BrowserModel, openSettings: OpenSettingsAction, openWindow: OpenWindowAction) {
        // Snapshots never run against the real settings.
        guard let run = SnapshotRun.requested(layout: { GridProbes.shared.write(to: $0.path, window: $1) }) else { return }
        Task {
            await run.start()
            let main = WindowShot.mainWindow()
            let pages = Page.allCases.filter { run.wants($0.rawValue) }
            await run.forEachAppearance { look in
                for page in pages {
                    await page.show(in: browser)
                    await run.pause()
                    if page == .columnsMenu {
                        captureHeaderMenu(of: browser, run: run, look: look, window: main)
                    } else if page == .tabs {
                        // The new tab is in front; its window draws the tab bar.
                        await run.capture(page.rawValue, look, window: NSApp.keyWindow, area: .automatic)
                    } else if let id = page.windowID {
                        let own = NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue.contains(id) == true }
                        own?.makeKeyAndOrderFront(nil)
                        await run.pause(.seconds(0.3))
                        await run.capture(page.rawValue, look, window: own, area: .automatic)
                    } else {
                        // A sheet or a popover (the transfers) is a window of its own: the window's screen area is shot.
                        await run.capture(page.rawValue, look, window: main, area: .automatic)
                    }
                    await page.cleanUp(in: browser)
                }
                if browser.isEditingPath { browser.cancelEditingPath() }
            }
            if run.wants("log") {
                openWindow(id: KamiroApp.logID)
                await run.pause(.seconds(1))
                let log = NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue.contains(KamiroApp.logID) == true }
                await run.forEachAppearance { look in
                    await run.pause()
                    await run.capture("log", look, window: log)
                }
                log?.close()
                await run.pause(.seconds(0.4))
            }
            await run.shootSettings(tabs: SettingsTab.allCases.map(\.rawValue), open: { openSettings() },
                                    select: { app.settingsTab = SettingsTab(rawValue: $0) ?? .general },
                                    window: { WindowShot.otherWindow { $0.identifier?.rawValue.contains(KamiroApp.logID) != true } })
            run.finish()
        }
    }

    /// Opens the list header's right-click menu and shoots the window's screen area while
    /// it's open: the menu blocks this task, so a timer in the menu's run loop mode shoots.
    private static func captureHeaderMenu(of browser: BrowserModel, run: SnapshotRun, look: Appearance, window: NSWindow?) {
        guard let window else {
            print("SNAPSHOT no window")
            return
        }
        let url = run.url(Page.columnsMenu.rawValue, look)
        guard let table = browser.details?.table, let header = table.headerView, let menu = header.menu else {
            WindowShot.captureNow(window, to: url, area: .automatic, layout: run.layout)
            return
        }
        let timer = Timer(timeInterval: 0.8, repeats: false) { _ in
            MainActor.assumeIsolated {
                WindowShot.captureNow(window, to: url, area: .screen, layout: run.layout)
                browser.details?.table?.headerView?.menu?.cancelTracking()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        let column = table.column(withIdentifier: ListColumn.kind.identifier)
        let x = column >= 0 ? table.rect(ofColumn: column).minX + Space.lg : header.bounds.midX
        menu.popUp(positioning: nil, at: NSPoint(x: x, y: header.bounds.maxY), in: header)
    }
}
