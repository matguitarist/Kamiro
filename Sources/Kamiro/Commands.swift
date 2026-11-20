import AppKit
import Combine
import KamiroKit
import SwiftUI

/// The key window's browser, mirrored for the menu bar: Commands don't observe @Observable models.
final class MenuState: ObservableObject {
    static let shared = MenuState()
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var canGoUp = false
    @Published private(set) var hasSelection = false
    private(set) weak var browser: BrowserModel?

    func activate(_ browser: BrowserModel) {
        self.browser = browser
        refresh(browser)
    }

    func refresh(_ browser: BrowserModel) {
        guard browser === self.browser else { return }
        canGoBack = browser.history.canGoBack
        canGoForward = browser.history.canGoForward
        canGoUp = browser.canGoUp
        hasSelection = !browser.selection.isEmpty
    }
}

struct KamiroCommands: Commands {
    @ObservedObject var menu: MenuState
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Prefs.showStatusBar, store: Prefs.defaults) private var showStatusBar = true

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: KamiroApp.browserID) }
                .keyboardShortcut("n")
            Divider()
            Button("Open") { menu.browser?.open() }
                .keyboardShortcut("o")
                .disabled(!menu.hasSelection)
            Button("Quick Look") { menu.browser?.quickLook?() }
                .keyboardShortcut("y")
                .disabled(!menu.hasSelection)
        }
        CommandGroup(after: .toolbar) {
            Button(showStatusBar ? "Hide Status Bar" : "Show Status Bar") { showStatusBar.toggle() }
                .keyboardShortcut("/")
            Button("Refresh") { menu.browser?.refresh() }
                .keyboardShortcut("r")
        }
        CommandMenu("Go") {
            Button("Back") { menu.browser?.goBack() }
                .keyboardShortcut("[")
                .disabled(!menu.canGoBack)
            Button("Forward") { menu.browser?.goForward() }
                .keyboardShortcut("]")
                .disabled(!menu.canGoForward)
            // ⌘↑ is handled by the list: as a menu shortcut it would also fire in the address field.
            Button("Enclosing Folder") { menu.browser?.goUp() }
                .disabled(!menu.canGoUp)
            Divider()
            ForEach(Pinned.defaults) { place in
                Button(place.title) { menu.browser?.go(to: place.url) }
                    .keyboardShortcut(place.key, modifiers: place.modifiers)
            }
            Divider()
            Button("Go to Folder…") { menu.browser?.beginEditingPath() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Edit Address") { menu.browser?.beginEditingPath() }
                .keyboardShortcut("l")
        }
        CommandGroup(before: .windowList) {
            Button("Log") { openWindow(id: KamiroApp.logID) }
                .keyboardShortcut("j", modifiers: [.command, .option])
            Divider()
        }
    }
}

/// Calls `onKey` when this view's window becomes the key window.
struct WindowObserver: NSViewRepresentable {
    let onKey: () -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onKey = onKey
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) { view.onKey = onKey }

    final class ObserverView: NSView {
        var onKey: (() -> Void)?
        private var token: (any NSObjectProtocol)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
            guard let window else { return }
            token = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                                           queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onKey?() }
            }
        }
    }
}
