import KamiroKit
import Observation
import SwiftUI

// MARK: - Icons for servers and disks (S-056)

/// The icons people picked for servers and disks, kept in the settings and shared by every window.
@MainActor @Observable
final class IconStore {
    static let shared = IconStore()
    private(set) var icons = PlaceIcons()

    private init() { reload() }

    /// Reads the settings again (the self-test starts from none).
    func reload() {
        icons = PlaceIcons(saved: Prefs.defaults.dictionary(forKey: Prefs.placeIcons) as? [String: String] ?? [:])
    }

    func set(_ icon: PlaceIcon?, for key: String) {
        icons.set(icon, for: key)
        Prefs.defaults.set(icons.saved, forKey: Prefs.placeIcons)
    }

    func symbol(for volume: Volume) -> String {
        (icons.icon(for: PlaceIcons.key(volume: volume)) ?? .automatic(for: volume)).symbol
    }

    func symbol(server: URL) -> String {
        (icons.icon(for: PlaceIcons.key(server: server)) ?? .server).symbol
    }
}

extension PlaceIcon {
    var title: String {
        switch self {
        case .network: String(localized: "Network")
        case .server: String(localized: "Server")
        case .nas: String(localized: "NAS")
        case .pc: String(localized: "PC")
        case .mac: String(localized: "Mac")
        case .laptop: String(localized: "Laptop")
        case .cloud: String(localized: "Cloud")
        case .internalDrive: String(localized: "Internal Disk")
        case .externalDrive: String(localized: "External Disk")
        }
    }
}

/// The right-click menu's Icon submenu: Automatic, then every icon, the current one checked.
struct IconMenu: View {
    let key: String
    let automatic: PlaceIcon
    private var store: IconStore { .shared }

    var body: some View {
        Picker(selection: Binding { store.icons.icon(for: key) } set: { store.set($0, for: key) }) {
            Label(String(localized: "Automatic (\(automatic.title))"), systemImage: automatic.symbol)
                .tag(PlaceIcon?.none)
            Divider()
            ForEach(PlaceIcon.allCases) { icon in
                Label(icon.title, systemImage: icon.symbol).tag(PlaceIcon?.some(icon))
            }
        } label: {
            Label("Icon", systemImage: "photo.badge.checkmark")
        }
    }
}
