import AppKit
import KamiroKit
import SwiftUI

/// Show Disk Usage (S-063): a map of what fills a folder, at every depth, beside a list of its
/// biggest items. Double-click a folder to zoom in; the path bar or ⌘↑ zooms out.
struct DiskUsageView: View {
    @State private var model: DiskUsageModel
    @Environment(\.openWindow) private var openWindow

    init(url: URL) {
        _model = State(initialValue: DiskUsageModel(folder: url))
    }

    var body: some View {
        content
            .frame(minWidth: 640, minHeight: 420)
            .navigationTitle(String(localized: "Disk Usage — \(FileManager.default.displayName(atPath: model.folder.path))"))
            .toolbar {
                ToolbarItemGroup {
                    Button("Enclosing Folder", systemImage: "chevron.up") { model.zoomOut() }
                        .keyboardShortcut(.upArrow, modifiers: .command)
                        .disabled(model.trail.count < 2)
                        .help("Show the folder this one is in")
                    if model.state == .measuring {
                        Button("Stop", systemImage: "xmark") { model.stop() }
                    } else {
                        Button("Measure Again", systemImage: "arrow.clockwise") { model.start() }
                    }
                }
            }
            .noInitialFocus()
            .task {
                model.openBrowser = { start in openWindow(id: KamiroApp.browserID, value: start) }
                DiskUsageModel.latest = model
                if model.root == nil { model.start() }
            }
            .onDisappear { model.stop() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .measuring:
            VStack(spacing: Space.md) {
                ProgressView()
                Text("Measuring…")
                    .font(.headline)
                Text(progressText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .denied:
            ContentUnavailableView("Kamiro can’t read this folder.", systemImage: "lock")
        case .stopped:
            ContentUnavailableView {
                Label("Stopped", systemImage: "stop.circle")
            } actions: {
                Button("Measure Again") { model.start() }
            }
        case .ready:
            if let shown = model.shown, !shown.children.isEmpty {
                ready(shown)
            } else {
                ContentUnavailableView("This folder is empty.", systemImage: "folder")
            }
        }
    }

    private var progressText: String {
        let bytes = ByteCountFormatter.string(fromByteCount: model.progress.bytes, countStyle: .file)
        return String(localized: "\(model.progress.items.formatted()) items, \(bytes)")
    }

    private func ready(_ shown: DiskNode) -> some View {
        VStack(spacing: 0) {
            pathBar(shown)
            Divider()
            HStack(spacing: 0) {
                DiskMap(model: model, folder: shown)
                    .padding(Space.sm)
                Divider()
                DiskList(model: model, folder: shown)
                    .frame(width: 280)
            }
            Divider()
            footer(shown)
        }
    }

    private func pathBar(_ shown: DiskNode) -> some View {
        HStack(spacing: Space.xs) {
            ForEach(Array(model.trail.enumerated()), id: \.element.id) { index, node in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                Button(node.name) { model.zoom(toLevel: index) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(index == model.trail.count - 1 ? .primary : .secondary)
                    .disabled(index == model.trail.count - 1)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.md)
            Text(DiskText.summary(shown))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
    }

    private func footer(_ shown: DiskNode) -> some View {
        HStack(spacing: Space.lg) {
            Group {
                if let node = model.hovered ?? model.selected {
                    Text(DiskText.share(node, of: shown))
                } else {
                    Text("Double-click a folder to look inside it.")
                }
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            Spacer(minLength: Space.md)
            DiskLegend(folder: shown)
                .fixedSize()
        }
        .font(.callout)
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
    }
}

/// The words the map, the list and the footer share.
enum DiskText {
    static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    static func name(_ node: DiskNode) -> String {
        node.isSmallerItems ? String(localized: "Smaller items (\(node.items.formatted()))") : node.name
    }

    static func summary(_ node: DiskNode) -> String {
        String(localized: "\(size(node.size)) in \(node.items.formatted()) items")
    }

    static func percent(_ node: DiskNode, of folder: DiskNode) -> String {
        guard folder.size > 0 else { return "" }
        return (Double(node.size) / Double(folder.size)).formatted(.percent.precision(.fractionLength(0...1)))
    }

    static func share(_ node: DiskNode, of folder: DiskNode) -> String {
        "\(name(node)) — \(size(node.size)) (\(percent(node, of: folder)))"
    }
}

extension DiskCategory {
    var title: String {
        switch self {
        case .folder: String(localized: "Folders")
        case .pictures: String(localized: "Pictures")
        case .movies: String(localized: "Movies")
        case .music: String(localized: "Music")
        case .documents: String(localized: "Documents")
        case .apps: String(localized: "Apps")
        case .archives: String(localized: "Archives")
        case .code: String(localized: "Code")
        case .other: String(localized: "Other")
        case .smaller: String(localized: "Smaller items")
        }
    }

    /// The system's own named colors, so they follow light, dark and Increase Contrast.
    var color: Color {
        switch self {
        case .folder: Color(nsColor: .systemGray)
        case .pictures: Color(nsColor: .systemPurple)
        case .movies: Color(nsColor: .systemPink)
        case .music: Color(nsColor: .systemOrange)
        case .documents: Color(nsColor: .systemBlue)
        case .apps: Color(nsColor: .systemGreen)
        case .archives: Color(nsColor: .systemBrown)
        case .code: Color(nsColor: .systemTeal)
        case .other: Color(nsColor: .systemIndigo)
        case .smaller: Color(nsColor: .systemGray)
        }
    }
}

/// The colors in use in the shown folder, in a fixed order.
struct DiskLegend: View {
    let folder: DiskNode

    var body: some View {
        let used = Set(Self.categories(in: folder, depth: 3))
        HStack(spacing: Space.md) {
            ForEach(DiskCategory.allCases.filter { used.contains($0) && $0 != .folder }, id: \.self) { category in
                HStack(spacing: Space.xs) {
                    Circle()
                        .fill(category.color.opacity(0.6))
                        .frame(width: Space.sm, height: Space.sm)
                        .accessibilityHidden(true)
                    Text(category.title)
                }
            }
        }
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private static func categories(in node: DiskNode, depth: Int) -> [DiskCategory] {
        node.children.flatMap { child in
            [child.category] + (depth > 1 && child.isFolder ? categories(in: child, depth: depth - 1) : [])
        }
    }
}

/// The shown folder's items, biggest first: the keyboard's way through the map.
struct DiskList: View {
    @Bindable var model: DiskUsageModel
    let folder: DiskNode

    var body: some View {
        List(selection: $model.selection) {
            ForEach(folder.children) { node in
                HStack(spacing: Space.sm) {
                    icon(node)
                    Text(DiskText.name(node))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: Space.xs)
                    Text(DiskText.size(node.size))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .help(DiskText.share(node, of: folder))
                .tag(node.id)
            }
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let node = folder.children.first(where: { $0.id == id }) {
                DiskItemMenu(model: model, node: node)
            }
        } primaryAction: { ids in
            guard let id = ids.first, let node = folder.children.first(where: { $0.id == id }) else { return }
            if node.isFolder { model.zoom(into: node) } else { model.open(node) }
        }
    }

    @ViewBuilder
    private func icon(_ node: DiskNode) -> some View {
        if node.isSmallerItems {
            Image(systemName: "ellipsis.circle")
                .frame(width: Space.lg, height: Space.lg)
                .foregroundStyle(.secondary)
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path))
                .resizable()
                .frame(width: Space.lg, height: Space.lg)
        }
    }
}

/// What a tile or row's right-click menu offers.
struct DiskItemMenu: View {
    let model: DiskUsageModel
    let node: DiskNode

    var body: some View {
        if node.isFolder, node.id != model.shown?.id {
            Button("Zoom In", systemImage: "plus.magnifyingglass") { model.zoom(into: node) }
        }
        if node.isFolder || node.isSmallerItems {
            Button("Open in Kamiro", systemImage: "folder") { model.open(node) }
        } else {
            Button("Open", systemImage: "arrow.up.forward.app") { model.open(node) }
        }
        if !node.isSmallerItems {
            Button("Show in Kamiro", systemImage: "magnifyingglass") { model.showInBrowser(node) }
            Button("Copy Path", systemImage: "link") { model.copyPath(node) }
        }
    }
}
