import Foundation

struct TreemapRect: Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var area: Double { max(0, width) * max(0, height) }

    func contains(x px: Double, y py: Double) -> Bool {
        px >= x && px < x + width && py >= y && py < y + height
    }

    func insetBy(_ amount: Double) -> TreemapRect {
        TreemapRect(x: x + amount, y: y + amount, width: max(0, width - amount * 2), height: max(0, height - amount * 2))
    }
}

struct TreemapTile: @unchecked Sendable {
    let node: FSNode
    let rect: TreemapRect
    /// 0 for the direct children of the layout root.
    let depth: Int
    /// Leaves are drawn as coloured blocks; containers only frame their children.
    let isLeaf: Bool
    /// Nil for plain folders.
    let category: FileCategory?
    /// True when the container reserved room for a title strip.
    let hasHeader: Bool
}

struct TreemapOptions: Sendable {
    var maxDepth = 6
    /// Tiles narrower than this are not drawn at all.
    var minSide = 3.0
    /// Directories narrower than this are drawn as one block instead of being subdivided.
    var minSubdivideSide = 26.0
    var padding = 1.5
    /// Height of the title strip on top-level folders; 0 disables it.
    var headerHeight = 17.0
    var minHeaderWidth = 70.0
    var maxTiles = 9000
}

enum Treemap {
    /// Squarified treemap (Bruls, Huizing, van Wijk). `areas` must be sorted
    /// largest first and sum to at most the area of `rect`.
    static func squarify(areas: [Double], in rect: TreemapRect) -> [TreemapRect] {
        var result: [TreemapRect] = []
        result.reserveCapacity(areas.count)
        var remaining = rect
        var rowStart = 0
        var rowSum = 0.0
        var rowMin = Double.greatestFiniteMagnitude
        var rowMax = 0.0

        func worst(sum: Double, minValue: Double, maxValue: Double, side: Double) -> Double {
            guard sum > 0, minValue > 0, side > 0 else { return .greatestFiniteMagnitude }
            let sideSquared = side * side
            let sumSquared = sum * sum
            return max(sideSquared * maxValue / sumSquared, sumSquared / (sideSquared * minValue))
        }

        func flushRow(upTo end: Int) {
            guard end > rowStart, rowSum > 0 else { return }
            if remaining.width >= remaining.height {
                let columnWidth = remaining.height > 0 ? min(remaining.width, rowSum / remaining.height) : 0
                var y = remaining.y
                for index in rowStart..<end {
                    let height = columnWidth > 0 ? areas[index] / columnWidth : 0
                    result.append(TreemapRect(x: remaining.x, y: y, width: columnWidth, height: height))
                    y += height
                }
                remaining.x += columnWidth
                remaining.width = max(0, remaining.width - columnWidth)
            } else {
                let rowHeight = remaining.width > 0 ? min(remaining.height, rowSum / remaining.width) : 0
                var x = remaining.x
                for index in rowStart..<end {
                    let width = rowHeight > 0 ? areas[index] / rowHeight : 0
                    result.append(TreemapRect(x: x, y: remaining.y, width: width, height: rowHeight))
                    x += width
                }
                remaining.y += rowHeight
                remaining.height = max(0, remaining.height - rowHeight)
            }
        }

        var index = 0
        while index < areas.count {
            let value = areas[index]
            let side = min(remaining.width, remaining.height)
            if index == rowStart {
                rowSum = value
                rowMin = value
                rowMax = value
                index += 1
                continue
            }
            let current = worst(sum: rowSum, minValue: rowMin, maxValue: rowMax, side: side)
            let extended = worst(sum: rowSum + value, minValue: min(rowMin, value), maxValue: max(rowMax, value), side: side)
            if extended <= current {
                rowSum += value
                rowMin = min(rowMin, value)
                rowMax = max(rowMax, value)
                index += 1
            } else {
                flushRow(upTo: index)
                rowStart = index
                rowSum = 0
            }
        }
        flushRow(upTo: areas.count)
        return result
    }

    /// Lays out the contents of `root` inside `rect`, recursing into folders
    /// while the tiles stay large enough to read.
    static func layout(root: FSNode, in rect: TreemapRect, options: TreemapOptions = TreemapOptions()) -> [TreemapTile] {
        var tiles: [TreemapTile] = []
        layoutChildren(of: root, in: rect, depth: 0, options: options, into: &tiles)
        return tiles
    }

    private static func layoutChildren(of node: FSNode, in rect: TreemapRect, depth: Int,
                                       options: TreemapOptions, into tiles: inout [TreemapTile]) {
        guard node.size > 0, rect.width >= options.minSide, rect.height >= options.minSide else { return }
        let scale = rect.area / Double(node.size)
        let minArea = options.minSide * options.minSide

        // Children are sorted largest first, so everything after the first
        // too-small child is too small as well.
        var visible: [FSNode] = []
        var areas: [Double] = []
        for child in node.children {
            let area = Double(child.size) * scale
            if area < minArea { break }
            visible.append(child)
            areas.append(area)
        }
        guard !visible.isEmpty else { return }

        let rects = squarify(areas: areas, in: rect)
        for (child, childRect) in zip(visible, rects) {
            if tiles.count >= options.maxTiles { return }
            if childRect.width < options.minSide || childRect.height < options.minSide { continue }

            let canSubdivide = child.isDirectory && !child.isPackage && !child.children.isEmpty
                && depth < options.maxDepth
                && childRect.width >= options.minSubdivideSide && childRect.height >= options.minSubdivideSide

            if canSubdivide {
                let wantsHeader = depth == 0 && options.headerHeight > 0
                    && childRect.width >= options.minHeaderWidth && childRect.height >= options.headerHeight * 3
                tiles.append(TreemapTile(node: child, rect: childRect, depth: depth, isLeaf: false,
                                         category: nil, hasHeader: wantsHeader))
                var inner = childRect.insetBy(options.padding)
                if wantsHeader {
                    inner.y += options.headerHeight
                    inner.height = max(0, inner.height - options.headerHeight)
                }
                layoutChildren(of: child, in: inner, depth: depth + 1, options: options, into: &tiles)
            } else {
                let category: FileCategory?
                if child.isDirectory {
                    category = child.isPackage ? FileCategory.category(forPackageExtension: child.fileExtension) : nil
                } else {
                    category = FileCategory.category(forExtension: child.fileExtension)
                }
                tiles.append(TreemapTile(node: child, rect: childRect, depth: depth, isLeaf: true,
                                         category: category, hasHeader: false))
            }
        }
    }

    /// The deepest tile under a point, preferring leaves.
    static func tile(at x: Double, _ y: Double, in tiles: [TreemapTile]) -> TreemapTile? {
        var best: TreemapTile?
        for tile in tiles where tile.rect.contains(x: x, y: y) {
            if best == nil || tile.depth >= best!.depth {
                best = tile
            }
        }
        return best
    }
}
