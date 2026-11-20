import AppKit
import KamiroKit
import SwiftUI

/// The content column: the list, or why there's no list, and the status bar under it.
struct BrowserView: View {
    let model: BrowserModel
    let showStatusBar: Bool
    @AppStorage(Prefs.iconSize, store: Prefs.defaults) private var iconSize = IconSize.standard
    @AppStorage(Prefs.showColumnPreview, store: Prefs.defaults) private var showColumnPreview = true

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                if let search = model.search { SearchScopeBar(model: model, search: search) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showStatusBar, !model.isFailed, model.place != .home { StatusBar(model: model) }
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.place == .home {
            HomeView(model: model)
        } else {
            folderContent
        }
    }

    @ViewBuilder
    private var folderContent: some View {
        switch model.state {
        case .failed(.denied):
            ContentUnavailableView {
                Label("Kamiro can't open this folder.", systemImage: "lock")
            } description: {
                Text("macOS keeps this folder closed to Kamiro. Allow it in Privacy & Security, under Files and Folders or Full Disk Access.")
            } actions: {
                Button("Open Privacy Settings") { PrivacySettings.open() }
            }
        case .failed(.missing), .failed(.notFolder):
            ContentUnavailableView {
                Label("This folder isn't there anymore.", systemImage: "questionmark.folder")
            } description: {
                Text(verbatim: model.folder.path)
            } actions: {
                Button("Go to Enclosing Folder") { model.goUp() }
            }
        case .failed where model.isServerPage:
            if case .server(let server) = model.place {
                ContentUnavailableView {
                    Label(String(localized: "“\(ServerHost.displayName(server))” didn't list its shares."), systemImage: "server.rack")
                } description: {
                    Text("It may need a name and password, or it isn't answering.")
                } actions: {
                    Button("Connect As…") { model.connectAs(server) }
                    Button("Try Again") { model.refresh() }
                }
            }
        case .failed(.other(let message)):
            ContentUnavailableView {
                Label("Kamiro can't read this folder.", systemImage: "exclamationmark.triangle")
            } description: {
                Text(verbatim: message)
            }
        default:
            list
                .overlay {
                    if model.state == .ready, model.items.isEmpty, !model.filterText.isEmpty {
                        ContentUnavailableView {
                            Label(String(localized: "No Items Match “\(model.filterText)”"), systemImage: "line.3.horizontal.decrease")
                        } actions: {
                            Button("Clear Filter") { model.filterText = "" }
                        }
                    } else if model.state == .ready, model.items.isEmpty, let search = model.search {
                        ContentUnavailableView.search(text: search.text)
                    } else if model.state == .ready, model.items.isEmpty, let place = model.place {
                        ContentUnavailableView(String(localized: "Nothing Is Tagged “\(place.title)”"), systemImage: "tag")
                    } else if model.state == .ready, model.items.isEmpty {
                        ContentUnavailableView("Folder Is Empty", systemImage: "folder")
                    } else if model.showsLoading {
                        ProgressView("Loading…")
                    }
                }
        }
    }
}

extension BrowserView {
    @ViewBuilder
    private var list: some View {
        // A tag's items come from many folders: no columns there.
        switch model.isVirtual && model.mode == .columns ? .details : model.mode {
        case .icons:
            IconGrid(model: model, version: model.itemsVersion, selection: model.selection,
                     reveal: model.revealToken, focus: model.focusToken,
                     cutVersion: FileClipboard.shared.version, renameToken: model.renameToken,
                     iconSize: min(max(iconSize, IconSize.range.lowerBound), IconSize.range.upperBound))
        case .columns:
            ColumnBrowser(model: model, version: model.itemsVersion, selection: model.selection, folder: model.folder,
                          focus: model.focusToken, cutVersion: FileClipboard.shared.version, renameToken: model.renameToken,
                          showPreview: showColumnPreview)
        case .details:
            DetailsTable(model: model, version: model.itemsVersion, selection: model.selection,
                         reveal: model.revealToken, focus: model.focusToken,
                         cutVersion: FileClipboard.shared.version, renameToken: model.renameToken,
                         groupVersion: model.groupVersion, sizesVersion: model.sizesVersion)
        }
    }
}

extension ViewMode {
    var title: String {
        switch self {
        case .icons: String(localized: "as Icons")
        case .details: String(localized: "as Details")
        case .columns: String(localized: "as Columns")
        }
    }

    /// The toolbar's name for it, said by VoiceOver and shown in hover help.
    var label: String {
        switch self {
        case .icons: String(localized: "Icons")
        case .details: String(localized: "Details")
        case .columns: String(localized: "Columns")
        }
    }

    var symbol: String {
        switch self {
        case .icons: "square.grid.2x2"
        case .details: "list.bullet"
        case .columns: "rectangle.split.3x1"
        }
    }

