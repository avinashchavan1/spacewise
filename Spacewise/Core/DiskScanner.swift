import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

struct ScanOptions: Sendable {
    /// Descend into directories that live on a different volume than the root.
    var crossMountPoints = false
    /// Absolute paths that are listed but never descended into.
    var excludedPaths: Set<String> = []
    /// Number of directories read in parallel.
    var workerCount = max(2, min(8, ProcessInfo.processInfo.activeProcessorCount))

    /// Options suited to a root path. Scanning "/" on macOS has to cross onto
    /// the Data volume (it is firmlinked into the read-only system volume), so
    /// crossing is allowed there while other disks and the duplicate view of
    /// the Data volume are excluded.
    static func recommended(forRoot path: String) -> ScanOptions {
        var options = ScanOptions()
        if path == "/" {
            options.crossMountPoints = true
            options.excludedPaths = ["/System/Volumes", "/Volumes", "/dev", "/net", "/home", "/proc", "/sys"]
        }
        return options
    }
}

/// Thread-safe counters a scan publishes while it runs.
final class ScanProgress: @unchecked Sendable {
    struct Snapshot: Sendable, Equatable {
        var files = 0
        var directories = 0
        var bytes: Int64 = 0
        var unreadable = 0
        var currentPath = ""
    }

    private let lock = NSLock()
    private var value = Snapshot()

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    fileprivate func add(files: Int, bytes: Int64, unreadable: Bool, path: String) {
        lock.lock()
        value.files += files
        value.directories += 1
        value.bytes += bytes
        if unreadable { value.unreadable += 1 }
        value.currentPath = path
        lock.unlock()
    }
}

/// Walks a directory tree with several threads and builds an `FSNode` tree.
///
/// Each directory is read with `readdir` + `fstatat`, which avoids building a
/// URL or fetching resource values per file and is an order of magnitude
/// faster than `FileManager` enumeration.
final class DiskScanner: @unchecked Sendable {
    let progress = ScanProgress()

    private let stateLock = NSLock()
    private var cancelled = false
    private var seenHardLinks = Set<HardLinkKey>()

    private struct HardLinkKey: Hashable {
        let device: UInt64
        let inode: UInt64
    }

