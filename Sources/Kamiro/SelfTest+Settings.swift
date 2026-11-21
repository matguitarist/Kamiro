import AppKit
import KamiroKit

/// S-040: Settings › Views.
extension SelfTest {
    static func viewsSettings(browser: BrowserModel, seed: URL) async {
        func pause(_ seconds: Double = 0.3) async { try? await Task.sleep(for: .seconds(seconds)) }
        check("Settings has a Views tab after General", SettingsTab.allCases.prefix(2) == [.general, .views])

        browser.go(to: seed)
        await browser.waitUntilLoaded()
        Store.views.change { $0.setFoldersFirst(false) }
        NotificationCenter.default.post(name: BrowserModel.foldersFirstChanged, object: nil)
        await pause()
        let firstFile = browser.items.firstIndex { !$0.isFolder } ?? .max
        let lastFolder = browser.items.lastIndex { $0.isFolder } ?? -1
        check("Folders on top off mixes folders and files in an open window", !browser.order.foldersFirst && firstFile < lastFolder,
              browser.items.prefix(6).map(\.name).joined(separator: ", "))
        Store.views.change { $0.setFoldersFirst(true) }
        NotificationCenter.default.post(name: BrowserModel.foldersFirstChanged, object: nil)
        await pause()
        let folders = browser.items.prefix { $0.isFolder }.count
        check("…and on puts them back on top", browser.order.foldersFirst && folders == browser.items.filter(\.isFolder).count)

        Store.views.change { $0.setStandardColumn(.created, shown: true) }
        browser.go(to: seed.appending(path: "Empty"))
        await browser.waitUntilLoaded()
        check("a column turned on in Settings › Views shows in a folder never changed", browser.columns.contains(.created), "\(browser.columns)")
        Store.views.change { $0.setStandardColumn(.created, shown: false) }
        browser.go(to: seed)
        await browser.waitUntilLoaded()
    }

    /// S-047: Settings › Menu hides actions and New File types from the right-click menu.
    static func menuSettings(browser: BrowserModel, seed: URL) async {
        func titles(_ menu: NSMenu) -> [String] { menu.items.filter { !$0.isSeparatorItem }.map(\.title) }
        check("Settings has a Menu tab", SettingsTab.allCases.contains(.menu))
        browser.go(to: seed)
        await browser.waitUntilLoaded()
        browser.selection = [seed.appending(path: "Guide.pdf").canonical]
        let before = titles(browser.contextMenu(onItems: true))
        var choices = MenuChoices()
        choices.show(.tags, false)
        choices.show(.copyInfo, false)
        for template in FileTemplate.all where template.group != .basic { choices.show(template, false) }
        choices.save()
        let after = titles(browser.contextMenu(onItems: true))
        let gone = [String(localized: "Tags"), String(localized: "Copy Info")]
        check("hidden actions leave the right-click menu, the rest stays",
              gone.allSatisfy(before.contains) && !gone.contains(where: after.contains) && after.count == before.count - 2, "\(after)")
        let newFile = browser.contextMenu(onItems: false).items.first { $0.title == String(localized: "New File") }?.submenu
        let types = newFile?.items.filter { !$0.isSectionHeader }.count ?? 0
        check("New File lists only the types left", types == FileTemplate.all.filter { $0.group == .basic }.count, "\(types) types")
        choices.show(.newFile, false)
        choices.save()
        check("New File can go too", !titles(browser.contextMenu(onItems: false)).contains(String(localized: "New File")))
        MenuChoices().save()
        check("Show All brings everything back", titles(browser.contextMenu(onItems: true)) == before)
        browser.selection = []
    }
}
