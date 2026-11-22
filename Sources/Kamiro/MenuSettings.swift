import KamiroKit
import SwiftUI

extension MenuChoices {
    /// The choices Settings › Menu saved (S-047).
    static var current: MenuChoices {
        MenuChoices(hiddenEntries: Prefs.defaults.stringArray(forKey: Prefs.hiddenMenuEntries) ?? [],
                    hiddenTemplates: Prefs.defaults.stringArray(forKey: Prefs.hiddenTemplates) ?? [])
    }

    func save() {
        Prefs.defaults.set(storedEntries, forKey: Prefs.hiddenMenuEntries)
        Prefs.defaults.set(storedTemplates, forKey: Prefs.hiddenTemplates)
    }
}

extension MenuEntry {
    /// Nil for Open in Code Editor while no editor Kamiro knows is installed.
    var title: String? {
        switch self {
        case .openWith: String(localized: "Open With")
        case .openInNewTab: String(localized: "Open in New Tab")
        case .quickLook: String(localized: "Quick Look")
        case .copyPath: String(localized: "Copy Path")
        case .copyInfo: String(localized: "Copy Info")
        case .duplicate: String(localized: "Duplicate")
        case .copyTo: String(localized: "Copy To")
        case .moveTo: String(localized: "Move To")
        case .compress: String(localized: "Compress")
        case .extract: String(localized: "Extract Here")
        case .convert: String(localized: "Convert")
        case .tags: String(localized: "Tags")
        case .pinToSidebar: String(localized: "Pin to Sidebar")
        case .openInTerminal: ItemActions.openInTerminalTitle
        case .openInEditor: ItemActions.editor.map { String(localized: "Open in \($0.name)") }
        case .diskUsage: String(localized: "Show Disk Usage")
        case .newFile: String(localized: "New File")
        case .newFileFromClipboard: String(localized: "New File from Clipboard")
        }
    }

    var symbol: String {
        switch self {
        case .openWith: "arrow.up.forward.app"
        case .openInNewTab: "plus.square.on.square"
        case .quickLook: "eye"
        case .copyPath: "link"
        case .copyInfo: "info.square"
        case .duplicate: "plus.rectangle.on.rectangle"
        case .copyTo: "doc.on.doc"
        case .moveTo: "folder"
        case .compress: "archivebox"
        case .extract: "arrow.up.bin"
        case .convert: "arrow.triangle.2.circlepath"
        case .tags: "tag"
        case .pinToSidebar: "pin"
        case .openInTerminal: "terminal"
        case .openInEditor: ItemActions.editorSymbol
        case .diskUsage: DiskUsageActions.symbol
        case .newFile: "doc.badge.plus"
        case .newFileFromClipboard: "doc.on.clipboard"
        }
    }
}

/// Settings › Menu: the right-click menu's actions and New File types to leave out (S-047).
struct MenuSettings: View {
    @State private var choices = MenuChoices.current

    var body: some View {
        Section {
            ForEach(MenuEntry.allCases, id: \.self) { entry in
                if let title = entry.title {
                    Toggle(isOn: binding { $0.shows(entry) } set: { $0.show(entry, $1) }) {
                        row(title, entry.symbol)
                    }
                }
            }
        } header: {
            Text("Right-Click Menu")
        } footer: {
            Text("Open, Cut, Copy, Paste, Rename, Move to Trash, New Folder and Properties always show.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        Section {
            ForEach(FileTemplate.all) { template in
                Toggle(isOn: binding { $0.shows(template) } set: { $0.show(template, $1) }) {
                    row(template.title, template.symbol)
                }
            }
            .disabled(!choices.shows(.newFile))
        } header: {
            Text("New File")
        } footer: {
            Text("File › New File and the toolbar’s New menu still list every type.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        if !choices.isEverythingShown {
            Section {
                Button("Show All") { update { $0 = MenuChoices() } }
            }
        }
    }

    /// Symbols differ in width; a fixed column lines the titles up.
    private func row(_ title: String, _ symbol: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol).frame(width: Space.xl)
        }
    }

    private func update(_ body: (inout MenuChoices) -> Void) {
        body(&choices)
        choices.save()
    }

    private func binding(get: @escaping (MenuChoices) -> Bool, set: @escaping (inout MenuChoices, Bool) -> Void) -> Binding<Bool> {
        Binding { get(choices) } set: { value in update { set(&$0, value) } }
    }
}
