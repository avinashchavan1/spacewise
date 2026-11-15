import Foundation

struct CategoryTotal: Sendable, Equatable {
    var bytes: Int64 = 0
    var files: Int = 0
}

/// Summaries computed in one pass over a finished scan.
struct ScanAnalysis: @unchecked Sendable {
    /// Biggest files (and packages such as apps), largest first.
    var largestFiles: [FSNode] = []
    var categoryTotals: [FileCategory: CategoryTotal] = [:]
    /// Biggest files per category, largest first.
    var largestByCategory: [FileCategory: [FSNode]] = [:]

    static func analyze(root: FSNode, largestLimit: Int = 3000, perCategoryLimit: Int = 300) -> ScanAnalysis {
        var totals: [FileCategory: CategoryTotal] = [:]
        var overall = TopK(limit: largestLimit)
        var perCategory: [FileCategory: TopK] = [:]

        func record(_ node: FSNode, category: FileCategory, files: Int) {
            totals[category, default: CategoryTotal()].bytes += node.size
            totals[category, default: CategoryTotal()].files += files
            guard node.size > 0 else { return }
            overall.insert(node)
            perCategory[category, default: TopK(limit: perCategoryLimit)].insert(node)
        }

        root.walk { node in
            switch node.kind {
            case .directory:
                if node.isPackage && node !== root {
                    record(node, category: .category(forPackageExtension: node.fileExtension), files: Int(node.fileCount))
                    return false
                }
                return true
            case .file:
                record(node, category: .category(forExtension: node.fileExtension), files: 1)
                return false
            case .symlink, .other:
                return false
            }
        }

        var analysis = ScanAnalysis()
        analysis.largestFiles = overall.sorted()
        analysis.categoryTotals = totals
        analysis.largestByCategory = perCategory.mapValues { $0.sorted() }
        return analysis
    }

    /// Drops nodes that are no longer part of the tree (after trashing or moving).
    mutating func removeDetachedNodes() {
        largestFiles.removeAll { !$0.isInTree }
        for key in Array(largestByCategory.keys) {
            largestByCategory[key]?.removeAll { !$0.isInTree }
        }
    }

    /// Recomputes category totals after files were removed from the tree.
    mutating func subtract(_ node: FSNode) {
        func subtractOne(_ item: FSNode, category: FileCategory, files: Int) {
            guard var total = totals(for: category) else { return }
            total.bytes = max(0, total.bytes - item.size)
            total.files = max(0, total.files - files)
            categoryTotals[category] = total
        }
        node.walk { item in
            switch item.kind {
            case .directory:
                if item.isPackage {
                    subtractOne(item, category: .category(forPackageExtension: item.fileExtension), files: Int(item.fileCount))
                    return false
                }
                return true
            case .file:
                subtractOne(item, category: .category(forExtension: item.fileExtension), files: 1)
                return false
            case .symlink, .other:
                return false
            }
        }
    }

    private func totals(for category: FileCategory) -> CategoryTotal? {
        categoryTotals[category]
    }
}

/// Keeps the `limit` largest nodes seen, using a min-heap.
struct TopK {
    private var heap: [FSNode] = []
    let limit: Int

    init(limit: Int) {
        self.limit = max(1, limit)
        heap.reserveCapacity(min(self.limit, 4096))
    }

    mutating func insert(_ node: FSNode) {
        if heap.count < limit {
            heap.append(node)
            siftUp(heap.count - 1)
        } else if node.size > heap[0].size {
            heap[0] = node
            siftDown(0)
        }
    }

    func sorted() -> [FSNode] {
        heap.sorted { $0.size > $1.size }
    }

    private mutating func siftUp(_ start: Int) {
        var index = start
        while index > 0 {
            let parent = (index - 1) / 2
            if heap[index].size < heap[parent].size {
                heap.swapAt(index, parent)
                index = parent
            } else {
                break
            }
        }
    }

    private mutating func siftDown(_ start: Int) {
        var index = start
        let count = heap.count
        while true {
            let left = index * 2 + 1
            let right = left + 1
            var smallest = index
            if left < count && heap[left].size < heap[smallest].size { smallest = left }
            if right < count && heap[right].size < heap[smallest].size { smallest = right }
            if smallest == index { break }
            heap.swapAt(index, smallest)
            index = smallest
        }
    }
}
