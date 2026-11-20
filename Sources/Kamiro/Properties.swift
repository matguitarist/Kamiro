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

    var body: some View {
        Form {
            if let item {
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
                if let app = PropertiesFacts.opener(of: item) {
                    Section("Opens With") {
                        LabeledContent("Application") {
                            HStack(spacing: Space.xs) {
                                Image(nsImage: app.icon).resizable().frame(width: 16, height: 16).accessibilityHidden(true)
                                Text(app.name)
                            }
                        }
                    }
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
        .navigationTitle(String(localized: "\(url.lastPathComponent) Properties"))
        .task(id: url) { await load() }
    }

    private func header(_ item: FileItem) -> some View {
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
                Text(KindCache.shared.kind(of: item))
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
        locked = ItemFlags.isLocked(url)
        hidden = ItemFlags.isHidden(url)
        PropertiesProbe.shown[url] = item.map { PropertiesFacts.size(item: $0, summary: nil) ?? "" }
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
