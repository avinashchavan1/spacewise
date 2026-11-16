import AppKit
import Observation
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case overview
    case explore
    case largeFiles
    case fileTypes
    case duplicates
    case cleanup
    case organize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .explore: return "Explore"
        case .largeFiles: return "Large Files"
        case .fileTypes: return "File Types"
        case .duplicates: return "Duplicates"
        case .cleanup: return "Cleanup"
        case .organize: return "Organize"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "internaldrive"
        case .explore: return "square.grid.2x2"
        case .largeFiles: return "doc.text.magnifyingglass"
        case .fileTypes: return "chart.pie"
        case .duplicates: return "doc.on.doc"
        case .cleanup: return "sparkles"
        case .organize: return "folder.badge.gearshape"
        }
    }

    /// Screens that only make sense once a scan has finished.
    var needsScan: Bool {
        switch self {
        case .overview, .organize: return false
        default: return true
        }
    }
}

struct ScanResult {
    let root: FSNode
    let rootURL: URL
    let finishedAt: Date
    let duration: TimeInterval
    let unreadableCount: Int
    var analysis: ScanAnalysis
    var suggestions: [CleanupSuggestion]

    var displayName: String {
        root.path == "/" ? "Macintosh HD" : FileManager.default.displayName(atPath: root.path)
    }
}

struct AlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// App state. Everything here is read and written on the main thread; the
/// heavy work (scanning, hashing, trashing) runs in detached tasks.
@MainActor
@Observable
final class AppModel {
    enum Phase {
        case idle
        case scanning
        case ready
    }

    enum DuplicateState {
        case idle
        case running
        case finished
    }

    var selection: SidebarItem? = .overview
    var phase: Phase = .idle
    var volumes: [VolumeInfo] = []
    var recents: [RecentLocation] = []

    var scanningURL: URL?
    var scanExpectedBytes: Int64 = 0
    var progress = ScanProgress.Snapshot()
    var result: ScanResult?
    /// Bumped whenever the scanned tree changes, so views that read plain
    /// `FSNode` values know to refresh.
    var revision = 0
    /// True when files were moved outside the app's knowledge of the tree.
    var isStale = false

    /// Folder shown in the Explore screen.
    var focus: FSNode?

    /// Items the user marked for removal.
    private(set) var collected: [FSNode] = []
    private var collectedIDs = Set<ObjectIdentifier>()

    var duplicateState: DuplicateState = .idle
    var duplicateGroups: [DuplicateGroup] = []
    /// Sets of identical files that are all APFS clones of one another. They
    /// already share their space, so they are left out of `duplicateGroups`.
    var hiddenCloneGroupCount = 0
    var duplicateProgress = DuplicateFinder.Progress()

    var isDeleting = false
    /// Items waiting for the user to confirm removal.
    var pendingTrash: [FSNode] = []
    var alert: AlertInfo?
    var quickLookURL: URL?

    @ObservationIgnored private var scanner: DiskScanner?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var duplicateFinder: DuplicateFinder?
    @ObservationIgnored private var scopedURL: URL?

    init() {
        recents = RecentLocations.load()
        refreshVolumes()
    }

    // MARK: - Volumes

    func refreshVolumes() {
        volumes = VolumeInfo.loadAll()
    }

    // MARK: - Scanning

    /// Shows the folder picker, then scans the chosen folder.
    func chooseFolderAndScan() {
        guard let url = FileAccess.chooseFolder(startingAt: FileAccess.realHomeURL) else { return }
        recents = RecentLocations.remember(url, in: recents)
        startScan(url)
    }

    /// Scans a known location, asking for permission first when the sandbox requires it.
    func requestScan(of url: URL) {
        if !FileAccess.isSandboxed {
            recents = RecentLocations.remember(url, in: recents)
            startScan(url)
            return
        }
        if let recent = RecentLocations.covering(url, in: recents), let granted = RecentLocations.resolve(recent) {
            startScan(url, accessVia: granted)
            return
        }
        let message = "macOS asks you to confirm before an app can read this location. Click Allow to scan it."
        guard let chosen = FileAccess.chooseFolder(startingAt: url, message: message, prompt: "Allow") else { return }
        recents = RecentLocations.remember(chosen, in: recents)
        startScan(chosen)
    }

