import AppKit
import KamiroKit
import SwiftUI

/// The Home page (S-031): pinned folders, files opened lately, and the volumes with their
/// free space. New windows open here.
struct HomeView: View {
    let model: BrowserModel
    @State private var recents: [URL] = []
    @State private var volumes: [VolumeSpace] = []
    private var pins: PinStore { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                if !pins.list.urls.isEmpty {
                    section("Pinned", probe: "pinned") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: Space.md)], spacing: Space.md) {
                            ForEach(pins.list.urls, id: \.self) { url in
                                HomeTile(url: url, title: GoPlace.name(of: url)) { model.go(to: url) }
                                    .contextMenu {
                                        Button("Open in New Tab", systemImage: "plus.square.on.square") { model.openWindow?(url, true) }
                                        Divider()
                                        Button("Unpin", systemImage: "pin.slash") { pins.unpin(url) }
                                    }
                            }
                        }
                    }
                }
                section("Recent Files", probe: "recents") {
                    if recents.isEmpty {
                        Text("Files you open show here.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(recents, id: \.self) { url in
                                RecentRow(url: url, model: model)
                                    // An overlay, so the hairline doesn't push the rows off the grid.
                                    .overlay(alignment: .bottom) {
                                        if url != recents.last { Divider().padding(.leading, Space.section + Space.md) }
                                    }
                            }
                        }
                        .padding(.vertical, Space.xs)
                        .cardBackground(Radius.banner)
                    }
                }
                section("Locations", probe: "locations") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: Space.md)], spacing: Space.md) {
                        ForEach(volumes) { space in
                            HomeTile(url: space.volume.url, title: space.volume.name, detail: space.detail,
                                     fraction: space.usedFraction) { model.go(to: space.volume.url) }
                        }
                    }
                }
            }
            .padding(Space.margin)
            .frame(maxWidth: .infinity, alignment: .leading)
            .gridArea("home")
        }
        .task(id: model.itemsVersion) { await load() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            Task { await load() }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            Task { await load() }
        }
    }

    private func section(_ title: LocalizedStringKey, probe: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(title)
                .font(.headline)
                .gridProbe(probe, area: "home")
            content()
        }
    }

    private func load() async {
        // Test runs look in the sample tree, which Spotlight doesn't index.
        let root = Store.isOverridden ? Store.seedFolder : nil
        async let files = Task.detached(priority: .utility) {
            root.map { RecentFiles.walk(in: $0, limit: 10) } ?? RecentFiles.spotlight(limit: 10)
        }.value
        async let spaces = Task.detached(priority: .utility) {
            Volumes.mounted().map { VolumeSpace(volume: $0, space: Volumes.space(at: $0.url)) }
        }.value
        (recents, volumes) = await (files, spaces)
    }
}

/// A volume and how full it is.
struct VolumeSpace: Identifiable, Sendable {
    let volume: Volume
    let space: (available: Int64, total: Int64)?
    var id: URL { volume.url }

    var usedFraction: Double? {
        guard let space, space.total > 0 else { return nil }
        return Double(space.total - space.available) / Double(space.total)
    }

    var detail: String? {
        guard let space else { return nil }
        let free = ByteCountFormatter.string(fromByteCount: space.available, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: space.total, countStyle: .file)
        return String(localized: "\(free) free of \(total)")
    }
}

/// A folder or volume on the Home page: its icon and name, and for a volume, its free space.
private struct HomeTile: View {
    let url: URL
    let title: String
    var detail: String?
    var fraction: Double?
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let fraction {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .controlSize(.small)
                    }
                    if let detail {
                        Text(detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .cardBackground(Radius.banner, highlighted: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(PathInput.display(url))
        .accessibilityLabel(detail.map { "\(title), \($0)" } ?? title)
    }
}

/// One recent file: a click opens it in its app.
private struct RecentRow: View {
    let url: URL
    let model: BrowserModel
    @State private var hovered = false

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            HStack(spacing: Space.md) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Space.lg)
                Text(PathInput.display(url.deletingLastPathComponent()))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .contentShape(.rect)
            .background(hovered ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Open", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(url) }
            Button("Show in Enclosing Folder", systemImage: "folder") {
                model.go(to: url.deletingLastPathComponent(), select: [url])
            }
        }
    }
}
