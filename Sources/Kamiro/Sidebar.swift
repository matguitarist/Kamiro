import AppKit
import KamiroKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Home, Pinned, Locations, Network and Tags, like the Finder's sidebar. Each part can be hidden in
/// Settings › General (S-032).
struct Sidebar: View {
    let browser: BrowserModel
    @State private var volumes = Volumes.mounted()
    @State private var renaming: Volume?
    private var pins: PinStore { .shared }

    var body: some View {
        List(selection: selection) {
            if pins.shows(.home) {
                Label("Home", systemImage: "house").tag(VirtualPlace.home.url)
            }
            if pins.shows(.pinned) {
                Section("Pinned") {
                    ForEach(pins.list.urls, id: \.self) { url in
                        Label(GoPlace.name(of: url), systemImage: GoPlace.symbol(for: url))
                            .tag(url)
                            .dropDestination(for: URL.self) { urls, _ in browser.drop(urls, into: url) }
                            .contextMenu { PinMenu(url: url, model: browser) }
                    }
                    .onMove { pins.move(fromOffsets: $0, toOffset: $1) }
                    // A folder dropped between pins is pinned there; dropped on a pin, it moves into it.
                    .onInsert(of: [.fileURL]) { index, providers in pins.pin(providers, at: index) }
                }
            }
            if pins.shows(.locations) {
                Section("Locations") {
                    Label(GoPlace.name(of: GoPlace.home), systemImage: "person.crop.circle")
                        .tag(GoPlace.home)
                        .dropDestination(for: URL.self) { urls, _ in browser.drop(urls, into: GoPlace.home) }
                    // Servers go under Network, unless that part is hidden.
                    ForEach(volumes.filter { !$0.isNetwork || !pins.shows(.network) }) { volume in
                        VolumeRow(volume: volume, browser: browser, renaming: $renaming)
                    }
                }
            }
            if pins.shows(.network) {
                NetworkSection(browser: browser, volumes: volumes.filter(\.isNetwork), renaming: $renaming)
            }
            if pins.shows(.tags) {
                TagsSection()
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            volumes = Volumes.mounted()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            volumes = Volumes.mounted()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didRenameVolumeNotification)) { _ in
            volumes = Volumes.mounted()
        }
        .volumeRenameAlert($renaming)
    }

    /// The sidebar shows where the window is when it's a sidebar place, and nothing otherwise.
    private var selection: Binding<URL?> {
        Binding {
            let here = browser.folder
            return pins.list.contains(here) || here == GoPlace.home || volumes.contains { $0.url == here && !$0.isNetwork }
                || VirtualPlace(here) != nil ? here : nil
        } set: { url in
            guard let url, !NetworkSection.act(on: url, browser: browser) else { return }
            browser.go(to: url)
        }
    }
}

extension Volume {
    var symbol: String { isNetwork ? "network" : isRoot ? "internaldrive" : "externaldrive" }
}

/// The pinned folders and the sidebar parts people hide (S-032), kept in the settings and
/// shared by every window.
@Observable
final class PinStore {
    static let shared = PinStore()
    private(set) var list: PinList
    private(set) var hidden: Set<SidebarSection>

    private init() {
        list = PinList(Self.defaultURLs)
        hidden = []
        reload()
    }

    /// Applications, Desktop, Documents and Downloads, like the Finder's first Favorites.
    static var defaultURLs: [URL] {
        let home = GoPlace.home
        return [URL(filePath: "/Applications")] + ["Desktop", "Documents", "Downloads"].map { home.appending(path: $0) }
    }

    /// Reads the settings again (the self-test starts from the defaults).
    func reload() {
        list = Prefs.defaults.stringArray(forKey: Prefs.pins).map(PinList.init(paths:)) ?? PinList(Self.defaultURLs)
        hidden = Set((Prefs.defaults.stringArray(forKey: Prefs.hiddenSidebarSections) ?? []).compactMap(SidebarSection.init))
    }

    /// Pins the folders among `urls`; files are left out.
    func pin(_ urls: [URL], at index: Int? = nil) {
        guard list.pin(urls.filter(Self.isFolder), at: index) else { return }
        save()
    }

    /// Pins what a drag brought.
    func pin(_ providers: [NSItemProvider], at index: Int) {
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let url = await Self.url(from: provider) { urls.append(url) }
            }
            pin(urls, at: index)
        }
    }

    func unpin(_ url: URL) {
        list.unpin(url)
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        list.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func shows(_ section: SidebarSection) -> Bool { !hidden.contains(section) }

    func show(_ section: SidebarSection, _ shown: Bool) {
        if shown { hidden.remove(section) } else { hidden.insert(section) }
        Prefs.defaults.set(SidebarSection.allCases.filter(hidden.contains).map(\.rawValue), forKey: Prefs.hiddenSidebarSections)
    }

    func showBinding(_ section: SidebarSection) -> Binding<Bool> {
        Binding { self.shows(section) } set: { self.show(section, $0) }
    }

    private func save() {
        Prefs.defaults.set(list.paths, forKey: Prefs.pins)
    }

    /// A folder people browse into: not a file, not an app.
    static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            && !NSWorkspace.shared.isFilePackage(atPath: url.path)
    }

    private static func url(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { done in
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                done.resume(returning: (object as? NSURL).map { ($0 as URL).canonical })
            }
        }
    }
}

/// The Go menu's places, with the Finder's shortcuts.
struct GoPlace: Identifiable {
    let url: URL
    let symbol: String
    let key: KeyEquivalent
    let modifiers: EventModifiers
    var id: URL { url }
    var title: String { GoPlace.name(of: url) }

    static let home = URL.homeDirectory.canonical

    static let all: [GoPlace] = [
        GoPlace(url: home, symbol: "person.crop.circle", key: "h", modifiers: [.command, .shift]),
        GoPlace(url: URL(filePath: "/Applications"), symbol: "square.grid.2x2", key: "a", modifiers: [.command, .shift]),
        GoPlace(url: home.appending(path: "Desktop"), symbol: "menubar.dock.rectangle", key: "d", modifiers: [.command, .shift]),
        GoPlace(url: home.appending(path: "Documents"), symbol: "doc", key: "o", modifiers: [.command, .shift]),
        GoPlace(url: home.appending(path: "Downloads"), symbol: "arrow.down.circle", key: "l", modifiers: [.command, .option]),
    ]

    static func name(of url: URL) -> String { FileManager.default.displayName(atPath: url.path) }

    /// The known folders keep their Finder symbol; any other pin is a folder.
    static func symbol(for url: URL) -> String {
        let known: [String: String] = ["Desktop": "menubar.dock.rectangle", "Documents": "doc", "Downloads": "arrow.down.circle",
                                       "Movies": "film", "Music": "music.note", "Pictures": "photo"]
        if url == URL(filePath: "/Applications").canonical { return "square.grid.2x2" }
        if url == home { return "person.crop.circle" }
        if url.deletingLastPathComponent().canonical == home, let symbol = known[url.lastPathComponent] { return symbol }
        return "folder"
    }
}
