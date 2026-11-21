import AppKit
import SwiftUI

/// What a browser window opens on. The id makes each request a new window: SwiftUI brings
/// forward a window already showing the same value, so two tabs on one folder need two values.
struct WindowStart: Codable, Hashable {
    var url: URL
    /// An item to show selected there (a file another app or the kamiro command sent).
    var select: URL?
    var id = UUID()
}

/// Tabs (S-030) are AppKit's own window tabs: a new browser window joins the front window's
/// tab group, and dragging a tab out, Merge All Windows and the tab bar come with them.
@MainActor
enum Tabs {
    /// The window the next browser windows join, and how many are on their way.
    private static weak var host: NSWindow?
    private static var waiting = 0

    static func isBrowser(_ window: NSWindow?) -> Bool {
        window?.identifier?.rawValue.contains(KamiroApp.browserID) == true
    }

    /// The browser window in front: a new tab joins it.
    static var front: NSWindow? {
        [NSApp.keyWindow, NSApp.mainWindow].first { isBrowser($0) } ?? nil
    }

    /// Opens a browser window on `url` (the start folder when nil), as a tab of `window` when given.
    static func open(_ url: URL?, besides window: NSWindow?, with openWindow: OpenWindowAction) {
        if let window {
            if host !== window { waiting = 0 }
            host = window
            waiting += 1
        }
        if let url {
            openWindow(id: KamiroApp.browserID, value: WindowStart(url: url))
        } else {
            openWindow(id: KamiroApp.browserID)
        }
    }

    /// A browser window's content arrived: it joins the waiting tab group, if any.
    static func adopt(_ window: NSWindow) {
        guard waiting > 0, let host, host !== window, host.isVisible else { return }
        waiting -= 1
        if waiting == 0 { Self.host = nil }
        host.addTabbedWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
    }
}

/// Puts this view's window into the tab group it was opened for.
struct TabJoiner: NSViewRepresentable {
    func makeNSView(context: Context) -> JoinerView { JoinerView() }
    func updateNSView(_ view: JoinerView, context: Context) {}

    final class JoinerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            MainActor.assumeIsolated { Tabs.adopt(window) }
        }
    }
}