    func scan(_ recent: RecentLocation) {
        guard let granted = RecentLocations.resolve(recent) else {
            recents.removeAll { $0.id == recent.id }
            RecentLocations.save(recents)
            alert = AlertInfo(title: "Folder Unavailable",
                              message: "“\(recent.name)” could not be opened. It may have been moved or deleted.")
            return
        }
        startScan(granted, accessVia: granted)
    }

    func rescan() {
        guard let url = result?.rootURL ?? scanningURL else { return }
        requestScan(of: url)
    }

    func cancelScan() {
        scanner?.cancel()
    }

    private func startScan(_ url: URL, accessVia scoped: URL? = nil) {
        scanner?.cancel()
        progressTask?.cancel()
        cancelDuplicateSearch()
        discardResult()

        // Hold the security scope for as long as this scan's results are in use.
        if let previous = scopedURL {
            previous.stopAccessingSecurityScopedResource()
            scopedURL = nil
        }
        if let scoped, scoped.startAccessingSecurityScopedResource() {
            scopedURL = scoped
        }

        let scanner = DiskScanner()
        self.scanner = scanner
        scanningURL = url
        progress = ScanProgress.Snapshot()
        phase = .scanning
        refreshVolumes()
        scanExpectedBytes = volumes.first { $0.url.path == url.path }?.used ?? 0

        let path = url.path
        let home = FileAccess.realHomePath
        let ageDays = UserDefaults.standard.object(forKey: SettingsKey.oldDownloadDays) as? Int ?? 180
        let started = Date()

        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                guard let self, self.scanner === scanner else { return }
                self.progress = scanner.progress.snapshot()
            }
        }

        Task.detached(priority: .userInitiated) {
            let root = scanner.scan(rootPath: path, options: ScanOptions.recommended(forRoot: path))
            var analysis = ScanAnalysis()
            var suggestions: [CleanupSuggestion] = []
            if let root {
                analysis = ScanAnalysis.analyze(root: root)
                var options = CleanupRules.Options(homePath: home)
                options.oldDownloadAge = TimeInterval(ageDays) * 86400
                suggestions = CleanupRules.suggestions(root: root, options: options)
            }
            let snapshot = scanner.progress.snapshot()
            let finalAnalysis = analysis
            let finalSuggestions = suggestions
            await MainActor.run {
                self.finishScan(scanner: scanner, url: url, root: root, analysis: finalAnalysis,
                                suggestions: finalSuggestions, snapshot: snapshot, started: started)
            }
        }
    }

    private func finishScan(scanner: DiskScanner, url: URL, root: FSNode?, analysis: ScanAnalysis,
                            suggestions: [CleanupSuggestion], snapshot: ScanProgress.Snapshot, started: Date) {
        // A newer scan replaced this one while it was finishing.
        guard self.scanner === scanner else {
            if let root { AppModel.release(root) }
            return
        }
        progressTask?.cancel()
        progressTask = nil
        self.scanner = nil
        progress = snapshot

        guard let root else {
            phase = .idle
            scanningURL = nil
            if !scanner.isCancelled {
                alert = AlertInfo(title: "Couldn’t Scan Folder",
                                  message: "“\(url.lastPathComponent)” could not be read. Check that it still exists and that you have permission to open it.")
            }
            return
        }

        result = ScanResult(root: root, rootURL: url, finishedAt: Date(),
                            duration: Date().timeIntervalSince(started),
                            unreadableCount: snapshot.unreadable,
                            analysis: analysis, suggestions: suggestions)
        focus = root
        isStale = false
        revision += 1
        phase = .ready
        refreshVolumes()
    }

    private func discardResult() {
        if let root = result?.root {
            AppModel.release(root)
        }
        result = nil
        focus = nil
        collected = []
        collectedIDs = []
        duplicateGroups = []
        hiddenCloneGroupCount = 0
        duplicateState = .idle
        isStale = false
        revision += 1
    }

    /// Frees a tree in the background; a full-disk tree has millions of nodes.
    private static func release(_ root: FSNode) {
        Task.detached(priority: .utility) {
            // Give views a moment to drop their references before the tree is taken apart.
            try? await Task.sleep(for: .seconds(3))
            root.teardown()
        }
    }

    // MARK: - Navigation

    func open(_ node: FSNode) {
        guard node.isInTree else { return }
        if node.isDirectory && !node.children.isEmpty {
            focus = node
        } else if let parent = node.parent {
            focus = parent
        }
        selection = .explore
    }

    func goUp() {
        if let parent = focus?.parent { focus = parent }
    }

    // MARK: - Cleanup list

    var collectedSize: Int64 { collected.reduce(0) { $0 + $1.size } }

    func isCollected(_ node: FSNode) -> Bool {
        collectedIDs.contains(ObjectIdentifier(node))
    }

    /// True when the node or a folder containing it is on the cleanup list.
    func isCoveredByCollection(_ node: FSNode) -> Bool {
        var current: FSNode? = node
        while let candidate = current {
            if collectedIDs.contains(ObjectIdentifier(candidate)) { return true }
            current = candidate.parent
        }
        return false
    }

    func collect(_ nodes: [FSNode]) {
        for node in nodes {
            guard node.parent != nil, node.isInTree, !isCoveredByCollection(node) else { continue }
            // A folder replaces anything inside it that was already listed.
            if node.isDirectory {
                let inside = collected.filter { $0.isDescendant(of: node) }
                if !inside.isEmpty {
                    for item in inside { collectedIDs.remove(ObjectIdentifier(item)) }
                    collected.removeAll { $0.isDescendant(of: node) }
                }
            }
            collected.append(node)
            collectedIDs.insert(ObjectIdentifier(node))
        }
    }

    func uncollect(_ nodes: [FSNode]) {
        let ids = Set(nodes.map { ObjectIdentifier($0) })
        collected.removeAll { ids.contains(ObjectIdentifier($0)) }
        collectedIDs.subtract(ids)
    }

    func toggleCollected(_ node: FSNode) {
        if isCollected(node) {
            uncollect([node])
        } else {
            collect([node])
        }
    }

    func setCollected(_ node: FSNode, _ isOn: Bool) {
        if isOn {
            collect([node])
        } else {
            uncollect([node])
        }
    }

    func clearCollection() {
        collected = []
        collectedIDs = []
    }

    // MARK: - File actions

    func reveal(_ nodes: [FSNode]) {
        let urls = nodes.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func quickLook(_ node: FSNode) {
        quickLookURL = node.url
    }

    func copyPath(_ nodes: [FSNode]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(nodes.map(\.path).joined(separator: "\n"), forType: .string)
    }

    /// Removes items, asking first unless the user turned confirmation off.
    func requestTrash(_ nodes: [FSNode]) {
        let targets = nodes.filter { $0.parent != nil && $0.isInTree }
        guard !targets.isEmpty else { return }
        let confirm = UserDefaults.standard.object(forKey: SettingsKey.confirmBeforeTrash) as? Bool ?? true
        if confirm {
            pendingTrash = targets
        } else {
            moveToTrash(targets)
        }
    }

    /// Moves items to the Trash (or deletes them for good if they are already
    /// in the Trash) and removes them from the scanned tree.
    func moveToTrash(_ nodes: [FSNode]) {
        let targets = AppModel.withoutNestedItems(nodes.filter { $0.parent != nil && $0.isInTree })
        guard !targets.isEmpty, !isDeleting else { return }
        isDeleting = true

        let jobs = targets.map { (url: $0.url, path: $0.path) }
        Task {
            let failures: [String?] = await Task.detached(priority: .userInitiated) {
                let manager = FileManager.default
                return jobs.map { job -> String? in
                    do {
                        if job.path.contains("/.Trash/") {
                            try manager.removeItem(at: job.url)
                        } else {
                            try manager.trashItem(at: job.url, resultingItemURL: nil)
                        }
                        return nil
                    } catch {
                        // Already gone counts as done.
                        return manager.fileExists(atPath: job.path) ? error.localizedDescription : nil
                    }
                }
            }.value

            var freed: Int64 = 0
            var problems: [String] = []
            for (node, failure) in zip(targets, failures) {
                if let failure {
                    problems.append("\(node.displayName): \(failure)")
                } else {
                    freed += node.size
                    result?.analysis.subtract(node)
                    node.removeFromTree()
                }
            }
            treeDidChange()
            isDeleting = false

            if !problems.isEmpty {
                let shown = problems.prefix(6).joined(separator: "\n")
                let more = problems.count > 6 ? "\n…and \(problems.count - 6) more." : ""
                alert = AlertInfo(title: problems.count == 1 ? "1 Item Couldn’t Be Removed" : "\(problems.count) Items Couldn’t Be Removed",
                                  message: shown + more)
            }
        }
    }

    /// Drops references to nodes that left the tree and refreshes dependent state.
    private func treeDidChange() {
        result?.analysis.removeDetachedNodes()
        if var suggestions = result?.suggestions {
            for index in suggestions.indices {
                suggestions[index].items.removeAll { !$0.isInTree }
            }
            suggestions.removeAll { $0.items.isEmpty }
            result?.suggestions = suggestions
        }
        for index in duplicateGroups.indices {
            duplicateGroups[index].files.removeAll { !$0.isInTree }
        }
        duplicateGroups.removeAll { $0.files.count < 2 || $0.isOnlyClones }

        let gone = collected.filter { !$0.isInTree }
        if !gone.isEmpty { uncollect(gone) }

        var current = focus
        while let node = current, !node.isInTree {
            current = node.parent
        }
        focus = current ?? result?.root

        revision += 1
        refreshVolumes()
    }

    /// Removes items that sit inside another item of the same list.
    private static func withoutNestedItems(_ nodes: [FSNode]) -> [FSNode] {
        let ids = Set(nodes.map { ObjectIdentifier($0) })
        var seen = Set<ObjectIdentifier>()
        return nodes.filter { node in
            guard seen.insert(ObjectIdentifier(node)).inserted else { return false }
            var ancestor = node.parent
            while let current = ancestor {
                if ids.contains(ObjectIdentifier(current)) { return false }
                ancestor = current.parent
            }
            return true
        }
    }

    // MARK: - Duplicates

    func findDuplicates(minimumSize: Int64) {
        guard let root = result?.root, duplicateState != .running else { return }
        let candidates = DuplicateFinder.candidates(root: root, minSize: minimumSize)
        let finder = DuplicateFinder()
        duplicateFinder = finder
        duplicateGroups = []
        hiddenCloneGroupCount = 0
        duplicateProgress = DuplicateFinder.Progress()
        duplicateState = .running

        Task {
            let poll = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard let self, self.duplicateFinder === finder else { return }
                    self.duplicateProgress = finder.progress
                }
            }
            let groups = await Task.detached(priority: .userInitiated) {
                finder.find(candidates: candidates)
            }.value
            poll.cancel()

            guard duplicateFinder === finder else { return }
            duplicateFinder = nil
            if finder.isCancelled {
                duplicateState = .idle
                return
            }
            let current = groups
                .map { group in
                    var kept = group
                    kept.files.removeAll { !$0.isInTree }
                    return kept
                }
                .filter { $0.files.count > 1 }
            duplicateGroups = current.filter { !$0.isOnlyClones }
            hiddenCloneGroupCount = current.count - duplicateGroups.count
            duplicateState = .finished
        }
    }

    func cancelDuplicateSearch() {
        duplicateFinder?.cancel()
        duplicateFinder = nil
        if duplicateState == .running { duplicateState = .idle }
    }

    /// Marks every copy except the first in each group for removal. Clones of
    /// the kept copy are left alone: they share its space, so removing them
    /// would free nothing.
    func collectExtraDuplicates() {
        var extras: [FSNode] = []
        for group in duplicateGroups {
            let alreadyKept = group.files.first { !isCoveredByCollection($0) }
            guard let keep = alreadyKept else { continue }
            extras.append(contentsOf: group.files.filter { $0 !== keep && !group.areClones($0, keep) })
        }
        collect(extras)
    }

    // MARK: - Summaries

    /// Space that the "safe" cleanup suggestions would free.
    var safelyReclaimableBytes: Int64 {
        (result?.suggestions ?? []).filter { $0.safety == .safe }.reduce(0) { $0 + $1.totalSize }
    }

    func markStale() {
        isStale = true
    }
}

enum SettingsKey {
    static let oldDownloadDays = "oldDownloadDays"
    static let confirmBeforeTrash = "confirmBeforeTrash"
    static let duplicateMinimumMB = "duplicateMinimumMB"
}
