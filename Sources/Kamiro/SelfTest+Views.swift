import AppKit
import KamiroKit
import Quartz

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

        // Each folder has its own view (S-021): the big folder is shown as icons too.
        await open("10k")
        let asked = Thumbnails.shared.requested
        browser.mode = .icons
        await pause(0.5)
        let visible = browser.grid?.grid?.indexPathsForVisibleItems().count ?? 0
        let loaded = Thumbnails.shared.requested - asked
        // The grid prepares a row or so beyond the edge; 10,000 files must not all be read.
        check("thumbnails load only for the items on screen", visible > 0 && loaded <= visible * 2, "\(loaded) asked, \(visible) on screen")
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
        await open()
        browser.mode = .details

        await columns(browser: browser, seed: seed, pause: pause, open: open)
        await chosenColumns(browser: browser, seed: seed, pause: pause, open: open)
    }

    // S-021: choose, move and sort columns, per folder.
    private static func chosenColumns(browser: BrowserModel, seed: URL, pause: (Double) async -> Void, open: (String) async -> Void) async {
        await open("")
        guard let table = browser.details?.table, let menu = table.headerView?.menu else {
            check("the header has a right-click menu of columns", false)
            return
        }
        menu.delegate?.menuNeedsUpdate?(menu)
        let titles = menu.items.map(\.title)
        check("the header's right-click menu lists every column but Name",
              titles == ListColumn.allCases.filter { $0 != .name }.map(\.title), "\(titles)")
        if let created = menu.items.first(where: { $0.title == ListColumn.created.title }), let action = created.action {
            NSApp.sendAction(action, to: created.target, from: created)
        }
        await pause(0.3)
        let visible = { table.tableColumns.filter { !$0.isHidden }.map(\.identifier.rawValue) }
        check("choosing Date Created shows it", visible() == ["name", "modified", "size", "kind", "created"], "\(visible())")
        table.moveColumn(3, toColumn: 1)
        await pause(0.3)
        check("a column dragged left stays there", browser.columns == [.name, .kind, .modified, .size, .created], "\(browser.columns)")
        browser.order = ItemOrder(key: .created, ascending: false)
        await pause(0.3)

        await open("Photos")
        check("a folder never changed shows the default columns and sort",
              visible() == ["name", "modified", "size", "kind"] && browser.order == ItemOrder(), "\(visible())")
        browser.goBack()
        await browser.waitUntilLoaded()
        await pause(0.3)
        check("going back shows the folder's own columns and sort",
              visible() == ["name", "kind", "modified", "size", "created"]
              && table.sortDescriptors.first?.key == SortKey.created.rawValue && browser.order.ascending == false, "\(visible())")
        let saved = (try? String(contentsOf: Store.views.url, encoding: .utf8)) ?? ""
        check("the folder's view is saved for the next launch", saved.contains(seed.path) && saved.contains("created"))

        // Back to the default, for the checks after these.
        browser.toggleColumn(.created)
        browser.columns = ListColumn.standard
        browser.order = ItemOrder()
        await pause(0.3)
    }

    // S-020: columns.
    private static func columns(browser: BrowserModel, seed: URL, pause: (Double) async -> Void, open: (String) async -> Void) async {
        func url(_ path: String) -> URL { seed.appending(path: path).canonical }
        await open("")
        browser.mode = .columns
        await pause(0.5)
        let columns = browser.columnView
        let view = columns?.browser
        check("⌘3 shows columns that start at the window's folder", view?.window != nil && columns?.root?.url == seed)
        browser.go(to: url("Projects/Kamiro"), select: [url("Projects/Kamiro/README.md")])
        await browser.waitUntilLoaded()
        await pause(0.5)
        func previews(_ view: NSView) -> Bool { view is QLPreviewView || view.subviews.contains(where: previews) }
        check("a file deep down opens every column to it, with its preview last",
              view?.selectedColumn == 2 && view.map(previews) == true, "column \(view?.selectedColumn ?? -1)")
        let first = view?.width(ofColumn: 0) ?? 0
        let third = view?.width(ofColumn: 2) ?? 0
        check("columns size to their longest name, up to a limit", first == 360 && third >= 160 && third < first, "\(first), \(third)")

        browser.go(to: seed, select: [url("Projects")])
        await browser.waitUntilLoaded()
        await pause(0.5)
        view?.window?.makeKeyAndOrderFront(nil)
        browser.focusList()
        await pause(0.3)
        let right = String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        if let window = view?.window, let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function],
                                                                   timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                                   characters: right, charactersIgnoringModifiers: right,
                                                                   isARepeat: false, keyCode: 124) {
            window.firstResponder?.keyDown(with: event)
        }
        await browser.waitUntilLoaded()
        await pause(0.5)
        check("→ moves into the next column", browser.folder == url("Projects") && browser.selection == [url("Projects/Kamiro")],
              "\(browser.folder.path) \(browser.selection.map(\.lastPathComponent))")
        check("the columns have the keyboard, so Delete and Cut go to them", view?.hasKeyboard == true && MenuState.shared.listFocused)
        browser.selection = [url("Projects/notes.md")]
        await pause(0.3)
        browser.beginRename()
        await pause(0.3)
        let field = view?.window?.firstResponder as? NSTextView
        check("an item's name renames in place in its column, with just the name to edit",
              columns?.renaming == url("Projects/notes.md") && field?.string == "notes.md"
              && field?.selectedRange() == NSRange(location: 0, length: 5), field?.string ?? "no field")
        field?.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        await pause(0.3)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url("Projects").path)) ?? []
        check("Escape keeps the old name", Set(names) == ["Kamiro", "Website", "notes.md"] && columns?.renaming == nil,
              "\(names), renaming \(columns?.renaming?.lastPathComponent ?? "nothing")")
        browser.beginRename()
        await pause(0.3)
        (view?.window?.firstResponder as? NSTextView)?.string = "notes old.md"
        (view?.window?.firstResponder as? NSTextView)?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        await pause(0.5)
        await browser.waitUntilLoaded()
        check("Return saves the new name", FileManager.default.fileExists(atPath: url("Projects/notes old.md").path))
        FileUndo.manager.undo()
        await pause(0.5)
        await browser.waitUntilLoaded()
        browser.mode = .details
        await open("")
        browser.mode = .details
        await pause(0.3)
    }
}
