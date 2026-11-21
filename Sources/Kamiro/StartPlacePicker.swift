import AppKit
import KamiroKit
import SwiftUI

/// Settings › General › New windows open on: Home, a folder of the home folder, or Other…,
/// which asks for a folder and then lists it by name (S-040).
struct StartPlacePicker: View {
    @Binding var stored: String
    /// The tag of Other…, never kept: choosing it asks for a folder.
    private static let other = "other"

    var body: some View {
        let current = StartPlace(stored: stored)
        Picker(selection: Binding(get: { stored }, set: { choose($0) })) {
            ForEach(StartPlace.standard, id: \.self) { place in
                Label(place.title, systemImage: place.symbol).tag(place.stored)
            }
            if case .folder = current {
                Divider()
                Label(current.title, systemImage: current.symbol).tag(current.stored)
            }
            Divider()
            Text("Other…").tag(Self.other)
        } label: {
            Text("New windows open on")
            Text("New tabs too. A folder that's gone opens Home.")
        }
    }

    private func choose(_ tag: String) {
        guard tag == Self.other else { stored = tag; return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
        panel.directoryURL = StartPlace(stored: stored).folder()
        if panel.runModal() == .OK, let url = panel.url { stored = StartPlace.folder(URL(filePath: url.path)).stored }
    }
}

extension StartPlace {
    var title: String {
        switch self {
        case .home: String(localized: "Home")
        // Named like the sidebar's row: the person's name.
        case .homeFolder: GoPlace.name(of: GoPlace.home)
        case .desktop: String(localized: "Desktop")
        case .documents: String(localized: "Documents")
        case .downloads: String(localized: "Downloads")
        case .folder(let url): FileManager.default.displayName(atPath: url.path)
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .homeFolder: "person.crop.circle"
        case .desktop: "menubar.dock.rectangle"
        case .documents: "doc"
        case .downloads: "arrow.down.circle"
        case .folder: "folder"
        }
    }
}
