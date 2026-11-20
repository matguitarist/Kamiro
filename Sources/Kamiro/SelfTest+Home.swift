import AppKit
import KamiroKit

/// S-031 and S-032: the Home page and pinned folders.
extension SelfTest {
    static func homeAndPins(browser: BrowserModel, seed: URL) async {
        let pins = PinStore.shared
        // Start from the defaults, whatever an earlier run left.
        Prefs.defaults.removeObject(forKey: Prefs.pins)
        Prefs.defaults.removeObject(forKey: Prefs.hiddenSidebarSections)
        pins.reload()
        defer {
            Prefs.defaults.removeObject(forKey: Prefs.pins)
            Prefs.defaults.removeObject(forKey: Prefs.hiddenSidebarSections)
            pins.reload()
        }
        check("the Pinned section starts with Applications, Desktop, Documents and Downloads",
              pins.list.urls.map(\.lastPathComponent) == ["Applications", "Desktop", "Documents", "Downloads"])

        // S-032: pin from the menu, folders only, once.
        let projects = seed.appending(path: "Projects").canonical
        let photos = seed.appending(path: "Photos").canonical
        browser.go(to: seed, select: [projects])
        await browser.waitUntilLoaded()
        browser.selection = [projects]
        let menu = browser.contextMenu(onItems: true)
        check("a folder's right-click menu has Pin to Sidebar", menu.items.contains { $0.title == String(localized: "Pin to Sidebar") })
        check("every right-click command has an icon",
              menu.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.image != nil },
              menu.items.filter { !$0.isSeparatorItem && $0.image == nil }.map(\.title).joined(separator: ", "))
        browser.pinToSidebar()
        check("Pin to Sidebar adds the folder at the end", pins.list.urls.last == projects)
        check("…and the menu no longer offers it", browser.pinTargets.isEmpty
              && !browser.contextMenu(onItems: true).items.contains { $0.title == String(localized: "Pin to Sidebar") })
        browser.selection = [seed.appending(path: "notes.md").canonical]
        check("a file can't be pinned", browser.pinTargets.isEmpty
              && !browser.contextMenu(onItems: true).items.contains { $0.title == String(localized: "Pin to Sidebar") })
        pins.pin([photos], at: 0)
        pins.pin([seed.appending(path: "notes.md")])
        check("a drop between pins pins the folder there, and skips files", pins.list.urls.first == photos && !pins.list.contains(seed.appending(path: "notes.md")))
        pins.move(fromOffsets: [0], toOffset: pins.list.urls.count)
        check("dragging a pin reorders it", pins.list.urls.last == photos)
        check("pins are saved", Prefs.defaults.stringArray(forKey: Prefs.pins)?.last == photos.path)
        pins.unpin(photos)
        check("Unpin takes it out", !pins.list.contains(photos))
        pins.show(.tags, false)
        check("a sidebar part can be hidden, and stays hidden", !pins.shows(.tags)
              && Prefs.defaults.stringArray(forKey: Prefs.hiddenSidebarSections) == ["tags"])
        pins.show(.tags, true)

        // S-031: the Home page.
        browser.go(to: VirtualPlace.home.url)
        await browser.waitUntilLoaded()
        check("Go › Home shows the Home page", browser.place == .home && browser.title == String(localized: "Home")
              && browser.state == .ready && !browser.canGoUp)
        // The sample tree has a file dated in the future: the check's file is newer still.
        let newest = seed.appending(path: "Home check.txt").canonical
        try? Data("x".utf8).write(to: newest)
        try? FileManager.default.setAttributes([.modificationDate: Date.distantFuture], ofItemAtPath: newest.path)
        let recent = RecentFiles.walk(in: seed)
        try? FileManager.default.removeItem(at: newest)
        check("Home lists the newest files first", recent.first == newest, recent.prefix(3).map(\.path).joined(separator: ", "))
        check("Home shows each volume's free space", Volumes.mounted().contains { Volumes.space(at: $0.url).map { $0.total > 0 } ?? false })
        let items = NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items) ?? []
        check("Go › Home is ⇧⌘F", items.contains { $0.title == String(localized: "Home") && $0.keyEquivalent == "f"
              && $0.keyEquivalentModifierMask == [.command, .shift] })
        browser.goBack()
        await browser.waitUntilLoaded()
    }
}
