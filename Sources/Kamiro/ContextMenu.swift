import AppKit
import KamiroKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - The right-click menu (S-033)

extension BrowserModel {
    /// The list's right-click menu. It follows what's under the pointer: items get Open, Copy and
    /// the like; empty space gets Paste and New. What doesn't apply is left out, not dimmed.
    func contextMenu(onItems: Bool) -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ symbol: String, _ action: @escaping () -> Void) {
            let item = MenuAction.item(title, handler: action)
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        func group() {
            if let last = menu.items.last, !last.isSeparatorItem { menu.addItem(.separator()) }
        }
        let chosen = onItems ? selectedItems : []
        let urls = chosen.map(\.url)
        let files = chosen.filter { !$0.isFolder }
        let folders = chosen.filter(\.isFolder)
        // A server's share that isn't mounted yet only opens (S-055).
        if onItems, chosen.contains(where: { !$0.url.isFileURL }) {
            add(String(localized: "Open"), "arrow.up.forward.app") { [weak self] in self?.open() }
            return menu
        }
        if onItems, !chosen.isEmpty {
            add(String(localized: "Open"), "arrow.up.forward.app") { [weak self] in self?.open() }
            if !files.isEmpty, folders.isEmpty {
                menu.addItem(ItemActions.openWithItem(for: files.map(\.url)))
                menu.addItem(ItemActions.openWithItem(for: files.map(\.url), always: true))
            }
            if !folders.isEmpty, files.isEmpty {
                add(String(localized: "Open in New Tab"), "plus.square.on.square") { [weak self] in self?.open(newTab: true) }
            }
            if isVirtual, chosen.count == 1 {
                add(String(localized: "Show in Enclosing Folder"), "folder") { [weak self] in self?.showInEnclosingFolder() }
            }
            add(String(localized: "Quick Look"), "eye") { [weak self] in self?.quickLook?() }
            // iCloud Drive and sync folders (S-058).
            if canDownload {
                add(String(localized: "Download Now"), "icloud.and.arrow.down") { [weak self] in self?.downloadSelection() }
            }
            if canRemoveDownload {
                add(String(localized: "Remove Download"), "icloud.slash") { [weak self] in self?.removeDownloadOfSelection() }
            }
            group()
            // An app's folder in iCloud Drive stays where its app keeps it (S-057).
            let locked = selectionHasAppFolder
            if !locked { add(String(localized: "Cut"), "scissors") { [weak self] in self?.cutSelection() } }
            add(String(localized: "Copy"), "doc.on.doc") { [weak self] in self?.copySelection() }
            add(String(localized: "Copy Path"), "link") { ItemActions.copyPaths(urls) }
            ItemActions.showCopyPathKey(menu.items.last)
            menu.addItem(ItemActions.copyInfoItem(for: urls))
            if canPaste { add(String(localized: "Paste"), "doc.on.clipboard") { [weak self] in self?.paste() } }
            if !locked {
                add(String(localized: "Duplicate"), "plus.rectangle.on.rectangle") { [weak self] in self?.duplicateSelection() }
            }
            menu.addItem(sendToMenuItem(.copy))
            if !locked { menu.addItem(sendToMenuItem(.move)) }
            if !compressTargets.isEmpty {
                add(compressTitle, "archivebox") { [weak self] in self?.compressSelection() }
                if compressTargets.count > 1 {
                    add(String(localized: "Compress To…"), "archivebox") { [weak self] in self?.compressSelectionTo() }
                }
            }
            if !extractTargets.isEmpty {
                add(String(localized: "Extract Here"), "arrow.up.bin") { [weak self] in self?.extractSelection() }
            }
            if let convert = convertMenuItem() { menu.addItem(convert) }
            group()
            if !locked {
                if chosen.count == 1 { add(String(localized: "Rename"), "pencil") { [weak self] in self?.beginRename() } }
                add(String(localized: "Move to Trash"), "trash") { [weak self] in self?.trashSelection() }
            }
            group()
            let tags = tagsMenu()
            tags.image = NSImage(systemSymbolName: "tag", accessibilityDescription: nil)
            menu.addItem(tags)
            // Folders only: a file can't be pinned (S-032).
            if !folders.isEmpty, files.isEmpty, !pinTargets.isEmpty {
                add(String(localized: "Pin to Sidebar"), "pin") { [weak self] in self?.pinToSidebar() }
            }
            group()
            if folders.count == 1, files.isEmpty {
                let folder = folders[0].url
                add(ItemActions.openInTerminalTitle, "terminal") { ItemActions.openInTerminal(folder) }
            }
            if let editor = ItemActions.editor, chosen.allSatisfy({ EditorApp.opens($0.url, isFolder: $0.isFolder) }) {
                add(String(localized: "Open in \(editor.name)"), ItemActions.editorSymbol) { ItemActions.open(urls, in: editor) }
            }
            // A disk listed in /Volumes ejects from here too.
            if chosen.count == 1, let volume = Volumes.volume(at: chosen[0].url), volume.actions.contains(.eject) {
                add(String(localized: "Eject"), "eject") { [weak self] in ItemActions.eject(volume, from: self) }
            }
        } else if !isVirtual, state == .ready {
            if canPaste { add(String(localized: "Paste"), "doc.on.clipboard") { [weak self] in self?.paste() } }
            group()
            add(String(localized: "New Folder"), "folder.badge.plus") { [weak self] in self?.newFolder() }
            let newFile = NSMenuItem(title: String(localized: "New File"), action: nil, keyEquivalent: "")
            newFile.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil)
            newFile.submenu = Self.templateMenu { [weak self] in self?.newFile($0) }
            menu.addItem(newFile)
            if canMakeFromClipboard {
                add(String(localized: "New File from Clipboard"), "doc.on.clipboard") { [weak self] in self?.newFileFromClipboard() }
            }
            group()
            let here = folder
            add(ItemActions.openTerminalHereTitle, "terminal") { ItemActions.openInTerminal(here) }
            if let editor = ItemActions.editor {
                add(String(localized: "Open Folder in \(editor.name)"), ItemActions.editorSymbol) { ItemActions.open([here], in: editor) }
            }
            add(String(localized: "Copy Path"), "link") { ItemActions.copyPaths([here]) }
            ItemActions.showCopyPathKey(menu.items.last)
        }
        if (onItems && !chosen.isEmpty) || (!isVirtual && state == .ready) {
            group()
            add(String(localized: "Properties"), "info.circle") { [weak self] in self?.showProperties() }
        }
        if let last = menu.items.last, last.isSeparatorItem { menu.removeItem(last) }
        return menu
    }

    /// Edit › Copy Path (⌥⌘C): the selected items' paths, or the folder's when nothing is selected.
    func copyPathOfSelection() {
        if !selection.isEmpty {
            ItemActions.copyPaths(orderedSelection)
        } else if !isVirtual {
            ItemActions.copyPaths([folder])
        }
    }

    /// Duplicate (⌘D): a copy of each selected item next to it, named "name copy".
    func duplicateSelection() {
        let urls = orderedSelection
        guard !urls.isEmpty else { return }
        // Copying into an item's own folder makes "name copy" (TransferEngine).
        let byFolder = Dictionary(grouping: urls) { $0.deletingLastPathComponent().canonical }
        for (parent, group) in byFolder.sorted(by: { $0.key.path < $1.key.path }) {
            transfer(.copy, group, into: parent)
        }
    }
}

