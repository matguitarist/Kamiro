import AppKit
import KamiroKit

// MARK: - Copy To and Move To (S-046)

/// The folders things were last copied or moved into, by any means: paste, drop, Copy To.
enum FolderHistory {
    static var recent: RecentFolders {
        get { RecentFolders(Prefs.defaults.stringArray(forKey: Prefs.recentFolders) ?? []) }
        set { Prefs.defaults.set(newValue.paths, forKey: Prefs.recentFolders) }
    }

    static func record(_ folder: URL) {
        var list = recent
        list.add(folder)
        recent = list
    }
}

extension BrowserModel {
    /// Copy To or Move To: pinned folders, recent folders, then Other….
    func sendToMenuItem(_ kind: TransferKind) -> NSMenuItem {
        let sources = orderedSelection
        let choices = Destinations.choices(pins: PinStore.shared.list.urls, recents: FolderHistory.recent.urls,
                                           sources: sources, exists: PinStore.isFolder)
        let menu = NSMenu()
        func add(_ folders: [URL], header: String) {
            guard !folders.isEmpty else { return }
            menu.addItem(.sectionHeader(title: header))
            for folder in folders {
                let item = MenuAction.item(GoPlace.name(of: folder)) { [weak self] in self?.send(kind, sources, to: folder) }
                let icon = NSWorkspace.shared.icon(forFile: folder.path)
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
                item.toolTip = folder.path
                menu.addItem(item)
            }
        }
        add(choices.pinned, header: String(localized: "Pinned"))
        add(choices.recent, header: String(localized: "Recent Folders"))
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(MenuAction.item(String(localized: "Other…")) { [weak self] in self?.chooseDestination(kind, sources) })
        let item = NSMenuItem(title: kind == .copy ? String(localized: "Copy To") : String(localized: "Move To"),
                              action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: kind == .copy ? "doc.on.doc" : "folder", accessibilityDescription: nil)
        item.submenu = menu
        return item
    }

    /// Copies or moves `sources` like a paste there: conflicts ask, progress shows, Undo works.
    func send(_ kind: TransferKind, _ sources: [URL], to folder: URL) {
        guard Destinations.allows(folder, sources: sources) else { NSSound.beep(); return }
        transfer(kind, sources, into: folder)
    }

    /// Other…: any folder, starting from this one; New Folder works in the panel.
    private func chooseDestination(_ kind: TransferKind, _ sources: [URL]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = isVirtual ? nil : folder
        panel.prompt = kind == .copy ? String(localized: "Copy Here") : String(localized: "Move Here")
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        send(kind, sources, to: destination)
    }
}
