import AppKit
import KamiroKit
import SwiftUI

/// The Finder's seven color tags, named in the Mac's language as the Finder names them (S-027).
enum ColorTag: Int, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, purple, gray

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .red: String(localized: "Red")
        case .orange: String(localized: "Orange")
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .blue: String(localized: "Blue")
        case .purple: String(localized: "Purple")
        case .gray: String(localized: "Gray")
        }
    }

    var color: NSColor {
        switch self {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .gray: .systemGray
        }
    }

    var place: VirtualPlace { .tag(name) }

    /// A dot for menus.
    var dot: NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            self.color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.accessibilityDescription = name
        return image
    }
}

extension BrowserModel {
    /// The window shows a tag's items, not a folder.
    var place: VirtualPlace? { VirtualPlace(folder) }
    var isVirtual: Bool { place != nil }

    /// A place's name for menus and the title: a folder's name, or a tag's.
    static func name(of url: URL) -> String {
        VirtualPlace(url)?.title ?? FileManager.default.displayName(atPath: url.path)
    }

    /// Adds the tag to every selected item, or takes it off when they all have it.
    func toggleTag(_ name: String) {
        let urls = Array(selection)
        guard !urls.isEmpty else { return }
        let present = !urls.allSatisfy { Tags.of($0).contains(name) }
        do {
            try Tags.set(name, present: present, on: urls)
            log.post(.info, "\(present ? "Tagged" : "Untagged") \(urls.count) items \(name)", source: "Tags")
        } catch {
            log.post(.error, "Couldn't change the tag \(name): \(error.localizedDescription)", source: "Tags")
        }
        refresh()
    }

    /// The right-click menu's Tags submenu: the color tags, then the selection's other tags,
    /// checked when every selected item has the tag.
    func tagsMenu() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "Tags"), action: nil, keyEquivalent: "")
        let menu = NSMenu()
        let tagged = selection.map(Tags.of)
        func add(_ name: String, image: NSImage?) {
            let entry = MenuAction.item(name) { [weak self] in self?.toggleTag(name) }
            entry.image = image
            let count = tagged.filter { $0.contains(name) }.count
            entry.state = count == 0 ? .off : count == tagged.count ? .on : .mixed
            menu.addItem(entry)
        }
        for tag in ColorTag.allCases { add(tag.name, image: tag.dot) }
        let others = Set(tagged.flatMap { $0 }).subtracting(ColorTag.allCases.map(\.name)).sorted()
        if !others.isEmpty {
            menu.addItem(.separator())
            for name in others { add(name, image: nil) }
        }
        item.submenu = menu
        return item
    }
}

/// The sidebar's Tags section: a click shows every item with that tag.
struct TagsSection: View {
    var body: some View {
        Section("Tags") {
            ForEach(ColorTag.allCases) { tag in
                Label {
                    Text(tag.name)
                } icon: {
                    Circle()
                        .fill(Color(nsColor: tag.color))
                        .frame(width: 10, height: 10)
                }
                .tag(tag.place.url)
            }
        }
    }
}
