import KamiroKit
import SwiftUI

/// The inspector (⌥⌘I, S-025): a pane at the right of the list with a preview and the
/// selection's details. Nothing selected shows the folder itself.
struct InspectorView: View {
    let model: BrowserModel

    var body: some View {
        ScrollView {
            content
                .padding(Space.lg)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.automatic)
    }

    @ViewBuilder
    private var content: some View {
        let chosen = model.items.filter { model.selection.contains($0.url) }
        if chosen.count > 1 {
            SeveralItems(count: chosen.count, bytes: model.counts.selectedBytes)
        } else if let item = chosen.first ?? FolderReader.item(at: model.folder) {
            OneItem(item: item, size: item.size ?? model.folderSizes[item.url])
                .id(item.url)
        }
    }
}

/// One item: its preview, name and kind, then Information.
private struct OneItem: View {
    let item: FileItem
    let size: Int64?
    @State private var media = MediaFacts()
    @State private var cloud: CloudStatus?

    var body: some View {
        VStack(spacing: Space.md) {
            QuickLookPreview(url: item.url)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxHeight: 240)
                .accessibilityHidden(true)
            VStack(spacing: Space.xs) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                Text(KindCache.shared.kind(of: item))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Information")
                    .font(.subheadline.weight(.semibold))
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.sm, verticalSpacing: Space.xs) {
                    ForEach(InspectorFacts.rows(item: item, size: size, media: media, tags: ItemFacts.tags(of: item.url),
                                                cloud: cloud)) { row in
                        GridRow {
                            Text(row.label)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                            Text(row.value)
                                .lineLimit(row.isPath ? 2 : nil)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .help(row.isPath ? row.value : "")
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .font(.callout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: item.url) {
            media = await ItemFacts.media(of: item.url)
            cloud = await Self.cloudStatus(of: item.url)
            InspectorProbe.shown = [item.name] + InspectorFacts.rows(item: item, size: size, media: media,
                                                                     tags: ItemFacts.tags(of: item.url), cloud: cloud).map(\.label)
        }
        .onDisappear { InspectorProbe.shown = [] }
    }

    @concurrent
    nonisolated private static func cloudStatus(of url: URL) async -> CloudStatus? { CloudStatus.read(url) }
}

/// What the inspector last showed (the name, then the Information labels), for the self-test:
/// SwiftUI builds the pane's accessibility only for an outside reader.
@MainActor
enum InspectorProbe {
    static var shown: [String] = []
}

/// Several items: how many and their total size.
private struct SeveralItems: View {
    let count: Int
    let bytes: Int64?

    var body: some View {
        VStack(spacing: Space.sm) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.vertical, Space.lg)
                .accessibilityHidden(true)
            Text("\(count) items")
                .font(.headline)
            if let bytes {
                Text(bytes.bytesText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The Information rows, in order; facts that don't apply are left out.
enum InspectorFacts {
    struct Row: Identifiable, Equatable {
        var id: String { label }
        let label: String
        let value: String
        var isPath = false
    }

    static func rows(item: FileItem, size: Int64?, media: MediaFacts, tags: [String], cloud: CloudStatus? = nil) -> [Row] {
        var rows: [Row] = [Row(label: String(localized: "Kind"), value: KindCache.shared.kind(of: item))]
        rows.append(Row(label: String(localized: "Size"), value: size?.bytesText ?? "—"))
        if let text = media.dimensionsText { rows.append(Row(label: String(localized: "Dimensions"), value: text)) }
        if let text = media.durationText { rows.append(Row(label: String(localized: "Duration"), value: text)) }
        if let pages = media.pages { rows.append(Row(label: String(localized: "Pages"), value: pages.formatted())) }
        if let date = item.created { rows.append(Row(label: String(localized: "Created"), value: format(date))) }
        if let date = item.modified { rows.append(Row(label: String(localized: "Modified"), value: format(date))) }
        if let date = item.added { rows.append(Row(label: String(localized: "Added"), value: format(date))) }
        if let cloud { rows.append(Row(label: String(localized: "Cloud Status"), value: cloud.title)) }
        if !tags.isEmpty { rows.append(Row(label: String(localized: "Tags"), value: tags.formatted(.list(type: .and)))) }
        rows.append(Row(label: String(localized: "Where"), value: PathInput.display(item.url.deletingLastPathComponent()),
                        isPath: true))
        return rows
    }

    private static func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
