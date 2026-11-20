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
    @Published private(set) var isReady = false
    @Published private(set) var mode: ViewMode = .details
    @Published private(set) var groupBy: GroupBy = .none
    /// The key window's list has the keyboard: Delete shortcuts go to it, not to a text field.
    @Published var listFocused = false
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
        isReady = browser.state == .ready
        mode = browser.mode
        groupBy = browser.groupBy
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
            Divider()
            Button("New Folder") { menu.browser?.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!menu.isReady)
            Menu("New File") {
                NewFileItems { menu.browser?.newFile($0) }
            }
            .disabled(!menu.isReady)
            Divider()
            Button("Rename") { menu.browser?.beginRename() }
                .disabled(!menu.hasSelection)
            // Disabled while a text field has the keyboard, so ⌘⌫ still deletes text there.
            Button("Move to Trash") { menu.browser?.trashSelection() }
                .keyboardShortcut(.delete)
                .disabled(!(menu.hasSelection && menu.listFocused))
            Button("Delete Immediately…") { menu.browser?.askDeleteImmediately() }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
                .disabled(!(menu.hasSelection && menu.listFocused))
        }
        CommandGroup(after: .pasteboard) {
            Button("Move Items Here") { menu.browser?.paste(move: true) }
                .keyboardShortcut("v", modifiers: [.command, .option])
                .disabled(!(menu.listFocused && menu.isReady))
        }
        CommandGroup(before: .toolbar) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Toggle(mode.title, isOn: Binding(get: { menu.mode == mode }, set: { if $0 { menu.browser?.mode = mode } }))
                    .keyboardShortcut(mode.key)
            }
            Divider()
            // Groups show in the details view.
            Menu("Group By") {
                ForEach(GroupBy.allCases, id: \.self) { group in
                    Toggle(group.title, isOn: Binding(get: { menu.groupBy == group }, set: { if $0 { menu.browser?.groupBy = group } }))
                }
            }
            .disabled(menu.mode != .details)
            Button("Use as Defaults") { menu.browser?.useAsDefaults() }
                .help("Show folders you haven't changed like this one")
            Divider()
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
