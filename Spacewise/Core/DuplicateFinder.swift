import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

#if canImport(CryptoKit)
import CryptoKit
#endif

/// Files with identical content.
struct DuplicateGroup: @unchecked Sendable {
    /// Content length of each file in the group.
    let fileSize: Int64
    var files: [FSNode]

    /// Space freed by keeping a single copy.
    var reclaimableBytes: Int64 {
        guard files.count > 1 else { return 0 }
        let sizes = files.map(\.size)
        return sizes.reduce(0, +) - (sizes.max() ?? 0)
    }
}

/// Finds duplicate files in three passes that each read more of the file:
/// equal size, equal hash of the first and last 64 KB, equal hash of everything.
final class DuplicateFinder: @unchecked Sendable {
    struct Progress: Sendable, Equatable {
        var filesDone = 0
        var filesTotal = 0
        var bytesDone: Int64 = 0
        var bytesTotal: Int64 = 0

        var fraction: Double {
            guard bytesTotal > 0 else { return filesTotal > 0 ? Double(filesDone) / Double(filesTotal) : 0 }
            return min(1, Double(bytesDone) / Double(bytesTotal))
        }
    }

    private let lock = NSLock()
    private var cancelled = false
    private var progressValue = Progress()

    static let sampleSize = 64 * 1024

