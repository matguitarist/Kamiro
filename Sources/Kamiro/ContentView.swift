import LogKitUI
import SwiftUI

/// One browser window: sidebar, toolbar with the address bar, the list, the status bar.
struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var browser: BrowserModel
    @AppStorage(Prefs.showStatusBar, store: Prefs.defaults) private var showStatusBar = true

    init(start: URL) {
        _browser = State(initialValue: BrowserModel(start: start, log: Store.log))
    }

    var body: some View {
        NavigationSplitView {
            Sidebar(browser: browser)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 280)
        } detail: {
            BrowserView(model: browser, showStatusBar: showStatusBar)
        }
        .navigationTitle(browser.title)
        .toolbar { BrowserToolbar(model: browser) }
        .background(WindowObserver { MenuState.shared.activate(browser) })
        .onAppear {
            browser.openWindow = { url in openWindow(id: KamiroApp.browserID, value: url) }
            browser.startIfNeeded()
            MenuState.shared.activate(browser)
        }
        .task {
            // The first window runs the agent modes.
            guard !AgentModes.started else { return }
            AgentModes.started = true
            await browser.waitUntilLoaded()
            browser.focusList()
            SelfTest.runIfRequested(app: app, browser: browser)
            Snapshot.runIfRequested(app: app, browser: browser, openSettings: openSettings, openWindow: openWindow)
        }
    }
}

enum AgentModes {
    static var started = false
}

/// The Log window (Window › Log, ⌥⌘J).
struct LogWindow: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        LogViewer(model: app.logViewer)
            .navigationTitle("Log")
    }
}
