import AppKit
import IOKit.pwr_mgt
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
        case deleteConfirm = "delete-confirm"

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
            case .transferProgress, .conflictSheet: browser.go(to: seed)
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
            default: return
            }
            try? await Task.sleep(for: .seconds(0.5))
        }
    }

    static func runIfRequested(app: AppModel, browser: BrowserModel, openSettings: OpenSettingsAction, openWindow: OpenWindowAction) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        // Snapshots never run against the real settings.
        guard Store.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE to a file in /tmp")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        Task {
            // A sleeping display gives screencapture nothing. Declaring user
            // activity wakes it; the assertion keeps it on until the run quits.
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
            if env["APP_SNAPSHOT_MIN"] != nil, let main {
                // The window clamps to its content's minimum size.
                main.setContentSize(NSSize(width: 1, height: 1))
                try? await Task.sleep(for: .seconds(0.5))
            }
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                for page in Page.allCases where only?.contains(page.rawValue) ?? true {
                    await page.show(in: browser)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/\(page.rawValue)-\(mode).png", window: main)
                    await page.cleanUp(in: browser)
                }
                if browser.isEditingPath { browser.cancelEditingPath() }
            }
            if only == nil || only?.contains("log") == true {
                openWindow(id: KamiroApp.logID)
                try? await Task.sleep(for: .seconds(1))
                let log = NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue.contains(KamiroApp.logID) == true }
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/log-\(mode).png", window: log)
                }
                log?.close()
                try? await Task.sleep(for: .seconds(0.4))
            }
            if only == nil || only?.contains("settings") == true {
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for tab in SettingsTab.allCases {
                        app.settingsTab = tab
                        try? await Task.sleep(for: .seconds(0.8))
                        let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet && $0.identifier?.rawValue.contains(KamiroApp.logID) != true }
                        capture(to: "\(dir)/settings-\(tab.rawValue)-\(mode).png", window: settings)
                    }
                }
            }
            print("SNAPSHOT done \(dir)")
            // An open sheet refuses terminate, and the run would wait forever.
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    /// Captures the real window with screencapture, so glass, sidebars, and
    /// materials look exactly as on screen. That needs Screen Recording
    /// permission for the app that started this one (your terminal, or Claude).
    /// Without it, falls back to drawing the view hierarchy, which leaves
    /// sidebars and glass blank.
    private static func capture(to path: String, window: NSWindow? = nil) {
        // Another app can hide this one while snapshots run (computer use hides
        // apps it does not control). Hidden windows cannot be captured.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            print("SNAPSHOT no window")
            return
        }
        // Active, like a window someone is using: real accent colors and focus rings.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let size = window.contentView?.bounds.size ?? .zero
        GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: size)
        try? FileManager.default.removeItem(atPath: path)
        // The first capture of a run sometimes misses the window. Try three times.
        // A sheet or a popover is a window of its own: shoot the screen area of the window instead.
        var arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
        if window.attachedSheet != nil || TransferCenter.shared.popoverShown, let top = NSScreen.screens.first?.frame.maxY {
            // Popovers can reach past the window's edge: take them in too.
            let popovers = NSApp.windows.filter { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
            let frame = popovers.reduce(window.frame) { $0.union($1.frame) }
            arguments = ["-x", "-R", "\(Int(frame.minX)),\(Int(top - frame.maxY)),\(Int(frame.width)),\(Int(frame.height))", path]
        }
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = arguments
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission, sidebars and glass are blank)")
        }
    }
}
