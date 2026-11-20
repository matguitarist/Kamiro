import AppKit
import KamiroKit
import Quartz
import SwiftUI

/// The last column for a selected file: its preview, name, kind, size and date. SwiftUI
/// lays it out in whatever width the browser gives the column.
final class ColumnPreview: NSHostingController<PreviewColumn> {
    init(item: FileItem) {
        super.init(rootView: PreviewColumn(item: item))
        sizingOptions = []
        // The browser sets the column's size on this view; it starts at zero otherwise.
        view.frame = NSRect(x: 0, y: 0, width: 240, height: 480)
        view.autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

struct PreviewColumn: View {
    let item: FileItem

    var body: some View {
        VStack(spacing: Space.md) {
            // The preview takes all the room the column has: a whole page of text, or the
            // picture as large as it fits.
            QuickLookPreview(url: item.url, style: .normal)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Radius.control))
            VStack(spacing: Space.xs) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(3)
                Group {
                    Text(summary)
                    if let modified = item.modified {
                        Text("Modified \(modified.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summary: String {
        let kind = KindCache.shared.kind(of: item)
        guard let size = item.size else { return kind }
        return "\(kind) – \(size.bytesText)"
    }
}

/// Quick Look's own preview of one file.
struct QuickLookPreview: NSViewRepresentable {
    let url: URL
    /// .compact draws a small thumbnail-like card; .normal shows the whole document, scrollable.
    var style: QLPreviewViewStyle = .compact

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: style) ?? QLPreviewView()
        view.shouldCloseWithWindow = false
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url { view.previewItem = url as NSURL }
    }
}

extension NSImage {
    /// The same image at half opacity, for hidden and cut items.
    var dimmed: NSImage {
        NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.5)
            return true
        }
    }
}