    var key: KeyEquivalent {
        switch self {
        case .icons: "1"
        case .details: "2"
        case .columns: "3"
        }
    }
}

enum PrivacySettings {
    static func open() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// "12 items, 3 selected (4.2 MB), 120 GB available", under the list; in icon view, the
/// icon size slider at its right end, like the Finder's.
struct StatusBar: View {
    let model: BrowserModel
    @AppStorage(Prefs.iconSize, store: Prefs.defaults) private var iconSize = IconSize.standard

    /// In search results, the one selected item's folder follows the counts, as in the Finder.
    private var statusText: String {
        let counts = StatusText.make(model.counts)
        guard model.isVirtual, model.selection.count == 1, let url = model.selection.first else { return counts }
        return String(localized: "\(counts) — in \(PathInput.display(url.deletingLastPathComponent()))")
    }

    var body: some View {
        Text(statusText)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            .padding(.horizontal, model.mode == .icons ? 140 : 0)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.xs)
            .overlay(alignment: .trailing) {
                if model.mode == .icons {
                    Slider(value: $iconSize, in: IconSize.range) {
                        Text("Icon size")
                    } minimumValueLabel: {
                        Image(systemName: "square.grid.3x3").imageScale(.small)
                    } maximumValueLabel: {
                        Image(systemName: "square.grid.2x2").imageScale(.medium)
                    }
                    .labelsHidden()
                    .controlSize(.mini)
                    .frame(width: 120)
                    .padding(.trailing, Space.md)
                    .help("Icon size")
                }
            }
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
    }
}

enum StatusText {
    static func make(_ counts: StatusCounts) -> String {
        var parts = [String(localized: "\(counts.items) items")]
        if counts.selected > 0 {
            if let bytes = counts.selectedBytes {
                parts.append(String(localized: "\(counts.selected) selected (\(size(bytes)))"))
            } else {
                parts.append(String(localized: "\(counts.selected) selected"))
            }
        }
        if let available = counts.available {
            parts.append(String(localized: "\(size(available)) available"))
        }
        return parts.joined(separator: ", ")
    }

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Back (hold for recent folders), Forward, Up, and the address bar.
struct BrowserToolbar: ToolbarContent {
    @Bindable var model: BrowserModel
    @AppStorage(Prefs.showInspector, store: Prefs.defaults) private var showInspector = false

    var body: some ToolbarContent {
        // One ToolbarItem holding one ControlGroup: three separate items split into two
        // glass capsules whenever their enabled states differ.
        ToolbarItem(placement: .navigation) {
            ControlGroup {
            Menu {
                ForEach(Array(model.history.backList.reversed().enumerated()), id: \.offset) { index, url in
                    Button(BrowserModel.name(of: url)) { model.goBack(index + 1) }
                }
            } label: {
                Label("Back", systemImage: "chevron.left")
            } primaryAction: {
                model.goBack()
            }
            .menuIndicator(.hidden)
            .disabled(!model.history.canGoBack)
            .help("Go back (⌘[)")
            Menu {
                ForEach(Array(model.history.forwardList.reversed().enumerated()), id: \.offset) { index, url in
                    Button(BrowserModel.name(of: url)) { model.goForward(index + 1) }
                }
            } label: {
                Label("Forward", systemImage: "chevron.right")
            } primaryAction: {
                model.goForward()
            }
            .menuIndicator(.hidden)
            .disabled(!model.history.canGoForward)
            .help("Go forward (⌘])")
            Button("Enclosing Folder", systemImage: "arrow.up") { model.goUp() }
                .disabled(!model.canGoUp)
                .help("Go to the enclosing folder (⌘↑)")
            }
            .controlGroupStyle(.navigation)
        }
        ToolbarItem(placement: .principal) {
            AddressBar(model: model)
        }
        ToolbarItem(placement: .primaryAction) {
            // One button with a menu, like the Finder's in a narrow window: three segments
            // pushed the address bar out of the toolbar at the smallest window size.
            Menu {
                Picker("View", selection: $model.mode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Label(mode.label, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("View", systemImage: model.mode.symbol)
            }
            .help("Show items as icons, details or columns (⌘1, ⌘2, ⌘3)")
        }
        if !TransferCenter.shared.tasks.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                TransferButton(center: TransferCenter.shared)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                NewItemsMenu(newFolder: { model.newFolder() }, newFile: { model.newFile($0) },
                             fromClipboard: { model.newFileFromClipboard() })
            } label: {
                Label("New", systemImage: "plus")
            }
            .menuIndicator(.hidden)
            .disabled(model.state != .ready)
            .help("Make a new folder or file here")
        }
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $showInspector) {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help(showInspector ? "Hide the inspector (⌥⌘I)" : "Show the inspector (⌥⌘I)")
        }
    }
}
