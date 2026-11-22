import KamiroKit
import SwiftUI

/// The treemap (S-063): each item a tile in proportion to its size, folders opened in place
/// while there's room, colored by what the files are.
struct DiskMap: View {
    @Bindable var model: DiskUsageModel
    let folder: DiskNode
    @State private var cache = TileCache()

    var body: some View {
        GeometryReader { geometry in
            let tiles = cache.tiles(for: folder, size: geometry.size)
            Canvas { context, _ in
                for tile in tiles { draw(tile, in: &context) }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): model.hovered = Self.tile(at: point, in: tiles)?.node
                case .ended: model.hovered = nil
                }
            }
            .gesture(SpatialTapGesture(count: 2).onEnded { value in
                if let tile = Self.tile(at: value.location, in: tiles) { model.zoom(into: tile.node) }
            }.exclusively(before: SpatialTapGesture().onEnded { value in
                model.selection = Self.tile(at: value.location, in: tiles)?.node.id
            }))
            .contextMenu {
                if let node = model.hovered { DiskItemMenu(model: model, node: node) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Disk usage map")
            .accessibilityChildren {
                ForEach(tiles.filter { $0.depth == 0 }, id: \.node.id) { tile in
                    Rectangle()
                        .frame(width: tile.rect.width, height: tile.rect.height)
                        .position(x: tile.rect.midX, y: tile.rect.midY)  // grid: ok accessibility frames follow the tiles
                        .accessibilityLabel("\(DiskText.name(tile.node)), \(DiskText.size(tile.node.size))")
                }
            }
        }
    }

    /// The innermost tile under a point: tiles inside a folder come after it.
    static func tile(at point: CGPoint, in tiles: [DiskTile]) -> DiskTile? {
        tiles.last { $0.rect.contains(point) }
    }

    private func draw(_ tile: DiskTile, in context: inout GraphicsContext) {
        let rect = tile.rect.insetBy(dx: 0.5, dy: 0.5)
        guard rect.width > 0, rect.height > 0 else { return }
        let shape = Path(roundedRect: rect, cornerRadius: min(Radius.control / 2, rect.width / 4, rect.height / 4))
        let node = tile.node
        if tile.isOpen {
            context.fill(shape, with: .color(.secondary.opacity(0.08)))
            label(node.name, in: CGRect(x: rect.minX + Space.xs, y: rect.minY, width: rect.width - Space.sm, height: Space.lg),
                  context: &context, secondary: true)
        } else {
            let color = node.category.color
            context.fill(shape, with: .linearGradient(Gradient(colors: [color.opacity(0.45), color.opacity(0.3)]),
                                                      startPoint: CGPoint(x: rect.minX, y: rect.minY),
                                                      endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
            if rect.width >= 36, rect.height >= Space.section + Space.sm {
                let box = rect.insetBy(dx: Space.xs, dy: Space.xs)
                label(DiskText.name(node), in: CGRect(x: box.minX, y: box.minY, width: box.width, height: Space.lg), context: &context)
                label(DiskText.size(node.size), in: CGRect(x: box.minX, y: box.minY + Space.lg, width: box.width, height: Space.lg),
                      context: &context, secondary: true)
            }
        }
        context.stroke(shape, with: .color(.primary.opacity(0.08)), lineWidth: 1)
        if node.id == model.selection {
            context.stroke(shape, with: .color(Palette.accent), lineWidth: 2)
        } else if node.id == model.hovered?.id {
            context.stroke(shape, with: .color(.primary.opacity(0.5)), lineWidth: 1)
        }
    }

    private func label(_ text: String, in rect: CGRect, context: inout GraphicsContext, secondary: Bool = false) {
        guard rect.width > 12 else { return }
        let resolved = context.resolve(Text(text).font(.caption2).foregroundStyle(secondary ? .secondary : .primary))
        context.draw(resolved, in: rect)
    }
}

/// Laying out thousands of tiles on every hover is wasted work: keep the last layout.
@MainActor
final class TileCache {
    private var key: (String, Int64, CGSize)?
    private var last: [DiskTile] = []

    func tiles(for folder: DiskNode, size: CGSize) -> [DiskTile] {
        // Measuring again makes a new tree with the same ids: its size tells them apart.
        if let key, key.0 == folder.id, key.1 == folder.size, key.2 == size { return last }
        key = (folder.id, folder.size, size)
        last = Treemap.tiles(for: folder, in: CGRect(origin: .zero, size: size))
        return last
    }
}
