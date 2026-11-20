import AppKit
import KamiroKit
import SwiftUI

/// The content column: the list, or why there's no list, and the status bar under it.
struct BrowserView: View {
    let model: BrowserModel
    let showStatusBar: Bool

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showStatusBar, !model.isFailed { StatusBar(model: model) }
            }
    }

    @ViewBuilder
    private var content: some View {
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
        case .failed(.other(let message)):
            ContentUnavailableView {
                Label("Kamiro can't read this folder.", systemImage: "exclamationmark.triangle")
            } description: {
                Text(verbatim: message)
            }
        default:
            DetailsTable(model: model, version: model.itemsVersion, selection: model.selection,
                         reveal: model.revealToken, focus: model.focusToken)
                .overlay {
                    if model.state == .ready, model.items.isEmpty {
                        ContentUnavailableView("Folder Is Empty", systemImage: "folder")
                    } else if model.showsLoading {
                        ProgressView("Loading…")
                    }
                }
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

/// "12 items, 3 selected (4.2 MB), 120 GB available", under the list.
struct StatusBar: View {
    let model: BrowserModel

    var body: some View {
        Text(StatusText.make(model.counts))
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.xs)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
            .accessibilityElement(children: .combine)
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

/// Home, Pinned and Locations, like the Finder's sidebar.
struct Sidebar: View {
    let browser: BrowserModel
    @State private var volumes = Volumes.mounted()

    var body: some View {
        List(selection: selection) {
            Section("Pinned") {
                ForEach(Pinned.defaults) { place in
                    Label(place.title, systemImage: place.symbol).tag(place.url)
                }
            }
            Section("Locations") {
                ForEach(volumes) { volume in
                    Label(volume.name, systemImage: volume.isNetwork ? "network" : volume.isRoot ? "internaldrive" : "externaldrive")
                        .tag(volume.url)
                }
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            volumes = Volumes.mounted()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            volumes = Volumes.mounted()
        }
    }

    /// The sidebar shows where the window is when it's a sidebar place, and nothing otherwise.
    private var selection: Binding<URL?> {
        Binding {
            let here = browser.folder
            return Pinned.defaults.contains { $0.url == here } || volumes.contains { $0.url == here } ? here : nil
        } set: { url in
            if let url { browser.go(to: url) }
        }
    }
}

/// The sidebar's pinned folders. People pin their own with S-032.
struct Pinned: Identifiable {
    let url: URL
    let symbol: String
    let key: KeyEquivalent
    let modifiers: EventModifiers
    var id: URL { url }
    var title: String { FileManager.default.displayName(atPath: url.path) }

    static let defaults: [Pinned] = {
        let home = URL.homeDirectory.canonical
        return [
            Pinned(url: home, symbol: "house", key: "h", modifiers: [.command, .shift]),
            Pinned(url: URL(filePath: "/Applications"), symbol: "square.grid.2x2", key: "a", modifiers: [.command, .shift]),
            Pinned(url: home.appending(path: "Desktop"), symbol: "menubar.dock.rectangle", key: "d", modifiers: [.command, .shift]),
            Pinned(url: home.appending(path: "Documents"), symbol: "doc", key: "o", modifiers: [.command, .shift]),
            Pinned(url: home.appending(path: "Downloads"), symbol: "arrow.down.circle", key: "l", modifiers: [.command, .option]),
        ]
    }()
}

/// Back (hold for recent folders), Forward, Up, and the address bar.
struct BrowserToolbar: ToolbarContent {
    @Bindable var model: BrowserModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Menu {
                ForEach(Array(model.history.backList.reversed().enumerated()), id: \.offset) { index, url in
                    Button(FileManager.default.displayName(atPath: url.path)) { model.goBack(index + 1) }
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
                    Button(FileManager.default.displayName(atPath: url.path)) { model.goForward(index + 1) }
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
        ToolbarItem(placement: .principal) {
            AddressBar(model: model)
        }
    }
}
