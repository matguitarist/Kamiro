import AppKit
import KamiroKit
import SwiftUI

/// The Settings window (Command-Comma). One tab per topic, at most about
/// six. Each tab is a grouped Form that sizes to its content, so the
/// window grows to fit and shows no scroll bar it does not need.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .views: ViewsSettings()
            case .sidebar: SidebarSettings()
            case .appearance: AppearanceSettings()
            case .tools: ToolsSettings()
            case .updates: UpdateSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 520)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, views, sidebar, appearance, tools, updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .views: String(localized: "Views")
        case .sidebar: String(localized: "Sidebar")
        case .appearance: String(localized: "Appearance")
        case .tools: String(localized: "Tools")
        case .updates: String(localized: "Updates")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .views: "rectangle.grid.2x2"
        case .sidebar: "sidebar.left"
        case .appearance: "paintpalette"
        case .tools: "wrench.and.screwdriver"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.returnOpensItems, store: Prefs.defaults) private var returnOpensItems = false
    @AppStorage(Prefs.terminal, store: Prefs.defaults) private var terminal = TerminalApp.apple.bundleID
    private let terminals = ItemActions.installedTerminals
    @AppStorage(Prefs.editor, store: Prefs.defaults) private var editor = ""
    private let editors = ItemActions.installedEditors
    @AppStorage(Prefs.showRecentFiles, store: Prefs.defaults) private var showRecentFiles = true
    @AppStorage(Prefs.newWindowStart, store: Prefs.defaults) private var newWindowStart = StartPlace.home.stored

    var body: some View {
        @Bindable var model = model
        Section("Folders") {
            StartPlacePicker(stored: $newWindowStart)
            Toggle("Recent Files on Home", isOn: $showRecentFiles)
        }
        Section("Keyboard") {
            Toggle(isOn: $returnOpensItems) {
                Text("Return opens items")
                Text("Off, Return renames, like the Finder. On, Return opens, like Windows, and F2 renames.")
            }
        }
        Section("Open With") {
            // A terminal removed since it was chosen shows as Terminal, the one now used.
            Picker("Terminal", selection: Binding(
                get: { TerminalApp.chosen(terminal, installed: terminals).bundleID },
                set: { terminal = $0 })) {
                ForEach(terminals) { app in
                    Label { Text(verbatim: app.name) } icon: { TerminalIcon(bundleID: app.bundleID) }
                        .tag(app.bundleID)
                }
            }
            // Shown once an editor Kamiro knows is installed (VS Code, Cursor, Zed, Xcode…).
            if let current = EditorApp.chosen(editor, installed: editors) {
                Picker("Code Editor", selection: Binding(get: { current.bundleID }, set: { editor = $0 })) {
                    ForEach(editors) { app in
                        Label { Text(verbatim: app.name) } icon: { TerminalIcon(bundleID: app.bundleID) }
                            .tag(app.bundleID)
                    }
                }
            }
        }
        OtherAppsSettings()
        Section("Language") {
            Picker("Language", selection: $model.language) {
                Text("System (\(AppLanguage.systemName))").tag(AppLanguage.system)
                // Every language the app is translated into, each named in itself.
                ForEach(AppLanguage.available, id: \.self) { language in
                    Text(verbatim: language.name).tag(language)
                }
            }
            if model.language != AppLanguage.atLaunch {
                HStack {
                    Text("The new language applies after a restart.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restart Now") { AppLanguage.relaunch() }
                }
            }
        }
    }
}

/// Settings › Views: how folders never changed show (their view, sort, groups and columns),
/// and folders on top in every folder (S-040). View › Use as Defaults sets the same defaults.
struct ViewsSettings: View {
    @State private var standard = Store.views.memory.standard

    var body: some View {
        Section {
            Picker("View", selection: binding(\.mode) { $0.setStandardMode($1) }) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Label(mode.label, systemImage: mode.symbol).tag(mode)
                }
            }
            Picker("Sort By", selection: binding(\.order.key) { $0.setStandardSort($1) }) {
                ForEach(SortKey.allCases, id: \.self) { key in Text(key.title).tag(key) }
            }
            Picker("Group By", selection: binding(\.groupBy) { $0.setStandardGroup($1) }) {
                ForEach(GroupBy.allCases, id: \.self) { group in Text(group.title).tag(group) }
            }
        } header: {
            Text("New Folders")
        } footer: {
            Text("Folders you already changed keep their view. View › Use as Defaults also sets these.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        Section("Columns in Details") {
            // Cloud Status comes on by itself in cloud folders (S-058).
            ForEach(ListColumn.allCases.filter { $0 != .name && $0 != .cloud }, id: \.self) { column in
                Toggle(column.title, isOn: Binding(
                    get: { standard.columns.contains(column) },
                    set: { shown in change { $0.setStandardColumn(column, shown: shown) } }))
            }
        }
        Section("All Folders") {
            Toggle(isOn: Binding(get: { standard.order.foldersFirst }, set: { on in
                change { $0.setFoldersFirst(on) }
                NotificationCenter.default.post(name: BrowserModel.foldersFirstChanged, object: nil)
            })) {
                Text("Folders on top")
                Text("Before files, sorted any way. Off, folders and files mix.")
            }
        }
        .onAppear { standard = Store.views.memory.standard }
    }

    private func change(_ body: (inout ViewMemory) -> Void) {
        Store.views.change(body)
        standard = Store.views.memory.standard
    }

    private func binding<Value>(_ path: KeyPath<FolderView, Value>, set: @escaping (inout ViewMemory, Value) -> Void) -> Binding<Value> {
        Binding(get: { standard[keyPath: path] }, set: { value in change { set(&$0, value) } })
    }
}

