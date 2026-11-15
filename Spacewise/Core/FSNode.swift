import Foundation

/// One file or directory in a scanned tree.
///
/// Nodes are deliberately compact: a full-disk scan creates millions of them.
/// `name` and `parent` never change after the scan, so `path` is safe to read
/// from any thread. `children`, `size`, `logicalSize` and `fileCount` are only
/// mutated on the main thread once the scan has finished.
final class FSNode: @unchecked Sendable {
    enum Kind: UInt8 {
        case file
        case directory
        case symlink
        case other
    }

    struct Flags: OptionSet {
        let rawValue: UInt8
        /// Directory that the Finder shows as a single file (.app, .photoslibrary…).
        static let package = Flags(rawValue: 1 << 0)
        /// Directory that could not be read (permission denied, I/O error).
        static let unreadable = Flags(rawValue: 1 << 1)
        /// Directory on another volume, or excluded from the scan. Not descended into.
        static let skipped = Flags(rawValue: 1 << 2)
        /// Additional hard link to a file that was already counted.
        static let hardLinkDuplicate = Flags(rawValue: 1 << 3)
        /// Removed from the tree after being trashed or moved.
        static let removed = Flags(rawValue: 1 << 4)
    }

    let name: String
    /// Strong on purpose: a node handed to the UI keeps its ancestors alive, so
    /// `path` always works. The cycle is broken by `teardown()`.
    private(set) var parent: FSNode?
    var children: [FSNode] = []
    /// Bytes allocated on disk. For directories, the total of everything inside.
    var size: Int64
    /// Byte length of the content. For directories, the total of everything inside.
    var logicalSize: Int64
    /// Modification time, seconds since 1970.
    let modified: Int64
    /// Number of files inside (1 for a file).
    var fileCount: Int32
    let kind: Kind
    var flags: Flags

    init(name: String, parent: FSNode?, kind: Kind, size: Int64, logicalSize: Int64, modified: Int64, flags: Flags = []) {
        self.name = name
        self.parent = parent
        self.kind = kind
        self.size = size
        self.logicalSize = logicalSize
        self.modified = modified
        self.fileCount = kind == .directory ? 0 : 1
        self.flags = flags
    }

    var isDirectory: Bool { kind == .directory }
    var isPackage: Bool { flags.contains(.package) }
    var isRemoved: Bool { flags.contains(.removed) }

    /// Absolute path. The root node's name is its absolute path.
    var path: String {
        var parts: [String] = []
        var node: FSNode? = self
        while let current = node {
            parts.append(current.name)
            node = current.parent
        }
        var result = parts.removeLast()
        while let part = parts.popLast() {
            if !result.hasSuffix("/") { result.append("/") }
            result.append(part)
        }
        return result
    }

    var url: URL { URL(fileURLWithPath: path, isDirectory: isDirectory) }

    /// Lowercased extension without the dot; empty if there is none.
    var fileExtension: String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        let ext = name[name.index(after: dot)...]
        if ext.isEmpty || ext.count > 16 { return "" }
        return ext.lowercased()
    }

    /// Name to show the user: the last path component, including for the root.
    var displayName: String {
        guard parent == nil else { return name }
        if name == "/" { return "/" }
        return (name as NSString).lastPathComponent
    }

    var depth: Int {
        var count = 0
        var node = parent
        while let current = node {
            count += 1
            node = current.parent
        }
        return count
    }

    /// Chain from the root down to this node.
    var ancestorsFromRoot: [FSNode] {
        var chain: [FSNode] = []
        var node: FSNode? = self
        while let current = node {
            chain.append(current)
            node = current.parent
        }
        return chain.reversed()
    }

    /// False once this node or any ancestor has been removed from the tree.
    var isInTree: Bool {
        var node: FSNode? = self
        while let current = node {
            if current.flags.contains(.removed) { return false }
            node = current.parent
        }
        return true
    }

    func isDescendant(of other: FSNode) -> Bool {
        var node = parent
        while let current = node {
            if current === other { return true }
            node = current.parent
        }
        return false
    }

    /// True if this node sits inside a package such as an app bundle.
    var isInsidePackage: Bool {
        var node = parent
        while let current = node {
            if current.isPackage { return true }
            node = current.parent
        }
        return false
    }

    func child(named childName: String) -> FSNode? {
        children.first { $0.name == childName }
    }

    /// Finds the node for an absolute path inside this tree, if it was scanned.
    func descendant(atPath absolutePath: String) -> FSNode? {
        let rootPath = path
        if absolutePath == rootPath { return self }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard absolutePath.hasPrefix(prefix) else { return nil }
        var node = self
        for component in absolutePath.dropFirst(prefix.count).split(separator: "/") {
            guard let next = node.child(named: String(component)) else { return nil }
            node = next
        }
        return node
    }

    /// Detaches this node from its parent and fixes the totals of every ancestor.
    func removeFromTree() {
        guard !flags.contains(.removed) else { return }
        flags.insert(.removed)
        guard let parent else { return }
        if let index = parent.children.firstIndex(where: { $0 === self }) {
            parent.children.remove(at: index)
        }
        var node: FSNode? = parent
        while let current = node {
            current.size -= size
            current.logicalSize -= logicalSize
            current.fileCount -= fileCount
            node = current.parent
        }
    }

    /// Adds up sizes bottom-up and sorts children largest first.
    func aggregate() {
        guard kind == .directory else { return }
        var total: Int64 = 0
        var logical: Int64 = 0
        var files: Int32 = 0
        for child in children {
            child.aggregate()
            total += child.size
            logical += child.logicalSize
            files &+= child.fileCount
        }
        size = total
        logicalSize = logical
        fileCount = files
        if children.count > 1 {
            children.sort { $0.size > $1.size }
        }
    }

    /// Breaks the parent/child reference cycles so the tree can be freed.
    /// Call once nothing needs the tree any more.
    func teardown() {
        var stack: [FSNode] = [self]
        while let node = stack.popLast() {
            stack.append(contentsOf: node.children)
            node.children = []
            node.parent = nil
        }
    }

    /// Visits every node below this one, depth first. Return false from `visit`
    /// to skip a directory's contents.
    func walk(_ visit: (FSNode) -> Bool) {
        var stack: [FSNode] = [self]
        while let node = stack.popLast() {
            if visit(node), !node.children.isEmpty {
                stack.append(contentsOf: node.children)
            }
        }
    }
}