    var progress: Progress {
        lock.lock()
        defer { lock.unlock() }
        return progressValue
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    /// Groups of files that share a content length. Reads only the tree, so it
    /// is fast. Skips package contents (app bundles, photo libraries), files
    /// with no data on disk (iCloud placeholders, extra hard links) and links.
    static func candidates(root: FSNode, minSize: Int64) -> [[FSNode]] {
        var bySize: [Int64: [FSNode]] = [:]
        root.walk { node in
            switch node.kind {
            case .directory:
                return !node.isPackage || node === root
            case .file:
                if node.logicalSize >= minSize && node.size > 0 && !node.flags.contains(.hardLinkDuplicate) {
                    bySize[node.logicalSize, default: []].append(node)
                }
                return false
            case .symlink, .other:
                return false
            }
        }
        return bySize.values.filter { $0.count > 1 }
    }

    /// Hashes the candidates and returns the confirmed groups, most
    /// reclaimable space first. Blocks; call off the main thread.
    func find(candidates: [[FSNode]]) -> [DuplicateGroup] {
        struct Item {
            let node: FSNode
            let path: String
            let group: Int
        }

        var items: [Item] = []
        var totalBytes: Int64 = 0
        for (index, group) in candidates.enumerated() {
            for node in group {
                items.append(Item(node: node, path: node.path, group: index))
                // Worst case: the samples plus one full read.
                totalBytes += min(node.logicalSize, Int64(DuplicateFinder.sampleSize * 2)) + node.logicalSize
            }
        }
        lock.lock()
        progressValue = Progress(filesDone: 0, filesTotal: items.count, bytesDone: 0, bytesTotal: totalBytes)
        lock.unlock()

        // Pass 2: hash the head and tail of every candidate.
        let sampleHashes = hashAll(items.map { ($0.path, $0.node.logicalSize) }, full: false)
        if isCancelled { return [] }

        struct SampleKey: Hashable {
            let group: Int
            let hash: [UInt8]
        }
        var bySample: [SampleKey: [Int]] = [:]
        for (index, hash) in sampleHashes.enumerated() {
            guard let hash else { continue }
            bySample[SampleKey(group: items[index].group, hash: hash), default: []].append(index)
        }

        // Pass 3: full hash where the samples did not already cover the file.
        var groups: [DuplicateGroup] = []
        var needFull: [Int] = []
        var skippedBytes: Int64 = 0
        for (_, indices) in bySample {
            let size = items[indices[0]].node.logicalSize
            if indices.count < 2 {
                skippedBytes += size
                continue
            }
            if size <= Int64(DuplicateFinder.sampleSize * 2) {
                groups.append(DuplicateGroup(fileSize: size, files: indices.map { items[$0].node }))
                skippedBytes += size * Int64(indices.count)
            } else {
                needFull.append(contentsOf: indices)
            }
        }
        addProgress(files: 0, bytes: skippedBytes)

        if !needFull.isEmpty {
            let fullHashes = hashAll(needFull.map { (items[$0].path, items[$0].node.logicalSize) }, full: true)
            if isCancelled { return [] }
            var byFull: [SampleKey: [Int]] = [:]
            for (position, hash) in fullHashes.enumerated() {
                guard let hash else { continue }
                let index = needFull[position]
                byFull[SampleKey(group: items[index].group, hash: hash), default: []].append(index)
            }
            for (_, indices) in byFull where indices.count > 1 {
                groups.append(DuplicateGroup(fileSize: items[indices[0]].node.logicalSize,
                                             files: indices.map { items[$0].node }))
            }
        }

        for index in groups.indices {
            groups[index].files.sort { $0.path < $1.path }
        }
        groups.sort { $0.reclaimableBytes > $1.reclaimableBytes }
        return groups
    }

    // MARK: - Hashing

    private func addProgress(files: Int, bytes: Int64) {
        lock.lock()
        progressValue.filesDone += files
        progressValue.bytesDone += bytes
        lock.unlock()
    }

    private func hashAll(_ files: [(path: String, size: Int64)], full: Bool) -> [[UInt8]?] {
        guard !files.isEmpty else { return [] }
        var results = [[UInt8]?](repeating: nil, count: files.count)
        let resultsLock = NSLock()
        DispatchQueue.concurrentPerform(iterations: files.count) { index in
            if self.isCancelled { return }
            let file = files[index]
            let hash = full ? self.hashFile(file.path) : self.hashSamples(file.path, size: file.size)
            resultsLock.lock()
            results[index] = hash
            resultsLock.unlock()
            if !full { self.addProgress(files: 1, bytes: 0) }
        }
        return results
    }

    /// Hash of the first and last 64 KB (the whole file if it is smaller).
    private func hashSamples(_ path: String, size: Int64) -> [UInt8]? {
        let fd = open(path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        let sample = DuplicateFinder.sampleSize
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: sample, alignment: 16)
        defer { buffer.deallocate() }
        var hasher = ContentHasher()

        var offsets: [Int64] = [0]
        if size > Int64(sample * 2) {
            offsets.append(size - Int64(sample))
        } else if size > Int64(sample) {
            offsets.append(Int64(sample))
        }
        for offset in offsets {
            var position = offset
            var remaining = sample
            while remaining > 0 {
                let count = pread(fd, buffer.baseAddress, remaining, off_t(position))
                if count < 0 { return nil }
                if count == 0 { break }
                hasher.update(UnsafeRawBufferPointer(rebasing: buffer[0..<count]))
                addProgress(files: 0, bytes: Int64(count))
                position += Int64(count)
                remaining -= count
            }
        }
        return hasher.finalize()
    }

    private func hashFile(_ path: String) -> [UInt8]? {
        let fd = open(path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 1 << 20, alignment: 16)
        defer { buffer.deallocate() }
        var hasher = ContentHasher()
        while true {
            if isCancelled { return nil }
            let count = read(fd, buffer.baseAddress, buffer.count)
            if count < 0 { return nil }
            if count == 0 { break }
            hasher.update(UnsafeRawBufferPointer(rebasing: buffer[0..<count]))
            addProgress(files: 0, bytes: Int64(count))
        }
        return hasher.finalize()
    }
}

/// SHA-256 where CryptoKit exists (every Apple platform). The fallback is only
/// used when the engine is built elsewhere for testing.
struct ContentHasher {
    #if canImport(CryptoKit)
    private var hasher = SHA256()

    mutating func update(_ bytes: UnsafeRawBufferPointer) {
        hasher.update(bufferPointer: bytes)
    }

    func finalize() -> [UInt8] {
        Array(hasher.finalize())
    }
    #else
    private var first: UInt64 = 0xcbf2_9ce4_8422_2325
    private var second: UInt64 = 0x6c62_272e_07bb_0142
    private var length: UInt64 = 0

    mutating func update(_ bytes: UnsafeRawBufferPointer) {
        for byte in bytes {
            first = (first ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            second = (second &+ UInt64(byte) &+ 0x9e37_79b9_7f4a_7c15) &* 0xff51_afd7_ed55_8ccd
            second ^= second >> 29
        }
        length &+= UInt64(bytes.count)
    }

    func finalize() -> [UInt8] {
        var output: [UInt8] = []
        for value in [first, second, length] {
            for shift in stride(from: 0, to: 64, by: 8) {
                output.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
            }
        }
        return output
    }
    #endif
}
