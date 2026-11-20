import AppKit
import KamiroKit

/// View › Show Hidden Files (⇧⌘.), S-024: one choice for every window, kept between launches.
/// Hidden items (dotfiles and items with the hidden flag) show at half opacity.
enum HiddenFiles {
    static let changed = Notification.Name("Kamiro.hiddenFilesChanged")

    static var shown: Bool { Prefs.defaults.bool(forKey: Prefs.showHidden) }

    static func toggle() { set(!shown) }

    static func set(_ show: Bool) {
        guard show != shown else { return }
        Prefs.defaults.set(show, forKey: Prefs.showHidden)
        MenuState.shared.showsHidden = show
        NotificationCenter.default.post(name: changed, object: nil)
    }
}
