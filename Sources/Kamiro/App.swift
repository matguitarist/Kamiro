import AppKit
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

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(log: Store.log)

    init() {
        // Test runs find iCloud Drive and a sync folder in /tmp/Kamiro-home (tools/seed-tree.sh).
        if Store.isOverridden { Cloud.configure(home: Store.cloudHome, fakeStatuses: true) }
    }

    var body: some Scene {
        WindowGroup(id: Self.browserID, for: WindowStart.self) { $start in
            ContentView(start: start?.url ?? Store.startFolder)
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 760, minHeight: 440)
        }
        .defaultSize(width: 1080, height: 680)
        .windowToolbarStyle(.unified)
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        _ = Updater.shared
        Task { await ToolStore.shared.refresh() }
        Store.log.post(.info, "Kamiro \(UpdateSettings.version) started", source: "App")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        Store.log.flushFile()
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Where Kamiro keeps its own files: ~/Library/Application Support/Kamiro/settings.json,
/// and its log in ~/Library/Logs/Kamiro. With APP_STORE set (a file in /tmp), both move
/// there, for tests, snapshots, and the self-test.
enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, self-test).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var folder: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Kamiro", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return folder.appending(path: "settings.json")
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

    /// Where a new window opens: the Home page (S-031), or the sample tree in a test run.
    static var startFolder: URL {
        if isOverridden, FileManager.default.fileExists(atPath: seedFolder.path) { return seedFolder }
        return VirtualPlace.home.url
    }
}
