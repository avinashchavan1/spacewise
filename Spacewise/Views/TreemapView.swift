import SwiftUI

/// Draws the contents of a folder as nested blocks sized by disk usage.
///
/// The layout is computed once per folder and window size, then drawn in a
/// single `Canvas`, so even thousands of blocks stay cheap to render.
struct TreemapView: View {
    let root: FSNode
    let revision: Int
    @Binding var highlighted: FSNode?
    var onOpen: (FSNode) -> Void
    var menu: (FSNode) -> NodeMenuItems

    @State private var tiles: [TreemapTile] = []
    @State private var hoveredIndex: Int?

    private struct LayoutKey: Hashable {
        let root: ObjectIdentifier
        let revision: Int
        let width: Int
        let height: Int
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            Canvas { context, _ in
                draw(in: &context)
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    updateHover(at: point)
                case .ended:
                    hoveredIndex = nil
                }
            }
            .onTapGesture(count: 2) { point in
                if let tile = topLevelTile(at: point) {
                    onOpen(tile.node)
                }
            }
            .onTapGesture { point in
                highlighted = Treemap.tile(at: point.x, point.y, in: tiles)?.node
            }
            .contextMenu {
                if let node = highlighted ?? hoveredNode {
                    menu(node)
                }
            }
            .task(id: LayoutKey(root: ObjectIdentifier(root), revision: revision,
                                width: Int(size.width), height: Int(size.height))) {
                hoveredIndex = nil
                tiles = Treemap.layout(root: root,
                                       in: TreemapRect(x: 0, y: 0, width: size.width, height: size.height))
            }
            .overlay {
                if root.size == 0 {
                    ContentUnavailableView("Empty Folder", systemImage: "folder",
                                           description: Text("There is nothing here that takes up space."))
                }
            }
        }
        .accessibilityLabel("Treemap of \(root.displayName)")
    }

    private var hoveredNode: FSNode? {
        guard let hoveredIndex, tiles.indices.contains(hoveredIndex) else { return nil }
        return tiles[hoveredIndex].node
    }

    private func updateHover(at point: CGPoint) {
        var best: Int?
        for (index, tile) in tiles.enumerated() where tile.rect.contains(x: point.x, y: point.y) {
            if best == nil || tile.depth >= tiles[best!].depth {
                best = index
            }
        }
        if best != hoveredIndex {
            hoveredIndex = best
            if let best { highlighted = tiles[best].node }
        }
    }

    private func topLevelTile(at point: CGPoint) -> TreemapTile? {
        tiles.first { $0.depth == 0 && $0.rect.contains(x: point.x, y: point.y) }
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext) {
        let highlightedID = highlighted.map { ObjectIdentifier($0) }

        for tile in tiles {
            let rect = CGRect(x: tile.rect.x, y: tile.rect.y, width: tile.rect.width, height: tile.rect.height)
                .insetBy(dx: 0.5, dy: 0.5)
            guard rect.width > 0, rect.height > 0 else { continue }

            if tile.isLeaf {
                let color = tile.category?.color ?? Color.gray
                // Deeper tiles are drawn slightly lighter so neighbours in
                // different folders can be told apart.
                let opacity = max(0.55, 0.92 - Double(tile.depth) * 0.07)
                let path = Path(roundedRect: rect, cornerRadius: min(3, min(rect.width, rect.height) / 3))
                context.fill(path, with: .color(color.opacity(opacity)))
                drawLeafLabel(tile, rect: rect, in: &context)
            } else {
                let path = Path(roundedRect: rect, cornerRadius: 4)
                context.fill(path, with: .color(Color.primary.opacity(tile.depth == 0 ? 0.07 : 0.05)))
                if tile.hasHeader {
                    var clipped = context
                    clipped.clip(to: Path(CGRect(x: rect.minX + 4, y: rect.minY, width: rect.width - 8, height: 17)))
                    let title: Text = Text("\(tile.node.displayName)  \(formatBytes(tile.node.size))")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    clipped.draw(title, at: CGPoint(x: rect.minX + 6, y: rect.minY + 9), anchor: .leading)
                }
            }

            if let highlightedID, ObjectIdentifier(tile.node) == highlightedID {
                let outline = Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3)
                context.stroke(outline, with: .color(Color.primary), lineWidth: 2)
            }
        }
    }

    private func drawLeafLabel(_ tile: TreemapTile, rect: CGRect, in context: inout GraphicsContext) {
        guard rect.width >= 64, rect.height >= 20 else { return }
        var clipped = context
        clipped.clip(to: Path(rect.insetBy(dx: 4, dy: 2)))
        let name: Text = Text(tile.node.displayName)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.white)
        clipped.draw(name, at: CGPoint(x: rect.minX + 6, y: rect.minY + 10), anchor: .leading)
        if rect.height >= 36 {
            let size: Text = Text(formatBytes(tile.node.size))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.8))
            clipped.draw(size, at: CGPoint(x: rect.minX + 6, y: rect.minY + 24), anchor: .leading)
        }
    }
}
