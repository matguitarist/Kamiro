import AppKit
import AppTestKit
import KamiroKit
import LogKitUI
import SwiftUI

// Kamiro
//   Kamiro                          the app, with its settings in ~/Library/Application Support/Kamiro
//   APP_STORE=<file> Kamiro         settings in <file> (in /tmp) and the log next to it; never touches the real ones
//   APP_SNAPSHOT=<dir> Kamiro       save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   APP_SEED=1 Kamiro               with APP_STORE: sample log lines; windows open on /tmp/Kamiro-seed (tools/seed-tree.sh)
//   Kamiro --selftest               run the self-test on a /tmp store and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> Kamiro          run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 Kamiro               draw the 8 pt grid and the layout probes over the window

@main
struct KamiroApp: App {
    static let browserID = "browser"
    static let logID = "log"
    static let propertiesID = "properties"
    static let diskUsageID = "disk-usage"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(log: Store.log)

    init() {
        // Test runs find iCloud Drive and a sync folder in /tmp/Kamiro-home (tools/seed-tree.sh).
        if Store.isOverridden { Cloud.configure(home: Store.cloudHome, fakeStatuses: true) }
    }

    var body: some Scene {
        WindowGroup(id: Self.browserID, for: WindowStart.self) { $start in
            ContentView(start: start?.url ?? Store.startFolder, select: start?.select)
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 760, minHeight: 440)
        }
        .defaultSize(width: 1080, height: 680)
        .windowToolbarStyle(.unified)
        // Folders and files sent from outside go to ExternalOpen, not to a new empty window.
        .handlesExternalEvents(matching: [])
        .commands {
            SidebarCommands()
            ToolbarCommands()
            KamiroCommands(menu: MenuState.shared)
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updater.shared.checkForUpdates() }
                    .disabled(!Updater.shared.isAvailable)
            }
        }

        WindowGroup(id: Self.propertiesID, for: URL.self) { $url in
            if let url { PropertiesView(url: url).themed() }
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commandsRemoved()

        WindowGroup(id: Self.diskUsageID, for: URL.self) { $url in
            if let url { DiskUsageView(url: url).themed() }
        }
        .defaultSize(width: 960, height: 620)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commandsRemoved()

        Window("Log", id: Self.logID) {
            LogWindow()
                .environment(model)
                .themed()
                .frame(minWidth: 720, minHeight: 420)
        }
        .defaultSize(width: 900, height: 560)
        .commandsRemoved()

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Folders and files sent by other apps, the kamiro command (S-039), or a drop on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        ExternalOpen.open(urls)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        _ = Updater.shared
        // Only Convert needs to know, so it waits behind the window.
        _ = VolumeStore.shared
        Task(priority: .utility) { await ToolStore.shared.refresh() }
        Store.log.post(.info, "Kamiro \(UpdateSettings.version) started", source: "App")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        Store.log.flushFile()
        SelfTest.exitIfRequested()
    }
}

/// Where Kamiro keeps its own files: ~/Library/Application Support/Kamiro/settings.json,
/// and its log in ~/Library/Logs/Kamiro. With APP_STORE set (a file in /tmp), both move
/// there, for tests, snapshots, and the self-test.
enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, self-test).
    static var isOverridden: Bool { TestRun.isTestRun() }

    static var folder: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Kamiro", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// APP_STORE outside /tmp quits with 1 before anything is read or written.
    static var url: URL {
        TestRun.store() ?? folder.appending(path: "settings.json")
    }

    /// The app's log: next to APP_STORE in a test run, ~/Library/Logs/Kamiro otherwise.
    static var logURL: URL {
        isOverridden ? url.deletingPathExtension().appendingPathExtension("log") : LogStore.defaultFileURL(app: "Kamiro")
    }

    static let log = LogStore(fileURL: logURL)

    /// Each folder's view (S-021): next to APP_STORE in a test run.
    static let views = ViewStore(url: isOverridden
        ? url.deletingPathExtension().appendingPathExtension("views.json")
        : folder.appending(path: "views.json"))

    /// The sample tree snapshots and the self-test browse (tools/seed-tree.sh).
    static let seedFolder = URL(filePath: "/tmp/Kamiro-seed")
    /// The home test runs look for iCloud Drive and sync folders in (tools/seed-tree.sh).
    static let cloudHome = URL(filePath: "/tmp/Kamiro-home")

    /// Where a new window or tab opens: Settings › General's choice, the Home page unless changed
    /// (S-031, S-040); in a test run that hasn't chosen, the sample tree.
    static var startFolder: URL {
        let stored = Prefs.defaults.string(forKey: Prefs.newWindowStart)
        if isOverridden, stored == nil, FileManager.default.fileExists(atPath: seedFolder.path) { return seedFolder }
        return StartPlace(stored: stored).url(home: isOverridden ? cloudHome : FileManager.default.homeDirectoryForCurrentUser)
    }
}
