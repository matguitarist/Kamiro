import AppKit
import KamiroKit
import SwiftUI

/// Properties (⌘I, ⌥↩, S-026): one item's full details in a window of its own, Windows'
/// Properties with the Mac's look. Locked and Hidden apply as soon as they're switched.
struct PropertiesView: View {
    let url: URL
    @State private var item: FileItem?
    @State private var summary: (bytes: Int64, items: Int)?
    @State private var measuring = false
    @State private var locked = false
    @State private var hidden = false
    @State private var problem: String?
    /// Set for a disk's top folder, which shows its format and space instead of a size.
    @State private var disk: VolumeFacts?
    /// Opens With: the app picked, and the one that opens this kind now (S-036).
    @State private var chosenApp: URL?
    @State private var defaultApp: URL?

    var body: some View {
        Form {
            if let item, let disk {
                header(item, kind: String(localized: "Disk"))
                Section("General") {
                    ForEach(PropertiesFacts.rows(disk), id: \.label) { row in
                        LabeledContent(row.label, value: row.value)
                    }
                    if let used = disk.used, let capacity = disk.capacity, capacity > 0 {
                        ProgressView(value: Double(used), total: Double(capacity))
                            .accessibilityLabel("Used")
                    }
                }
                if let permissions = Permissions.of(url) {
                    Section("Sharing & Permissions") {
                        LabeledContent(permissions.owner, value: permissions.ownerAccess.title)
                        LabeledContent(permissions.group, value: permissions.groupAccess.title)
                        LabeledContent("Everyone", value: permissions.everyoneAccess.title)
                    }
                }
            } else if let item {
                header(item)
                Section("General") {
                    LabeledContent("Size") { sizeText(item) }
                    LabeledContent("Where") {
                        Text(PathInput.display(url.deletingLastPathComponent()))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(url.deletingLastPathComponent().path)
                    }
                    if let date = item.created { LabeledContent("Created", value: date.formatted(date: .long, time: .shortened)) }
                    if let date = item.modified { LabeledContent("Modified", value: date.formatted(date: .long, time: .shortened)) }
                }
                if PropertiesFacts.opener(of: item) != nil {
                    OpensWithSection(url: url, chosen: $chosenApp, current: $defaultApp)
                }
                Section("Options") {
                    Toggle("Locked", isOn: $locked)
                        .onChange(of: locked) { _, value in apply { try ItemFlags.setLocked(value, url) } }
                    Toggle("Hidden", isOn: $hidden)
                        .onChange(of: hidden) { _, value in apply { try ItemFlags.setHidden(value, url) } }
                    if let problem {
                        Text(problem)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                if let permissions = Permissions.of(url) {
                    Section("Sharing & Permissions") {
                        LabeledContent(permissions.owner, value: permissions.ownerAccess.title)
                        LabeledContent(permissions.group, value: permissions.groupAccess.title)
                        LabeledContent("Everyone", value: permissions.everyoneAccess.title)
                    }
                }
            } else {
                Text("This item isn't there anymore.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .navigationTitle(String(localized: "\(disk?.name ?? url.lastPathComponent) Properties"))
        .task(id: url) { await load() }
    }

    private func header(_ item: FileItem, kind: String? = nil) -> some View {
        HStack(spacing: Space.md) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(3)
                    .textSelection(.enabled)
                Text(kind ?? KindCache.shared.kind(of: item))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func sizeText(_ item: FileItem) -> some View {
        if let text = PropertiesFacts.size(item: item, summary: summary) {
            Text(text)
        } else if measuring {
            HStack(spacing: Space.xs) {
                ProgressView().controlSize(.small)
                Text("Calculating…")
            }
        } else {
            Text(verbatim: "—")
        }
    }

    private func apply(_ change: () throws -> Void) {
        do {
            try change()
            problem = nil
        } catch {
            problem = String(localized: "Kamiro couldn't change this item: \(error.localizedDescription)")
        }
        locked = ItemFlags.isLocked(url)
        hidden = ItemFlags.isHidden(url)
    }

    private func load() async {
        item = FolderReader.item(at: url)
        disk = Volumes.facts(at: url)
        locked = ItemFlags.isLocked(url)
        hidden = ItemFlags.isHidden(url)
        PropertiesProbe.shown[url] = item.map { PropertiesFacts.size(item: $0, summary: nil) ?? "" }
        if let disk {
            // A whole disk isn't walked: it tells its own space.
            PropertiesProbe.shown[url] = PropertiesFacts.rows(disk).map(\.value).joined(separator: ", ")
            return
        }
        guard let item, item.size == nil else { return }
        measuring = true
        summary = await Self.summary(of: url)
        measuring = false
        PropertiesProbe.shown[url] = PropertiesFacts.size(item: item, summary: summary) ?? "—"
    }

    @concurrent
    nonisolated private static func summary(of url: URL) async -> (bytes: Int64, items: Int)? {
        try? FolderSize.summary(url)
    }
}

/// Opens With in Properties: pick an app, then Change All… makes it open every file of this
/// kind, after asking, like the Finder's Get Info.
private struct OpensWithSection: View {
    let url: URL
    @Binding var chosen: URL?
    @Binding var current: URL?

    var body: some View {
        let apps = ItemActions.apps(for: [url])
        let list = (apps.default.map { [$0] } ?? []) + apps.others
        Section("Opens With") {
            Picker("Application", selection: $chosen) {
                ForEach(list, id: \.self) { app in
                    Label { Text(verbatim: ItemActions.appName(app)) } icon: { Image(nsImage: Self.icon(app)) }
                        .tag(Optional(app))
                }
            }
            LabeledContent {
                Button("Change All…") {
                    guard let chosen, ItemActions.confirmMakeDefault(chosen, for: [url]) else { return }
                    current = chosen
                }
                .disabled(chosen == nil || chosen == current)
            } label: {
                Text("Use this app for every “\(ItemActions.kindName([url]))” file.")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            current = apps.default
            chosen = apps.default
        }
    }

    private static func icon(_ app: URL) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: app.path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}

/// The words Properties shows, kept apart from the view so the self-test can read them.
enum PropertiesFacts {
    /// "135 KB (138,240 bytes)" for a file, "193 KB on disk, 4 items" for a folder.
    static func size(item: FileItem, summary: (bytes: Int64, items: Int)?) -> String? {
        if let size = item.size {
            return String(localized: "\(size.bytesText) (\(size.formatted()) bytes)")
        }
        guard let summary else { return nil }
        if summary.items == 1 { return String(localized: "\(summary.bytes.bytesText) on disk, 1 item") }
        return String(localized: "\(summary.bytes.bytesText) on disk, \(summary.items) items")
    }

    /// A disk's lines: format, capacity, available and used space.
    static func rows(_ disk: VolumeFacts) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let format = disk.format { rows.append((String(localized: "Format"), format)) }
        if let capacity = disk.capacity { rows.append((String(localized: "Capacity"), capacity.bytesText)) }
        if let available = disk.available { rows.append((String(localized: "Available"), available.bytesText)) }
        if let used = disk.used { rows.append((String(localized: "Used"), used.bytesText)) }
        if disk.isReadOnly { rows.append((String(localized: "Access"), String(localized: "Read only"))) }
        return rows
    }

    /// The app that opens this file; none for folders and apps.
    static func opener(of item: FileItem) -> (name: String, icon: NSImage)? {
        guard !item.isFolder, item.url.pathExtension != "app",
              let app = NSWorkspace.shared.urlForApplication(toOpen: item.url) else { return nil }
        let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
        return (name, NSWorkspace.shared.icon(forFile: app.path))
    }
}

/// What each Properties window shows as its size, for the self-test.
@MainActor
enum PropertiesProbe {
    static var shown: [URL: String] = [:]
}

extension Permissions.Access {
    var title: String {
        switch self {
        case .readWrite: String(localized: "Read & Write")
        case .readOnly: String(localized: "Read only")
        case .writeOnly: String(localized: "Write only")
        case .none: String(localized: "No Access")
        }
    }
}
