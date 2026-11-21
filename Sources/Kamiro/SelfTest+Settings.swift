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
}
