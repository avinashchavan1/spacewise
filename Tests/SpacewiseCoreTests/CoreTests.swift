import XCTest
@testable import SpacewiseCore

final class CoreTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("spacewise-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    @discardableResult
    private func write(_ relative: String, bytes: Int, fill: UInt8 = 0x41) throws -> URL {
        let url = base.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: fill, count: bytes).write(to: url)
        return url
    }

    private func scan(_ options: ScanOptions = ScanOptions()) throws -> FSNode {
        try XCTUnwrap(DiskScanner().scan(rootPath: base.path, options: options))
    }

    // MARK: Scanner

    func testScanBuildsTreeWithTotals() throws {
        try write("a/one.bin", bytes: 10_000)
        try write("a/b/two.bin", bytes: 50_000)
        try write("three.txt", bytes: 3_000)
        try FileManager.default.createDirectory(at: base.appendingPathComponent("empty"), withIntermediateDirectories: true)

        let root = try scan()
        XCTAssertEqual(root.fileCount, 3)
        XCTAssertEqual(root.logicalSize, 63_000)
        XCTAssertGreaterThanOrEqual(root.size, 63_000)
        XCTAssertEqual(root.size % 512, 0)

        let a = try XCTUnwrap(root.child(named: "a"))
        XCTAssertEqual(a.fileCount, 2)
        XCTAssertEqual(a.logicalSize, 60_000)
        XCTAssertTrue(root.children.first === a, "children are sorted largest first")
        XCTAssertEqual(root.child(named: "empty")?.fileCount, 0)

        let two = try XCTUnwrap(root.descendant(atPath: base.path + "/a/b/two.bin"))
        XCTAssertEqual(two.path, base.path + "/a/b/two.bin")
        XCTAssertEqual(two.fileExtension, "bin")
        XCTAssertEqual(two.depth, 3)
        XCTAssertEqual(two.ancestorsFromRoot.map(\.displayName), [base.lastPathComponent, "a", "b", "two.bin"])
        XCTAssertNil(root.descendant(atPath: base.path + "/missing"))
        root.teardown()
    }

    func testScanMatchesFileManagerOnLargerTree() throws {
        var expectedFiles = 0
        var expectedBytes: Int64 = 0
        for dir in 0..<40 {
            for file in 0..<25 {
                let bytes = (dir * 37 + file * 911) % 9000
                try write("d\(dir)/sub\(file % 3)/f\(file).dat", bytes: bytes)
                expectedFiles += 1
                expectedBytes += Int64(bytes)
            }
        }
        for workers in [1, 4, 8] {
            var options = ScanOptions()
            options.workerCount = workers
            let scanner = DiskScanner()
            let root = try XCTUnwrap(scanner.scan(rootPath: base.path, options: options))
            XCTAssertEqual(Int(root.fileCount), expectedFiles)
            XCTAssertEqual(root.logicalSize, expectedBytes)
            let progress = scanner.progress.snapshot()
            XCTAssertEqual(progress.files, expectedFiles)
            XCTAssertEqual(progress.bytes, root.size)
            XCTAssertEqual(progress.directories, 1 + 40 + 40 * 3)
            root.teardown()
        }
    }

    func testHardLinksAreCountedOnce() throws {
        let original = try write("big.bin", bytes: 200_000)
        try FileManager.default.linkItem(at: original, to: base.appendingPathComponent("link.bin"))
        let root = try scan()
        XCTAssertEqual(root.fileCount, 2)
        let sizes = root.children.map(\.size).sorted()
        XCTAssertEqual(sizes[0], 0)
        XCTAssertGreaterThanOrEqual(sizes[1], 200_000)
        XCTAssertEqual(root.children.filter { $0.flags.contains(.hardLinkDuplicate) }.count, 1)
        root.teardown()
    }

    func testSymlinksAreNotFollowed() throws {
        try write("real/data.bin", bytes: 80_000)
        try FileManager.default.createSymbolicLink(at: base.appendingPathComponent("alias"),
                                                   withDestinationURL: base.appendingPathComponent("real"))
        let root = try scan()
        let alias = try XCTUnwrap(root.child(named: "alias"))
        XCTAssertEqual(alias.kind, .symlink)
        XCTAssertTrue(alias.children.isEmpty)
        XCTAssertEqual(root.logicalSize - alias.logicalSize, 80_000)
        root.teardown()
    }

    func testExcludedPathsAndPackagesAndMissingRoot() throws {
        try write("keep/a.bin", bytes: 5_000)
        try write("skip/b.bin", bytes: 5_000)
        try write("Tool.app/Contents/MacOS/tool", bytes: 7_000)
        var options = ScanOptions()
        options.excludedPaths = [base.path + "/skip"]
        let root = try scan(options)
        let skipped = try XCTUnwrap(root.child(named: "skip"))
        XCTAssertTrue(skipped.flags.contains(.skipped))
        XCTAssertEqual(skipped.fileCount, 0)
        XCTAssertEqual(root.fileCount, 2)
        XCTAssertEqual(root.child(named: "Tool.app")?.isPackage, true)
        XCTAssertEqual(root.descendant(atPath: base.path + "/Tool.app/Contents/MacOS/tool")?.isInsidePackage, true)
        XCTAssertNil(DiskScanner().scan(rootPath: base.path + "/does-not-exist"))
        XCTAssertNil(DiskScanner().scan(rootPath: base.path + "/keep/a.bin"))
        root.teardown()
    }

    func testUnreadableDirectoryIsFlagged() throws {
        try XCTSkipIf(getuid() == 0, "root can read everything")
        try write("locked/secret.bin", bytes: 5_000)
        let locked = base.appendingPathComponent("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let scanner = DiskScanner()
        let root = try XCTUnwrap(scanner.scan(rootPath: base.path))
        XCTAssertEqual(root.child(named: "locked")?.flags.contains(.unreadable), true)
        XCTAssertEqual(scanner.progress.snapshot().unreadable, 1)
        root.teardown()
    }

    func testCancelledScanReturnsNil() throws {
        try write("a/one.bin", bytes: 100)
        let scanner = DiskScanner()
        scanner.cancel()
        XCTAssertNil(scanner.scan(rootPath: base.path))
    }

    func testTrailingSlashAndRootOptions() {
        XCTAssertEqual(DiskScanner.normalize("/tmp/x///"), "/tmp/x")
        XCTAssertEqual(DiskScanner.normalize("/"), "/")
        XCTAssertTrue(ScanOptions.recommended(forRoot: "/").crossMountPoints)
        XCTAssertFalse(ScanOptions.recommended(forRoot: "/Users/me").crossMountPoints)
    }

    // MARK: Tree edits

    func testRemoveFromTreeUpdatesAncestors() throws {
        try write("a/one.bin", bytes: 10_000)
        try write("a/b/two.bin", bytes: 50_000)
        try write("three.txt", bytes: 3_000)
        let root = try scan()
        let b = try XCTUnwrap(root.descendant(atPath: base.path + "/a/b"))
        let two = try XCTUnwrap(b.child(named: "two.bin"))
        let before = root.size
        let removedSize = b.size
        b.removeFromTree()
        XCTAssertEqual(root.size, before - removedSize)
        XCTAssertEqual(root.fileCount, 2)
        XCTAssertEqual(root.child(named: "a")?.fileCount, 1)
        XCTAssertFalse(b.isInTree)
        XCTAssertFalse(two.isInTree)
        XCTAssertTrue(two.isDescendant(of: b))
        XCTAssertEqual(two.path, base.path + "/a/b/two.bin", "detached nodes still know their path")
        b.removeFromTree()
        XCTAssertEqual(root.size, before - removedSize, "removing twice is harmless")
        root.teardown()
    }

    // MARK: Analysis

    func testAnalysisTotalsAndLargest() throws {
        try write("movie.mp4", bytes: 90_000)
        try write("photo.jpg", bytes: 40_000)
        try write("pics/other.PNG", bytes: 20_000)
        try write("notes.txt", bytes: 1_000)
        try write("App.app/Contents/Resources/blob.mp4", bytes: 30_000)
        let root = try scan()
        var analysis = ScanAnalysis.analyze(root: root, largestLimit: 3)

        XCTAssertEqual(analysis.largestFiles.count, 3)
        XCTAssertEqual(analysis.largestFiles.map(\.name), ["movie.mp4", "photo.jpg", "App.app"])
        XCTAssertEqual(analysis.categoryTotals[.videos]?.files, 1)
        XCTAssertEqual(analysis.categoryTotals[.images]?.files, 2)
        XCTAssertEqual(analysis.categoryTotals[.applications]?.files, 1)
        XCTAssertEqual(analysis.categoryTotals[.documents]?.files, 1)
        XCTAssertEqual(analysis.categoryTotals.values.reduce(0) { $0 + $1.bytes }, root.size)
        XCTAssertEqual(analysis.largestByCategory[.images]?.map(\.name), ["photo.jpg", "other.PNG"])

        let pics = try XCTUnwrap(root.child(named: "pics"))
        analysis.subtract(pics)
        pics.removeFromTree()
        analysis.removeDetachedNodes()
        XCTAssertEqual(analysis.categoryTotals[.images]?.files, 1)
        XCTAssertEqual(analysis.largestByCategory[.images]?.map(\.name), ["photo.jpg"])
        XCTAssertEqual(analysis.categoryTotals.values.reduce(0) { $0 + $1.bytes }, root.size)
        root.teardown()
    }

    func testTopKKeepsLargest() {
        var top = TopK(limit: 5)
        var sizes = (1...200).map { Int64(($0 * 7919) % 1000) }
        for size in sizes {
            top.insert(FSNode(name: "f", parent: nil, kind: .file, size: size, logicalSize: size, modified: 0))
        }
        sizes.sort(by: >)
        XCTAssertEqual(top.sorted().map(\.size), Array(sizes.prefix(5)))
    }

    func testCategories() {
        XCTAssertEqual(FileCategory.category(forExtension: "mkv"), .videos)
        XCTAssertEqual(FileCategory.category(forExtension: "heic"), .images)
        XCTAssertEqual(FileCategory.category(forExtension: "dmg"), .archives)
        XCTAssertEqual(FileCategory.category(forExtension: "swift"), .developer)
        XCTAssertEqual(FileCategory.category(forExtension: "zzz"), .other)
        XCTAssertEqual(FileCategory.category(forPackageExtension: "photoslibrary"), .images)
        XCTAssertTrue(FileCategory.isPackage(directoryExtension: "app"))
        XCTAssertFalse(FileCategory.isPackage(directoryExtension: "txt"))
    }

    // MARK: Treemap

    func testSquarifyFillsRectWithoutOverlap() {
        let rect = TreemapRect(x: 10, y: 20, width: 600, height: 400)
        let weights: [Double] = [500, 300, 200, 120, 80, 40, 30, 20, 10, 5, 1]
        let scale = rect.area / weights.reduce(0, +)
        let areas = weights.map { $0 * scale }
        let rects = Treemap.squarify(areas: areas, in: rect)

        XCTAssertEqual(rects.count, areas.count)
        for (tile, area) in zip(rects, areas) {
            XCTAssertEqual(tile.area, area, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(tile.x, rect.x - 0.001)
            XCTAssertGreaterThanOrEqual(tile.y, rect.y - 0.001)
            XCTAssertLessThanOrEqual(tile.x + tile.width, rect.x + rect.width + 0.001)
            XCTAssertLessThanOrEqual(tile.y + tile.height, rect.y + rect.height + 0.001)
        }
        for i in rects.indices {
            for j in rects.indices where j > i {
                let a = rects[i], b = rects[j]
                let overlapW = min(a.x + a.width, b.x + b.width) - max(a.x, b.x)
                let overlapH = min(a.y + a.height, b.y + b.height) - max(a.y, b.y)
                XCTAssertFalse(overlapW > 0.001 && overlapH > 0.001, "tiles \(i) and \(j) overlap")
            }
        }
        // Squarified layouts keep the big tiles close to square.
        XCTAssertLessThan(max(rects[0].width / rects[0].height, rects[0].height / rects[0].width), 3)
        XCTAssertTrue(Treemap.squarify(areas: [], in: rect).isEmpty)
        XCTAssertEqual(Treemap.squarify(areas: [rect.area], in: rect), [rect])
    }

    func testTreemapLayoutNestsAndHitTests() throws {
        try write("big/a.mp4", bytes: 400_000)
        try write("big/b.jpg", bytes: 200_000)
        try write("small.zip", bytes: 100_000)
        let root = try scan()
        let rect = TreemapRect(x: 0, y: 0, width: 800, height: 500)
        let tiles = Treemap.layout(root: root, in: rect)

        let names = Set(tiles.map(\.node.name))
        XCTAssertEqual(names, ["big", "a.mp4", "b.jpg", "small.zip"])
        let big = try XCTUnwrap(tiles.first { $0.node.name == "big" })
        XCTAssertFalse(big.isLeaf)
        XCTAssertTrue(big.hasHeader)
        let video = try XCTUnwrap(tiles.first { $0.node.name == "a.mp4" })
        XCTAssertTrue(video.isLeaf)
        XCTAssertEqual(video.category, .videos)
        XCTAssertEqual(video.depth, 1)
        XCTAssertGreaterThanOrEqual(video.rect.y, big.rect.y + 17, "children sit below the header")
        XCTAssertLessThanOrEqual(video.rect.x + video.rect.width, big.rect.x + big.rect.width)

        let hit = Treemap.tile(at: video.rect.x + 2, video.rect.y + 2, in: tiles)
        XCTAssertTrue(hit?.node === video.node)
        XCTAssertNil(Treemap.tile(at: -5, -5, in: tiles))

        var options = TreemapOptions()
        options.maxTiles = 2
        XCTAssertLessThanOrEqual(Treemap.layout(root: root, in: rect, options: options).count, 2)
        root.teardown()
    }

    // MARK: Duplicates

    func testDuplicateFinder() throws {
        // Same content, three copies (larger than both samples).
        for name in ["dup/a.bin", "dup/b.bin", "other/c.bin"] {
            try write(name, bytes: 300_000, fill: 0x11)
        }
        // Same size and same head/tail, different middle: must not match.
        var tricky = Data(repeating: 0x11, count: 300_000)
        tricky[150_000] = 0x99
        try tricky.write(to: base.appendingPathComponent("dup/tricky.bin"))
        // Small identical pair, fully covered by the samples.
        try write("small1.txt", bytes: 70_000, fill: 0x22)
        try write("small2.txt", bytes: 70_000, fill: 0x22)
        // Same size, different content.
        try write("small3.txt", bytes: 70_000, fill: 0x33)
        // Below the minimum size.
        try write("tiny1", bytes: 100)
        try write("tiny2", bytes: 100)
        // Identical files inside a package are ignored.
        try write("X.app/Contents/a.bin", bytes: 300_000, fill: 0x11)

        let root = try scan()
        let candidates = DuplicateFinder.candidates(root: root, minSize: 1_000)
        XCTAssertEqual(candidates.count, 2)

        let finder = DuplicateFinder()
        let groups = finder.find(candidates: candidates)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].files.map(\.name).sorted(), ["a.bin", "b.bin", "c.bin"])
        XCTAssertEqual(groups[0].fileSize, 300_000)
        XCTAssertEqual(groups[0].reclaimableBytes, groups[0].files[0].size * 2)
        XCTAssertEqual(groups[1].files.map(\.name).sorted(), ["small1.txt", "small2.txt"])
        XCTAssertEqual(finder.progress.filesDone, finder.progress.filesTotal)
        XCTAssertLessThanOrEqual(finder.progress.fraction, 1)

        let cancelled = DuplicateFinder()
        cancelled.cancel()
        XCTAssertTrue(cancelled.find(candidates: candidates).isEmpty)
        root.teardown()
    }

    // MARK: Cleanup rules

    func testCleanupSuggestions() throws {
        let mb = 1_100_000
        try write("home/Library/Caches/com.app.one/data", bytes: 2 * mb)
        try write("home/Library/Caches/com.app.two/data", bytes: mb)
        try write("home/Library/Caches/tiny/data", bytes: 10)
        try write("home/.Trash/old.mov", bytes: 3 * mb)
        try write("home/Library/Developer/Xcode/DerivedData/Proj-abc/blob", bytes: 4 * mb)
        try write("home/code/web/package.json", bytes: 10)
        try write("home/code/web/node_modules/lib/index.js", bytes: 2 * mb)
        try write("home/code/web/node_modules/lib/node_modules/deep/x.js", bytes: mb)
        try write("home/code/rusty/Cargo.toml", bytes: 10)
        try write("home/code/rusty/target/debug/bin", bytes: 2 * mb)
        try write("home/code/notrust/target/thing", bytes: 2 * mb)
        try write("home/Downloads/Setup.dmg", bytes: 2 * mb)
        let old = try write("home/Downloads/ancient.zip", bytes: 2 * mb)
        try write("home/Downloads/fresh.zip", bytes: 2 * mb)
        let longAgo = Date(timeIntervalSinceNow: -400 * 86400)
        try FileManager.default.setAttributes([.modificationDate: longAgo], ofItemAtPath: old.path)

        let root = try scan()
        let options = CleanupRules.Options(homePath: base.path + "/home")
        let suggestions = CleanupRules.suggestions(root: root, options: options)
        let byKind = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.kind, $0) })

        XCTAssertEqual(byKind[.userCaches]?.items.map(\.name), ["com.app.one", "com.app.two"])
        XCTAssertEqual(byKind[.userCaches]?.safety, .safe)
        XCTAssertEqual(byKind[.trash]?.items.map(\.name), ["old.mov"])
        XCTAssertEqual(byKind[.xcodeDerivedData]?.items.map(\.name), ["Proj-abc"])
        XCTAssertEqual(byKind[.dependencyFolders]?.items.map(\.name).sorted(), ["node_modules", "target"])
        XCTAssertEqual(byKind[.dependencyFolders]?.items.first { $0.name == "target" }?.parent?.name, "rusty")
        XCTAssertEqual(byKind[.installers]?.items.map(\.name), ["Setup.dmg"])
        XCTAssertEqual(byKind[.oldDownloads]?.items.map(\.name), ["ancient.zip"])
        XCTAssertNil(byKind[.logs])
        XCTAssertEqual(suggestions.map(\.totalSize), suggestions.map(\.totalSize).sorted(by: >))

        // A scan that does not include the home folder still finds pattern matches.
        let outside = CleanupRules.suggestions(root: root, options: CleanupRules.Options(homePath: "/nowhere"))
        XCTAssertEqual(outside.map(\.kind), [.dependencyFolders])
        root.teardown()
    }

    // MARK: Organizer

    func testOrganizerPlans() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let march = Date(timeIntervalSince1970: 1_773_500_000) // 2026-03-14
        let entries = [
            Organizer.Entry(name: "holiday.JPG", isDirectory: false, modified: march, size: 10),
            Organizer.Entry(name: "report.pdf", isDirectory: false, modified: march),
            Organizer.Entry(name: "clip.mov", isDirectory: false, modified: march),
            Organizer.Entry(name: "README", isDirectory: false, modified: march),
            Organizer.Entry(name: ".DS_Store", isDirectory: false, modified: march),
            Organizer.Entry(name: "Folder", isDirectory: true, modified: march),
            Organizer.Entry(name: "movie.mp4.crdownload", isDirectory: false, modified: march),
        ]
        let byType = Organizer.plan(entries: entries, strategy: .byType, calendar: calendar)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: byType.map { ($0.name, $0.folder) }), [
            "holiday.JPG": "Images", "report.pdf": "Documents", "clip.mov": "Videos", "README": "Other",
        ])
        XCTAssertEqual(byType.first { $0.name == "holiday.JPG" }?.size, 10)

        let byMonth = Organizer.plan(entries: entries, strategy: .byMonth, calendar: calendar)
        XCTAssertTrue(byMonth.allSatisfy { $0.folder == "2026-03" })
        let byYear = Organizer.plan(entries: entries, strategy: .byYear, calendar: calendar)
        XCTAssertTrue(byYear.allSatisfy { $0.folder == "2026" })
        let byExt = Organizer.plan(entries: entries, strategy: .byExtension, calendar: calendar)
        XCTAssertEqual(Set(byExt.map(\.folder)), ["JPG", "PDF", "MOV", "No Extension"])

        XCTAssertEqual(Organizer.uniqueName(for: "a.pdf", existing: []), "a.pdf")
        XCTAssertEqual(Organizer.uniqueName(for: "a.pdf", existing: ["A.PDF"]), "a 2.pdf")
        XCTAssertEqual(Organizer.uniqueName(for: "a.pdf", existing: ["a.pdf", "a 2.pdf"]), "a 3.pdf")
        XCTAssertEqual(Organizer.uniqueName(for: "notes", existing: ["notes"]), "notes 2")
    }
}