    var isCancelled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cancelled
    }

    func cancel() {
        stateLock.lock()
        cancelled = true
        stateLock.unlock()
        queue.wakeAll()
    }

    private let queue = WorkQueue()

    /// Scans `rootPath` and returns the tree, or nil if the scan was cancelled
    /// or the root is not a readable directory. Blocks until finished; call it
    /// off the main thread.
    func scan(rootPath: String, options: ScanOptions = ScanOptions()) -> FSNode? {
        let normalized = DiskScanner.normalize(rootPath)
        var st = stat()
        guard lstat(normalized, &st) == 0, DiskScanner.fileType(st) == typeDirectory else { return nil }

        let root = FSNode(name: normalized, parent: nil, kind: .directory, size: 0, logicalSize: 0,
                          modified: DiskScanner.modificationTime(st))
        queue.push([Work(node: root, path: normalized, device: UInt64(truncatingIfNeeded: st.st_dev))])

        DispatchQueue.concurrentPerform(iterations: max(1, options.workerCount)) { _ in
            while let work = self.queue.pop(isCancelled: { self.isCancelled }) {
                let subdirectories = self.readDirectory(work, options: options)
                self.queue.finish(adding: subdirectories)
            }
        }

        if isCancelled {
            root.teardown()
            return nil
        }
        root.aggregate()
        return root
    }

    // MARK: - Directory reading

    private func readDirectory(_ work: Work, options: ScanOptions) -> [Work] {
        let fd = open(work.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0, let dir = fdopendir(fd) else {
            if fd >= 0 { close(fd) }
            work.node.flags.insert(.unreadable)
            progress.add(files: 0, bytes: 0, unreadable: true, path: work.path)
            return []
        }
        defer { closedir(dir) }

        var children: [FSNode] = []
        var subdirectories: [Work] = []
        var fileCount = 0
        var byteCount: Int64 = 0
        let prefix = work.path.hasSuffix("/") ? work.path : work.path + "/"

        while let entry = readdir(dir) {
            let namePointer = UnsafeRawPointer(entry).advanced(by: DiskScanner.nameOffset)
                .assumingMemoryBound(to: CChar.self)
            // Skip "." and "..".
            if namePointer[0] == 46 {
                if namePointer[1] == 0 || (namePointer[1] == 46 && namePointer[2] == 0) { continue }
            }

            var st = stat()
            guard fstatat(fd, namePointer, &st, AT_SYMLINK_NOFOLLOW) == 0 else { continue }

            let name = String(cString: namePointer)
            let type = DiskScanner.fileType(st)
            let modified = DiskScanner.modificationTime(st)

            if type == typeDirectory {
                var flags: FSNode.Flags = []
                if let dot = name.lastIndex(of: "."), dot != name.startIndex {
                    let ext = name[name.index(after: dot)...].lowercased()
                    if FileCategory.isPackage(directoryExtension: ext) { flags.insert(.package) }
                }
                let childPath = prefix + name
                let device = UInt64(truncatingIfNeeded: st.st_dev)
                var descend = true
                if !options.crossMountPoints && device != work.device { descend = false }
                if descend && !options.excludedPaths.isEmpty && options.excludedPaths.contains(childPath) { descend = false }
                if descend && DiskScanner.isDataless(st) { descend = false }
                if !descend { flags.insert(.skipped) }

                let child = FSNode(name: name, parent: work.node, kind: .directory, size: 0, logicalSize: 0,
                                   modified: modified, flags: flags)
                children.append(child)
                if descend {
                    subdirectories.append(Work(node: child, path: childPath, device: device))
                }
            } else {
                var allocated = Int64(st.st_blocks) * 512
                let logical = Int64(st.st_size)
                var flags: FSNode.Flags = []
                let kind: FSNode.Kind
                if type == typeRegular {
                    kind = .file
                    if st.st_nlink > 1 {
                        let key = HardLinkKey(device: UInt64(truncatingIfNeeded: st.st_dev), inode: UInt64(st.st_ino))
                        stateLock.lock()
                        let firstSighting = seenHardLinks.insert(key).inserted
                        stateLock.unlock()
                        if !firstSighting {
                            allocated = 0
                            flags.insert(.hardLinkDuplicate)
                        }
                    }
                } else if type == typeSymlink {
                    kind = .symlink
                } else {
                    kind = .other
                }
                children.append(FSNode(name: name, parent: work.node, kind: kind, size: allocated,
                                       logicalSize: logical, modified: modified, flags: flags))
                fileCount += 1
                byteCount += allocated
            }
        }

        work.node.children = children
        progress.add(files: fileCount, bytes: byteCount, unreadable: false, path: work.path)
        return subdirectories
    }

    // MARK: - stat helpers

    private static let nameOffset = MemoryLayout<dirent>.offset(of: \dirent.d_name)!

    private static func fileType(_ st: stat) -> UInt32 {
        UInt32(st.st_mode) & 0o170000
    }

    private static func modificationTime(_ st: stat) -> Int64 {
        #if canImport(Darwin)
        return Int64(st.st_mtimespec.tv_sec)
        #else
        return Int64(st.st_mtim.tv_sec)
        #endif
    }

    /// iCloud placeholders: listing one would make the system download it.
    private static func isDataless(_ st: stat) -> Bool {
        #if canImport(Darwin)
        return st.st_flags & 0x4000_0000 != 0
        #else
        return false
        #endif
    }

    static func normalize(_ path: String) -> String {
        var result = path
        while result.count > 1 && result.hasSuffix("/") {
            result.removeLast()
        }
        return result.isEmpty ? "/" : result
    }
}

private let typeDirectory: UInt32 = 0o040000
private let typeRegular: UInt32 = 0o100000
private let typeSymlink: UInt32 = 0o120000

private struct Work {
    let node: FSNode
    let path: String
    let device: UInt64
}

/// A LIFO queue of directories shared by the scan workers. `pop` blocks until
/// there is work or every worker is idle, which means the scan is complete.
private final class WorkQueue: @unchecked Sendable {
    private let condition = NSCondition()
    private var items: [Work] = []
    private var inFlight = 0

    func push(_ batch: [Work]) {
        condition.lock()
        items.append(contentsOf: batch)
        condition.unlock()
        condition.broadcast()
    }

    func pop(isCancelled: () -> Bool) -> Work? {
        condition.lock()
        defer { condition.unlock() }
        while true {
            if isCancelled() {
                condition.broadcast()
                return nil
            }
            if let item = items.popLast() {
                inFlight += 1
                return item
            }
            if inFlight == 0 {
                condition.broadcast()
                return nil
            }
            condition.wait()
        }
    }

    /// Marks one popped item as done and queues the work it produced.
    func finish(adding batch: [Work]) {
        condition.lock()
        items.append(contentsOf: batch)
        inFlight -= 1
        condition.unlock()
        condition.broadcast()
    }

    func wakeAll() {
        condition.lock()
        condition.unlock()
        condition.broadcast()
    }
}
