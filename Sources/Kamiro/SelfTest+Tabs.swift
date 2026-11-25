import AppKit
import AppTestKit
import KamiroKit

/// S-030: tabs.
extension SelfTest {
    static func tabs(browser: BrowserModel, seed: URL) async {
        func pause(_ seconds: Double = 0.3) async { try? await Task.sleep(for: .seconds(seconds)) }
        func tabs(_ count: Int) async {
            for _ in 0..<30 where (main?.tabbedWindows?.count ?? 1) != count { await pause(0.1) }
        }
        browser.go(to: seed)
        await browser.waitUntilLoaded()
        let main = browser.details?.table?.window
        main?.makeKeyAndOrderFront(nil)
        await pause()

        let items = NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items) ?? []
        let newTab = items.first { $0.keyEquivalent == "t" && $0.keyEquivalentModifierMask == .command }
        check("⌘T is File › New Tab", newTab?.title == String(localized: "New Tab"), newTab?.title ?? "missing")
        if let newTab, let menu = newTab.menu { menu.performActionForItem(at: menu.index(of: newTab)) }
        await tabs(2)
        let opened = NSApp.keyWindow
        check("⌘T opens a tab in the same window, in front", main?.tabbedWindows?.count == 2 && opened !== main && Tabs.isBrowser(opened),
              "\(main?.tabbedWindows?.count ?? 0) tabs")
        opened?.close()
        await tabs(1)

        // ⌘-double-click opens the folder in a tab (the list passes newTab for ⌘); twice gives two tabs.
        let projects = seed.appending(path: "Projects")
        browser.open([projects], newTab: true)
        await tabs(2)
        browser.open([projects], newTab: true)
        await tabs(3)
        await pause(0.5)
        let others = (main?.tabbedWindows ?? []).filter { $0 !== main }
        check("⌘-double-click opens a folder in a new tab, each time", others.count == 2 && others.allSatisfy { $0.title == "Projects" },
              "\(others.map(\.title))")
        check("…and the first tab stays where it was", browser.folder == seed)

        // Dragging a tab out does what Window › Move Tab to New Window does.
        if let tab = others.first {
            tab.moveTabToNewWindow(nil)
            await pause(0.5)
            check("a tab moves out to a window of its own", main?.tabbedWindows?.contains(tab) != true && tab.isVisible)
        }
        others.forEach { $0.close() }
        await tabs(1)
        main?.makeKeyAndOrderFront(nil)
        await pause()
    }
}