// MARK: - Actions shared by the list, the Home page and the sidebar

@MainActor
enum ItemActions {
    /// Paths, one per line, on the pasteboard (the test pasteboard in test runs).
    static func copyPaths(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        copyText(urls.map(\.path).joined(separator: "\n"))
    }

    /// Copy Path shows ⌥⌘C, its shortcut in the Edit menu.
    static func showCopyPathKey(_ item: NSMenuItem?) {
        item?.keyEquivalent = "c"
        item?.keyEquivalentModifierMask = [.command, .option]
    }

    /// Copy Info and its submenu: the name, the name without extension, the extension, the
    /// parent folder's path. Choices that say nothing for these items are left out.
    static func copyInfoItem(for urls: [URL]) -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "Copy Info"), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        let menu = NSMenu()
        for info in CopyInfo.allCases where info.applies(to: urls) {
            menu.addItem(MenuAction.item(info.title) { copyText(info.text(for: urls)) })
        }
        item.submenu = menu
        return item
    }

    static func copyText(_ text: String) {
        let pasteboard = FileClipboard.shared.pasteboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: Code editor (S-034)

    static let editorSymbol = "chevron.left.forwardslash.chevron.right"

    static var installedEditors: [EditorApp] {
        EditorApp.installed { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    }

    /// The one chosen in Settings › General, or the first installed; nil when there's none.
    static var editor: EditorApp? {
        EditorApp.chosen(Prefs.defaults.string(forKey: Prefs.editor), installed: installedEditors)
    }

    static func open(_ urls: [URL], in editor: EditorApp) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleID) else { NSSound.beep(); return }
        open(urls, with: app)
    }

    /// The terminals on this Mac that Kamiro knows how to open in a folder.
    static var installedTerminals: [TerminalApp] {
        TerminalApp.installed { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    }

    /// The one chosen in Settings › General, or Apple's Terminal once that one is gone.
    static var terminal: TerminalApp {
        TerminalApp.chosen(Prefs.defaults.string(forKey: Prefs.terminal), installed: installedTerminals)
    }

    /// "Open in Ghostty", for a folder that's chosen (an item, a pin, a disk).
    static var openInTerminalTitle: String { String(localized: "Open in \(terminal.name)") }

    /// "Open Ghostty Here", for the folder on screen (right-click on empty space).
    static var openTerminalHereTitle: String { String(localized: "Open \(terminal.name) Here") }

    /// Opens a window of the chosen terminal in `folder`.
    static func openInTerminal(_ folder: URL) {
        let terminal = terminal
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.bundleID) else { NSSound.beep(); return }
        let configuration = NSWorkspace.OpenConfiguration()
        switch terminal.launch {
        case .openFolder:
            NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: configuration)
        case .arguments:
            // These read the folder from their command line only at launch: a new instance each time.
            configuration.arguments = terminal.arguments(for: folder)
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        }
    }

    // MARK: Open With

    /// The apps that open every one of `urls`, the default first; the rest by name.
    static func apps(for urls: [URL]) -> (default: URL?, others: [URL]) {
        guard let first = urls.first else { return (nil, []) }
        var common = NSWorkspace.shared.urlsForApplications(toOpen: first).map(\.canonical)
        for url in urls.dropFirst() {
            let these = Set(NSWorkspace.shared.urlsForApplications(toOpen: url).map(\.canonical))
            common.removeAll { !these.contains($0) }
        }
        var seen = Set<URL>()
        common = common.filter { seen.insert($0).inserted }
        let preferred = NSWorkspace.shared.urlForApplication(toOpen: first)?.canonical
        let chosen = preferred.flatMap { common.contains($0) ? $0 : nil }
        let others = common.filter { $0 != chosen }
            .sorted { appName($0).localizedStandardCompare(appName($1)) == .orderedAscending }
        return (chosen, others)
    }

    static func appName(_ app: URL) -> String {
        FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }

    static func open(_ urls: [URL], with app: URL) {
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Open With › Other…: pick any app in /Applications; Always Open With makes it the default.
    static func openWithOther(_ urls: [URL]) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = String(localized: "Open")
        panel.message = String(localized: "Choose an app to open the selected items.")
        let always = NSButton(checkboxWithTitle: String(localized: "Always Open With"), target: nil, action: nil)
        always.sizeToFit()
        always.frame.size.height += Space.lg
        panel.accessoryView = always
        panel.isAccessoryViewDisclosed = true
        guard panel.runModal() == .OK, let app = panel.url else { return }
        if always.state == .on { makeDefault(app, for: urls) }
        open(urls, with: app)
    }

    // MARK: Default app (S-036)

    /// "PDF document": the kind the Change All question names.
    static func kindName(_ urls: [URL]) -> String {
        let names = DefaultApps.types(of: urls).map { $0.localizedDescription ?? $0.identifier }
        return ListFormatter.localizedString(byJoining: names)
    }

    /// Makes `app` open every file of the kinds in `urls`, here and in the Finder.
    static func makeDefault(_ app: URL, for urls: [URL]) {
        let types = DefaultApps.types(of: urls)
        Task {
            for type in types {
                do {
                    try await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type)
                    Store.log.post(.info, "\(appName(app)) now opens \(type.identifier)", source: "Open With")
                } catch {
                    Store.log.post(.error, "Couldn't make \(appName(app)) open \(type.identifier): \(error.localizedDescription)", source: "Open With")
                    let alert = NSAlert()
                    alert.messageText = String(localized: "\(appName(app)) couldn’t be made the default.")
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    /// Asks before changing the default, like the Finder's Change All…; true when changed.
    @discardableResult
    static func confirmMakeDefault(_ app: URL, for urls: [URL]) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Open every “\(kindName(urls))” file with \(appName(app))?")
        alert.informativeText = String(localized: "Files of this kind will open with \(appName(app)) everywhere on this Mac, the Finder included.")
        alert.addButton(withTitle: String(localized: "Change All"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        makeDefault(app, for: urls)
        return true
    }

    /// Open With and its submenu: the default app, the others, then Other…. With ⌥ held it
    /// reads Always Open With: the app chosen opens them and becomes the default for their kind.
    static func openWithItem(for urls: [URL], always: Bool = false) -> NSMenuItem {
        let title = always ? String(localized: "Always Open With") : String(localized: "Open With")
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "arrow.up.forward.square", accessibilityDescription: nil)
        if always {
            item.isAlternate = true
            item.keyEquivalentModifierMask = .option
        }
        let menu = NSMenu()
        let (main, others) = apps(for: urls)
        func add(_ app: URL, title: String) {
            let entry = MenuAction.item(title) {
                if always { makeDefault(app, for: urls) }
                open(urls, with: app)
            }
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            entry.image = icon
            menu.addItem(entry)
        }
        if let main {
            add(main, title: String(localized: "\(appName(main)) (default)"))
            if !others.isEmpty { menu.addItem(.separator()) }
        }
        others.forEach { add($0, title: appName($0)) }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(MenuAction.item(String(localized: "Other…")) { openWithOther(urls) })
        item.submenu = menu
        return item
    }

    // MARK: Disks

    /// Ejects a disk; a window showing it goes Home. Says so when the disk is in use.
    static func eject(_ volume: Volume, from browser: BrowserModel?) {
        Task {
            do {
                try await unmount(volume)
                Store.log.post(.info, "Ejected \(volume.url.path)", source: "Disks")
                if let browser, browser.folder.path == volume.url.path || browser.folder.path.hasPrefix(volume.url.path + "/") {
                    browser.go(to: VirtualPlace.home.url)
                }
            } catch {
                Store.log.post(.error, "Couldn't eject \(volume.url.path): \(error.localizedDescription)", source: "Disks")
                let alert = NSAlert()
                alert.messageText = String(localized: "“\(volume.name)” couldn’t be ejected.")
                alert.informativeText = String(localized: "Quit apps that use it, then try again.") + "\n\n" + error.localizedDescription
                alert.runModal()
            }
        }
    }

    static func unmount(_ volume: Volume) async throws {
        try await FileManager.default.unmountVolume(at: volume.url, options: volume.isNetwork ? [] : [.allPartitionsAndEjectDisk])
    }

    static func renameVolume(_ volume: Volume, to name: String) {
        do {
            try Volumes.rename(volume.url, to: name)
            Store.log.post(.info, "Renamed disk \(volume.url.path) to \(name)", source: "Disks")
        } catch {
            let problem = (error as? NameProblem)?.message(name) ?? error.localizedDescription
            Store.log.post(.error, "Couldn't rename disk \(volume.url.path): \(problem)", source: "Disks")
            let alert = NSAlert()
            alert.messageText = String(localized: "“\(volume.name)” couldn’t be renamed.")
            alert.informativeText = problem
            alert.runModal()
        }
    }
}

// MARK: - SwiftUI menus for the Home page and the sidebar

extension CopyInfo {
    var title: String {
        switch self {
        case .name: String(localized: "Name")
        case .nameWithoutExtension: String(localized: "Name Without Extension")
        case .fileExtension: String(localized: "Extension")
        case .parentPath: String(localized: "Parent Folder Path")
        }
    }
}

extension VolumeAction {
    var title: String {
        switch self {
        case .open: String(localized: "Open")
        case .openInNewTab: String(localized: "Open in New Tab")
        case .openInTerminal: ItemActions.openInTerminalTitle
        case .rename: String(localized: "Rename…")
        case .copyPath: String(localized: "Copy Path")
        case .properties: String(localized: "Properties")
        case .eject: String(localized: "Eject")
        }
    }

    var symbol: String {
        switch self {
        case .open: "arrow.up.forward.app"
        case .openInNewTab: "plus.square.on.square"
        case .openInTerminal: "terminal"
        case .rename: "pencil"
        case .copyPath: "link"
        case .properties: "info.circle"
        case .eject: "eject"
        }
    }
}

/// A disk's right-click menu: open it, get its Properties, rename or eject it.
struct VolumeMenu: View {
    let volume: Volume
    let model: BrowserModel
    @Binding var renaming: Volume?

    var body: some View {
        ForEach(Array(volume.actions.enumerated()), id: \.offset) { _, action in
            if let action {
                Button(action.title, systemImage: action.symbol) { perform(action) }
            } else {
                Divider()
            }
        }
    }

    private func perform(_ action: VolumeAction) {
        switch action {
        case .open: model.go(to: volume.url)
        case .openInNewTab: model.openWindow?(volume.url, true)
        case .openInTerminal: ItemActions.openInTerminal(volume.url)
        case .rename: renaming = volume
        case .copyPath: ItemActions.copyPaths([volume.url])
        case .properties: model.openProperties?(volume.url)
        case .eject: ItemActions.eject(volume, from: model)
        }
    }
}

/// Asks for a disk's new name.
struct VolumeRenameAlert: ViewModifier {
    @Binding var volume: Volume?
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert("Rename Disk", isPresented: Binding { volume != nil } set: { if !$0 { volume = nil } }, presenting: volume) { volume in
                TextField("Name", text: $name)
                Button("Rename") { ItemActions.renameVolume(volume, to: name) }
                Button("Cancel", role: .cancel) {}
            } message: { volume in
                Text("Enter a new name for “\(volume.name)”.")
            }
            .onChange(of: volume) { _, volume in name = volume?.name ?? "" }
    }
}

extension View {
    func volumeRenameAlert(_ volume: Binding<Volume?>) -> some View { modifier(VolumeRenameAlert(volume: volume)) }
}

/// Open With for a file on the Home page: the default app, the others, then Other….
struct OpenWithMenu: View {
    let urls: [URL]

    var body: some View {
        let apps = ItemActions.apps(for: urls)
        Menu("Open With", systemImage: "arrow.up.forward.square") {
            if let main = apps.default {
                Button("\(ItemActions.appName(main)) (default)") { ItemActions.open(urls, with: main) }
                if !apps.others.isEmpty { Divider() }
            }
            ForEach(apps.others, id: \.self) { app in
                Button(ItemActions.appName(app)) { ItemActions.open(urls, with: app) }
            }
            Divider()
            Button("Other…") { ItemActions.openWithOther(urls) }
        }
    }
}
