import AppKit
import KamiroKit

/// M3, views (S-019 to S-024). Runs on the sample tree before the file actions change it.
extension SelfTest {
    static func views(browser: BrowserModel, seed: URL) async {
        func pause(_ seconds: Double = 0.3) async { try? await Task.sleep(for: .seconds(seconds)) }
        func open(_ path: String = "") async {
            browser.go(to: path.isEmpty ? seed : seed.appending(path: path))
            await browser.waitUntilLoaded()
            browser.focusList()
            await pause()
        }

        // S-019: icons with thumbnails.
        await open()
        browser.mode = .icons
        await pause(0.5)
        let grid = browser.grid?.grid
        check("⌘1 shows the folder as icons", grid?.numberOfItems(inSection: 0) == browser.items.count && grid?.window != nil,
              "\(grid?.numberOfItems(inSection: 0) ?? -1) of \(browser.items.count)")
        let owl = browser.items.first { $0.name == "Owl.jpg" }
        for _ in 0..<50 where owl.flatMap({ Thumbnails.shared.cached($0, size: IconSize.standard) }) == nil { await pause(0.1) }
        check("a picture shows its thumbnail", owl.flatMap { Thumbnails.shared.cached($0, size: IconSize.standard) } != nil)
        browser.selection = [seed.appending(path: "notes.md")]
        browser.beginRename()
        await pause()
        check("an icon's name renames in place", browser.grid?.renaming == seed.appending(path: "notes.md"))
        browser.grid?.rename?.end()
        await pause()

        let asked = Thumbnails.shared.requested
        await open("10k")
        await pause(0.5)
        let visible = browser.grid?.grid?.indexPathsForVisibleItems().count ?? 0
        let loaded = Thumbnails.shared.requested - asked
        check("thumbnails load only for the items on screen", visible > 0 && loaded <= visible, "\(loaded) asked, \(visible) on screen")
        if let grid = browser.grid?.grid, let scroll = grid.enclosingScrollView {
            let steps = 60
            let height = grid.frame.height - scroll.contentView.bounds.height
            let started = ContinuousClock.now
            for step in 1...steps {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: height * CGFloat(step) / CGFloat(steps)))
                scroll.reflectScrolledClipView(scroll.contentView)
                grid.window?.displayIfNeeded()
            }
            let each = (ContinuousClock.now - started) / steps
            check("10,000 icons scroll smoothly (under 16 ms a step)", height > 10_000 && each < .milliseconds(16), "\(each), \(Int(height)) pt")
        } else {
            check("10,000 icons scroll smoothly (under 16 ms a step)", false, "no grid")
        }
        browser.mode = .details
        await pause()
        check("⌘2 goes back to details", browser.details?.table?.window != nil)
    }
}
