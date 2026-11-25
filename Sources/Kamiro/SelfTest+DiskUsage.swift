import AppKit
import AppTestKit
import KamiroKit

extension SelfTest {
    // S-063: Show Disk Usage.
    static func diskUsage(browser: BrowserModel, seed: URL) async {
        func pause(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
        func windows() -> [NSWindow] {
            NSApp.windows.filter { $0.isVisible && $0.identifier?.rawValue.contains(KamiroApp.diskUsageID) == true }
        }
        let main = browser.details?.table?.window
        browser.go(to: seed, select: [seed.appending(path: "Photos").canonical])
        await browser.waitUntilLoaded()
        let menu = browser.details?.contextMenu(onItems: true).items.map(\.title) ?? []
        check("right-clicking a folder offers Show Disk Usage", menu.contains(String(localized: "Show Disk Usage")), "\(menu)")
        browser.selection = []
        MenuState.shared.activate(browser)
        check("File › Show Disk Usage works on the folder on screen", MenuState.shared.canShowDiskUsage && browser.diskUsageTarget == seed.canonical,
              "\(String(describing: browser.diskUsageTarget))")
        DiskUsageModel.latest = nil
        browser.showDiskUsage()
        for _ in 0..<100 where DiskUsageModel.latest?.state != .ready { await pause(0.1) }
        guard let model = DiskUsageModel.latest, let root = model.root else {
            check("Show Disk Usage measures the sample tree", false, "no map")
            return
        }
        let title = String(localized: "Disk Usage — \(FileManager.default.displayName(atPath: seed.path))")
        check("it opens “\(title)”", windows().map(\.title).contains(title), "\(windows().map(\.title))")
        let expected = (try? FolderSize.measure(seed)) ?? -1
        check("…with the same total as Properties", root.size == expected, "\(root.size) vs \(expected)")
        let big = root.children.first { $0.name == "10k" }
        check("…and a 10,000-file folder folds its smallest files into one tile",
              big?.children.contains(where: \.isSmallerItems) == true && (big?.children.count ?? 0) <= DiskUsage.keptFiles + 1)
        check("…with the folder’s own items at the top", root.url.path == seed.canonical.path
              && root.children.allSatisfy { $0.url.deletingLastPathComponent().canonical.path == seed.canonical.path })
        if let photos = root.children.first(where: { $0.name == "Photos" }) {
            model.zoom(into: photos)
            check("double-clicking Photos zooms into it", model.shown?.id == photos.id && model.trail.count == 2)
            model.zoom(toLevel: 0)
            check("the path bar goes back up", model.shown?.id == root.id)
        } else {
            check("the map has Photos", false, "\(root.children.map(\.name))")
        }
        if let notes = root.children.first(where: { $0.name == "Owl.jpg" }) {
            // Goes to the browser window used last.
            MenuState.shared.activate(browser)
            model.showInBrowser(notes)
            await browser.waitUntilLoaded()
            check("Show in Kamiro selects the item in the browser",
                  browser.folder == seed.canonical && browser.selection == [notes.url.canonical], "\(browser.selection)")
        }
        windows().forEach { $0.close() }
        main?.makeKeyAndOrderFront(nil)
        await pause(0.3)
    }
}