extension SortKey {
    /// The same name as its column.
    var title: String { ListColumn(rawValue: rawValue)?.title ?? rawValue }
}

/// Settings › General › Other Apps: the kamiro command (S-039).
struct OtherAppsSettings: View {
    private var command: CommandLineStore { CommandLineStore.shared }

    var body: some View {
        Section("Other Apps") {
            LabeledContent {
                switch command.status {
                case .missing: Button("Install…") { command.install() }
                case .outdated: Button("Update…") { command.install() }
                case .installed: Button("Remove…") { command.remove() }
                case .foreign: EmptyView()
                }
            } label: {
                Text("Command Line")
                Text(commandNote)
                if let failure = command.failure {
                    Text(failure).foregroundStyle(.red)
                }
            }
        }
        .onAppear { command.refresh() }
    }

    private var commandNote: String {
        switch command.status {
        case .missing: String(localized: "Installs the kamiro command in \(command.folder.path), to open folders from Terminal.")
        case .installed: String(localized: "In Terminal, kamiro . opens the folder you’re in, and kamiro and a file shows it in its folder.")
        case .outdated: String(localized: "The kamiro command in \(command.folder.path) opens another copy of Kamiro.")
        case .foreign: String(localized: "Another kamiro command is already in \(command.folder.path); Kamiro leaves it alone.")
        }
    }
}

/// Settings › Sidebar: which parts show, and how servers show in Network.
struct SidebarSettings: View {
    @AppStorage(Prefs.showConnectedShares, store: Prefs.defaults) private var showConnectedShares = false
    @AppStorage(Prefs.connectAllShares, store: Prefs.defaults) private var connectAllShares = true

    var body: some View {
        Section("Show in Sidebar") {
            ForEach(SidebarSection.allCases, id: \.self) { section in
                Toggle(section.title, isOn: PinStore.shared.showBinding(section))
            }
        }
        Section("Network") {
            Toggle(isOn: $showConnectedShares) {
                Text("Connected Shares")
                Text("Under each server in Network. Off, a server's shares open from its page.")
            }
            .disabled(!PinStore.shared.shows(.network))
            Toggle(isOn: $connectAllShares) {
                Text("Connect all shares when opening a server")
                Text("Only the first may ask for a password; the others use the one in the keychain.")
            }
        }
    }
}

/// An app's own icon, small, for the Terminal and Code Editor pickers.
private struct TerminalIcon: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: Self.icon(url))
        }
    }

    private static func icon(_ url: URL) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}

/// Settings > Updates: Sparkle's automatic checks.
struct UpdateSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section("Automatic Updates") {
            Toggle(isOn: $model.checksForUpdates) {
                Text("Check for updates automatically")
                Text(updatesNote)
            }
            .disabled(!Updater.shared.isAvailable)
            LabeledContent("Version \(Self.version)") {
                Button("Check Now") { Updater.shared.checkForUpdates() }
                    .disabled(!Updater.shared.isAvailable)
            }
        }
    }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }

    private var updatesNote: String {
        guard Updater.shared.isAvailable else { return String(localized: "Updates are off in this build.") }
        guard let last = Updater.shared.lastCheck else { return String(localized: "Looks once a day for a new version on GitHub.") }
        return String(localized: "Looks once a day for a new version on GitHub. Last checked \(last.formatted(.relative(presentation: .named))).")
    }
}

/// The app's own language, independent of macOS's. Stored as the app's
/// AppleLanguages default, which macOS reads at launch. The choices come
/// from the bundle, so adding a translation adds it here.
struct AppLanguage: Hashable {
    /// A localization code ("fr", "pt-BR"), or nil to follow macOS.
    let code: String?

    static let system = AppLanguage(code: nil)
    private static let key = "AppleLanguages"

    /// The app's translations, sorted by their own names.
    static let available: [AppLanguage] = Set(Bundle.main.localizations)  // can list one twice
        .subtracting(["Base"])
        .map { AppLanguage(code: $0) }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    /// "Français", "English".
    var name: String {
        guard let code else { return "" }
        let name = Locale(identifier: code).localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    static var current: AppLanguage {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        guard let stored = (domain?[key] as? [String])?.first else { return .system }
        // "fr-CA" set elsewhere still selects "fr".
        let codes = available.compactMap(\.code)
        guard let match = Bundle.preferredLocalizations(from: codes, forPreferences: [stored]).first,
              codes.contains(match) else { return .system }
        return AppLanguage(code: match)
    }

    /// What this run of the app uses (the setting can change after launch).
    static let atLaunch = current

    /// The language macOS would pick for the app, by name ("Français").
    static var systemName: String {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[key] as? [String] ?? Locale.preferredLanguages
        let code = Bundle.preferredLocalizations(from: available.compactMap(\.code), forPreferences: global).first ?? "en"
        return AppLanguage(code: code).name
    }

    /// Test and snapshot runs never change the real setting.
    func apply() {
        guard !Store.isOverridden else { return }
        if let code {
            UserDefaults.standard.set([code], forKey: Self.key)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.key)
        }
    }

    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

extension SidebarSection {
    var title: String {
        switch self {
        case .home: String(localized: "Home")
        case .pinned: String(localized: "Pinned")
        case .locations: String(localized: "Locations")
        case .cloud: String(localized: "Cloud")
        case .network: String(localized: "Network")
        case .tags: String(localized: "Tags")
        }
    }
}
