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
        await groups(browser: browser, seed: seed, pause: pause, open: open)
        await folderSizes(browser: browser, seed: seed, pause: pause, open: open)
        await hiddenFiles(browser: browser, seed: seed, pause: pause, open: open)
        await inspector(browser: browser, seed: seed, pause: pause, open: open)
        await properties(browser: browser, seed: seed, pause: pause, open: open)
    }

    // S-026: Properties.
    private static func properties(browser: BrowserModel, seed: URL, pause: (Double) async -> Void, open: (String) async -> Void) async {
        func url(_ path: String) -> URL { seed.appending(path: path).canonical }
        func windows() -> [NSWindow] {
            NSApp.windows.filter { $0.isVisible && $0.identifier?.rawValue.contains(KamiroApp.propertiesID) == true }
        }
        func closeAll() { windows().forEach { $0.close() } }
        let main = browser.details?.table?.window
        await open("")
        browser.selection = [url("Owl.jpg")]
        let menuItem = NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items)
            .first { $0.keyEquivalent == "i" && $0.keyEquivalentModifierMask == .command }
        check("⌘I is File › Properties", menuItem?.title == String(localized: "Properties"), menuItem?.title ?? "missing")
        browser.showProperties()
        await pause(1.2)
        let title = String(localized: "\(url("Owl.jpg").lastPathComponent) Properties")
        check("⌘I opens “Owl.jpg Properties”", windows().map(\.title) == [title], "\(windows().map(\.title))")
        check("…with the file's size in bytes", PropertiesProbe.shown[url("Owl.jpg")]?.contains("138") == true
              || PropertiesProbe.shown[url("Owl.jpg")]?.contains("(") == true, PropertiesProbe.shown[url("Owl.jpg")] ?? "nothing")
        closeAll()
        main?.makeKeyAndOrderFront(nil)
        await pause(0.4)

        browser.selection = [url("Photos")]
        browser.focusList()
        await pause(0.3)
        let altReturn = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .option, timestamp: 0,
                                         windowNumber: main?.windowNumber ?? 0, context: nil, characters: "\r",
                                         charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)
        if let altReturn { _ = FileKeys.handle(altReturn, model: browser) }
        for _ in 0..<30 where PropertiesProbe.shown[url("Photos")]?.contains(",") != true { await pause(0.1) }
        let expected = (try? FolderSize.summary(url("Photos")))?.items ?? -1
        let shown = PropertiesProbe.shown[url("Photos")] ?? "nothing"
        check("⌥↩ opens Properties, and a folder shows its size with the item count",
              windows().count == 1 && shown.contains("\(expected)"), "\(shown), expected \(expected) items")
        closeAll()
        main?.makeKeyAndOrderFront(nil)

        let file = url("notes.md")
        try? ItemFlags.setLocked(true, file)
        let lockedOnDisk = ItemFlags.isLocked(file) && (try? Data("x".utf8).write(to: file)) == nil
        try? ItemFlags.setLocked(false, file)
        check("Locked locks the file on disk, and unlocking puts it back", lockedOnDisk && !ItemFlags.isLocked(file))
        await pause(0.3)
    }

    // S-025: the inspector.
    private static func inspector(browser: BrowserModel, seed: URL, pause: (Double) async -> Void, open: (String) async -> Void) async {
        func url(_ path: String) -> URL { seed.appending(path: path).canonical }
        let window = browser.details?.table?.window
        Prefs.defaults.set(false, forKey: Prefs.showInspector)
        await open("")
        browser.selection = [url("Owl.jpg")]
        let menuItem = NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items)
            .first { $0.keyEquivalent == "i" && $0.keyEquivalentModifierMask == [.command, .option] }
        check("⌥⌘I is in the View menu", menuItem?.title == String(localized: "Show Inspector"), menuItem?.title ?? "missing")
        let fullWidth = browser.details?.table?.enclosingScrollView?.frame.width ?? 0
        Prefs.defaults.set(true, forKey: Prefs.showInspector)
        await pause(1.2)
        let narrowed = browser.details?.table?.enclosingScrollView?.frame.width ?? 0
        let clip = browser.details?.table?.enclosingScrollView?.contentView.bounds.width ?? 0
        let lastEdge = browser.details?.table.map { table in
            table.tableColumns.filter { !$0.isHidden }.reduce(0) { $0 + $1.width + table.intercellSpacing.width }
        } ?? .infinity
        check("the inspector takes room from the list, and every column still shows", narrowed < fullWidth - 150 && lastEdge <= clip + 1,
              "\(fullWidth) → \(narrowed), columns \(lastEdge) in \(clip)")
        let shown = InspectorProbe.shown
        check("the inspector shows the selected item's name, kind, size and dimensions",
              shown.first == "Owl.jpg" && [String(localized: "Kind"), String(localized: "Size"), String(localized: "Dimensions")]
                .allSatisfy(shown.contains), "\(shown)")
        browser.selection = []
        await pause(0.8)
        check("with nothing selected the inspector shows the folder", InspectorProbe.shown.first == seed.lastPathComponent,
              "\(InspectorProbe.shown)")
        let rows = InspectorFacts.rows(item: FileItem(url: url("notes.md"), name: "notes.md", isFolder: false, size: 47),
                                       size: 47, media: MediaFacts(), tags: [])
        check("facts that don't apply are left out", !rows.contains { $0.label == String(localized: "Dimensions") }
              && rows.first?.label == String(localized: "Kind"))
        Prefs.defaults.set(false, forKey: Prefs.showInspector)
        await pause(0.5)
        let restored = browser.details?.table?.enclosingScrollView?.frame.width ?? 0
        check("⌥⌘I again hides it", abs(restored - fullWidth) < 2 && window?.isVisible == true, "\(restored) vs \(fullWidth)")
    }

    // S-024: hidden files.
    private static func hiddenFiles(browser: BrowserModel, seed: URL, pause: (Double) async -> Void, open: (String) async -> Void) async {
        func url(_ path: String) -> URL { seed.appending(path: path).canonical }
        HiddenFiles.set(false)
        await open("")
        check("hidden items stay out of the list by default",
              !browser.items.contains { $0.name == ".hidden-notes" || $0.name == "Flagged Hidden.txt" })
        HiddenFiles.toggle()
        await pause(0.2)
        await browser.waitUntilLoaded()
        await pause(0.3)
        func dimmed(_ path: String) -> Bool {
            guard let table = browser.details?.table, let row = browser.details?.rowOf[url(path)] else { return false }
            return table.view(atColumn: 0, row: row, makeIfNecessary: true)?.alphaValue == 0.5
        }
        check("⇧⌘. shows dotfiles and flagged hidden items at half opacity",
              dimmed(".hidden-notes") && dimmed("Flagged Hidden.txt") && !dimmed("notes.md"))
        let other = BrowserModel(start: seed, log: Store.log)
        other.startIfNeeded()
        await other.waitUntilLoaded()
        check("the choice is the same in every window", other.items.contains { $0.name == ".hidden-notes" })
        // SwiftUI fills a menu when it opens.
        let menus = NSApp.mainMenu?.items.compactMap(\.submenu) ?? []
        menus.forEach { $0.delegate?.menuNeedsUpdate?($0) }
        await pause(0.2)
        let hiddenItems = menus.flatMap(\.items).filter { $0.keyEquivalent == "." }.map(\.title)
        check("the View menu offers to hide them again",
              hiddenItems.contains(String(localized: "Hide Hidden Files")) && MenuState.shared.showsHidden, "\(hiddenItems)")
        HiddenFiles.toggle()
        await pause(0.2)
        await browser.waitUntilLoaded()
        check("⇧⌘. again hides them", !browser.items.contains { $0.name == ".hidden-notes" })
    }

    // S-023: folder sizes.
    private static func folderSizes(browser: BrowserModel, seed: URL, pause: (Double) async -> Void, open: (String) async -> Void) async {
        func url(_ path: String) -> URL { seed.appending(path: path).canonical }
        func allocated(_ folder: URL) -> Int64 {
            let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
            return (files?.allObjects as? [URL] ?? []).reduce(0) {
                $0 + Int64((try? $1.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
            }
        }
        let photos = FileItem(url: url("Photos"), name: "Photos", isFolder: true)
        check("a folder shows “—” until it's measured", DetailsCoordinator.sizeText(photos, sizes: [:]) == "—")
        await open("")
        for _ in 0..<50 where browser.isMeasuring || browser.folderSizes[url("Photos")] == nil { await pause(0.1) }
        let measured = browser.folderSizes[url("Photos")]
        check("folders get their size in the background", measured == allocated(url("Photos")) && (measured ?? 0) > 100_000,
              "\(measured ?? -1) vs \(allocated(url("Photos")))")
        let row = browser.details?.rowOf[url("Photos")] ?? -1
        let column = browser.details?.table?.column(withIdentifier: ListColumn.size.identifier) ?? -1
        let shown = (browser.details?.table?.view(atColumn: column, row: row, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue
        check("a folder Kamiro can't open keeps its “—”", browser.folderSizes[url("Locked")] == nil && !browser.isMeasuring)
        check("…and the Size column shows it", shown == ByteCountFormatter.string(fromByteCount: measured ?? 0, countStyle: .file), shown ?? "no cell")

        browser.order = ItemOrder(key: .size, ascending: false)
        await pause(0.6)
        let folders = browser.items.filter(\.isFolder).map(\.name)
        check("sorting by size puts the biggest folder first", folders.first == "Photos"
              && folders.firstIndex(of: "Projects") ?? 0 < folders.firstIndex(of: "Empty") ?? 0, "\(folders)")

        try? Data(repeating: 9, count: 2_000_000).write(to: url("Photos/Big.raw"))
        for _ in 0..<80 where (browser.folderSizes[url("Photos")] ?? 0) < (measured ?? 0) + 2_000_000 { await pause(0.1) }
        check("a folder's size follows changes made inside it", (browser.folderSizes[url("Photos")] ?? 0) >= (measured ?? 0) + 2_000_000,
              "\(browser.folderSizes[url("Photos")] ?? -1)")
        try? FileManager.default.removeItem(at: url("Photos/Big.raw"))
        browser.order = ItemOrder()
        await pause(0.3)

        browser.go(to: url("Projects"))
        await browser.waitUntilLoaded()
        await pause(0.1)
        browser.go(to: url("Empty"))
        await browser.waitUntilLoaded()
        check("leaving a folder stops measuring it", !browser.isMeasuring && browser.folderSizes.isEmpty)
    }

    // S-022: groups with headers that fold.
    private static func groups(browser: BrowserModel, seed: URL, pause: (Double) async -> Void, open: (String) async -> Void) async {
        await open("")
        browser.groupBy = .modified
        await pause(0.3)
        var headers: [GroupHeader] {
            browser.details?.rows.compactMap { if case .header(let header) = $0 { header } else { nil } } ?? []
        }
        let rows = browser.details?.rows ?? []
        let first = headers.first
        check("Group By Date Modified puts a header before each group, newest first",
              headers.count >= 2 && rows.count == browser.items.count + headers.count
              && headers.reduce(0) { $0 + $1.count } == browser.items.count
              && { if case .header = rows.first { true } else { false } }(), headers.map(\.title).joined(separator: ", "))
        check("headers can't be selected", browser.details?.table.map { !(browser.details?.tableView($0, shouldSelectRow: 0) ?? true) } ?? false)
        if let first {
            browser.toggleGroup(first.id)
            await pause(0.3)
            check("a header folds its group", browser.details?.rows.count == rows.count - first.count && headers.first?.collapsed == true)
            browser.toggleGroup(first.id)
            await pause(0.3)
            check("…and unfolds it", browser.details?.rows.count == rows.count)
        }
        await open("Photos")
        check("another folder isn't grouped", browser.groupBy == GroupBy.none && headers.isEmpty)
        browser.goBack()
        await browser.waitUntilLoaded()
        await pause(0.3)
        check("the folder keeps its grouping", browser.groupBy == .modified && !headers.isEmpty)
        browser.groupBy = .none
        await pause(0.3)
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
