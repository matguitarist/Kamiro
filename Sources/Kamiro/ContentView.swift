import KamiroKit
import LogKitUI
import SwiftUI

/// One browser window: sidebar, toolbar with the address bar, the list, the status bar.
struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var browser: BrowserModel
    @AppStorage(Prefs.showStatusBar, store: Prefs.defaults) private var showStatusBar = true
    @AppStorage(Prefs.showInspector, store: Prefs.defaults) private var showInspector = false
    @FocusState private var filterFocused: Bool

    init(start: URL) {
        _browser = State(initialValue: BrowserModel(start: start, log: Store.log))
    }

    var body: some View {
        NavigationSplitView {
            Sidebar(browser: browser)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 280)
        } detail: {
            BrowserView(model: browser, showStatusBar: showStatusBar)
                .inspector(isPresented: $showInspector) {
                    InspectorView(model: browser)
                        .inspectorColumnWidth(min: 220, ideal: 260, max: 400)
                }
        }
        // Filter this folder by name as you type (S-028); Escape clears it.
        .searchable(text: $browser.filterText, placement: .toolbar, prompt: Text("Filter by Name"))
        .searchFocused($filterFocused)
        .onChange(of: browser.filterFocusToken) { filterFocused = true }
        .navigationTitle(browser.title)
        // The address bar shows where the window is; the title stays for the Window menu and Mission Control.
        .toolbar(removing: .title)
        .toolbar { BrowserToolbar(model: browser) }
        .background(WindowObserver { MenuState.shared.activate(browser) })
        .sheet(item: conflictBinding) { question in
            ConflictSheet(question: question)
        }
        .alert(deleteTitle, isPresented: deleteShown) {
            Button("Delete", role: .destructive) { browser.deleteImmediately() }
            Button("Cancel", role: .cancel) { browser.pendingDelete = nil }
        } message: {
            Text("You can’t undo this action.")
        }
        .alert(browser.pendingExtension?.title ?? "", isPresented: extensionShown) {
            Button(browser.pendingExtension?.useTitle ?? "") { browser.answerExtension(use: true) }
            Button(browser.pendingExtension?.keepTitle ?? "", role: .cancel) { browser.answerExtension(use: false) }
        } message: {
            Text("If you make this change, the file may open in a different app.")
        }
        .onAppear {
            browser.openWindow = { url in openWindow(id: KamiroApp.browserID, value: url) }
            browser.openProperties = { url in openWindow(id: KamiroApp.propertiesID, value: url) }
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

extension ContentView {
    /// Closing the sheet any other way than its buttons stops the transfer.
    private var conflictBinding: Binding<ConflictQuestion?> {
        Binding {
            browser.conflicts.first
        } set: { question in
            if question == nil { browser.conflicts.first?.answer(ConflictAnswer(.stop)) }
        }
    }

    private var deleteShown: Binding<Bool> {
        Binding { browser.pendingDelete != nil } set: { if !$0 { browser.pendingDelete = nil } }
    }

    private var extensionShown: Binding<Bool> {
        Binding { browser.pendingExtension != nil } set: { _ in }
    }

    private var deleteTitle: String {
        let count = browser.pendingDelete?.count ?? 0
        if count == 1, let name = browser.pendingDelete?.first?.lastPathComponent {
            return String(localized: "Delete “\(name)” Immediately?")
        }
        return String(localized: "Delete \(count) Items Immediately?")
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
