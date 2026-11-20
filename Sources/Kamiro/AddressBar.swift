import AppKit
import KamiroKit
import SwiftUI

/// The path in the toolbar: crumbs to click, each with a menu of its subfolders, and a
/// field for typing a path (⌘L, ⇧⌘G, or a click on the empty part).
struct AddressBar: View {
    @Bindable var model: BrowserModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Group {
            if model.isEditingPath { field } else { crumbs }
        }
        .frame(minWidth: 320, idealWidth: 560, maxWidth: 720)
    }

    // MARK: Crumbs

    private enum Entry: Identifiable {
        case crumb(URL, last: Bool)
        case more([URL])
        var id: String {
            switch self {
            case .crumb(let url, _): url.path
            case .more: "…"
            }
        }
    }

    /// Long paths keep the disk and the last three folders; "…" holds the rest.
    private var entries: [Entry] {
        let all = Location(model.folder).crumbs
        let tail = all.count > 5 ? Array(all.suffix(3)) : Array(all.dropFirst())
        var list: [Entry] = all.first.map { [.crumb($0, last: all.count == 1)] } ?? []
        if all.count > 5 { list.append(.more(Array(all.dropFirst().dropLast(3)))) }
        list += tail.map { .crumb($0, last: $0 == all.last) }
        return list
    }

    private var crumbs: some View {
        HStack(spacing: 0) {
            ForEach(entries) { entry in
                switch entry {
                case .crumb(let url, let last):
                    Crumb(url: url, isFirst: url.path == "/" || Location(url).parent == nil, isLast: last) { model.go(to: $0) }
                case .more(let hidden):
                    Menu {
                        ForEach(hidden, id: \.self) { url in
                            Button(FileManager.default.displayName(atPath: url.path)) { model.go(to: url) }
                        }
                        Divider()
                        Button("Show Full Path") { model.beginEditingPath() }
                    } label: {
                        Text(verbatim: "…")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Show the folders in between")
                    Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: Space.lg)
        }
        .padding(.horizontal, Space.sm)
        .contentShape(Rectangle())
        .onTapGesture { model.beginEditingPath() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Path: \(Location(model.folder).crumbs.map { FileManager.default.displayName(atPath: $0.path) }.joined(separator: ", "))"))
    }

    // MARK: Field

    private var suggestions: [String] {
        PathInput.completions(for: model.pathText, relativeTo: model.folder)
    }

    private var field: some View {
        TextField("Type a path", text: $model.pathText)
            .textFieldStyle(.plain)
            .padding(.horizontal, Space.sm)
            .focused($fieldFocused)
            .onSubmit { model.submitPath() }
            .onExitCommand { model.cancelEditingPath() }
            .onKeyPress(.tab) {
                if let common = PathInput.commonPrefix(suggestions), common.count > model.pathText.count {
                    model.pathText = common
                }
                return .handled
            }
            .textInputSuggestions {
                ForEach(suggestions, id: \.self) { suggestion in
                    Text(verbatim: suggestion).textInputCompletion(suggestion)
                }
            }
            .modifier(Shake(count: model.shakeToken))
            .animation(.default, value: model.shakeToken)
            .popover(isPresented: Binding(get: { model.pathError != nil }, set: { if !$0 { model.pathError = nil } }),
                     arrowEdge: .bottom) {
                Label(model.pathError ?? "", systemImage: "exclamationmark.triangle")
                    .padding(Space.md)
            }
            .onAppear { fieldFocused = true }
            .onChange(of: fieldFocused) {
                // Clicking elsewhere puts the crumbs back.
                if !fieldFocused, model.isEditingPath, model.pathError == nil { model.cancelEditingPath() }
            }
            .accessibilityLabel("Path")
    }
}

/// One folder in the path: its name, then a chevron with its subfolders.
private struct Crumb: View {
    let url: URL
    let isFirst: Bool
    let isLast: Bool
    let go: (URL) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                go(url)
            } label: {
                HStack(spacing: Space.xs) {
                    if isFirst {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    Text(verbatim: FileManager.default.displayName(atPath: url.path))
                        .fontWeight(isLast ? .semibold : .regular)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isLast ? .primary : .secondary)
            Button {
                SubfolderMenu.show(for: url, go: go)
            } label: {
                Image(systemName: "chevron.compact.right")
                    .padding(.horizontal, Space.xs)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tertiary)
            .help(String(localized: "Show the folders in \(FileManager.default.displayName(atPath: url.path))"))
        }
    }
}

/// The chevron's menu, built when it opens so the toolbar never lists folders it won't show.
enum SubfolderMenu {
    static func show(for folder: URL, go: @escaping (URL) -> Void) {
        let menu = NSMenu()
        let folders = (try? FolderReader.list(folder))?.filter(\.isFolder) ?? []
        if folders.isEmpty {
            let empty = NSMenuItem(title: String(localized: "No Folders"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for item in ItemOrder().sorted(folders).prefix(300) {
            let entry = MenuAction.item(item.name) { go(item.url) }
            entry.image = IconCache.shared.icon(for: item)
            menu.addItem(entry)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// A menu item that runs a closure. The item keeps its action alive in representedObject.
final class MenuAction: NSObject {
    private let handler: () -> Void

    private init(_ handler: @escaping () -> Void) { self.handler = handler }

    static func item(_ title: String, handler: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(handler)
        let item = NSMenuItem(title: title, action: #selector(fire), keyEquivalent: "")
        item.target = action
        item.representedObject = action
        return item
    }

    @objc private func fire() { handler() }
}

/// Shakes the field when a path doesn't exist.
private struct Shake: GeometryEffect {
    var count: Int
    var animatableData: CGFloat

    init(count: Int) {
        self.count = count
        animatableData = CGFloat(count)
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: Space.sm * sin(animatableData * .pi * 4), y: 0))
    }
}
