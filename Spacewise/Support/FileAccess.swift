import AppKit
import Foundation

/// Folder permissions. A sandboxed app can only read folders the user picked
/// in an open panel; a security-scoped bookmark lets it return to them later.
enum FileAccess {
    static let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    /// The user's actual home folder. Inside the sandbox `NSHomeDirectory()`
    /// points at the app container instead.
    static let realHomePath: String = {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return String(cString: directory)
        }
        return NSHomeDirectory()
    }()

    static var realHomeURL: URL { URL(fileURLWithPath: realHomePath, isDirectory: true) }

    @MainActor
    static func chooseFolder(startingAt directory: URL? = nil,
                             message: String = "Choose a folder or disk to analyze.",
                             prompt: String = "Scan") -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = false
        panel.message = message
        panel.prompt = prompt
        if let directory { panel.directoryURL = directory }
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// A folder the user scanned before, remembered across launches.
struct RecentLocation: Codable, Identifiable, Hashable {
    var path: String
    var bookmark: Data
    var lastUsed: Date

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
    var name: String {
        path == "/" ? "Macintosh HD" : FileManager.default.displayName(atPath: path)
    }
}

enum RecentLocations {
    private static let key = "recentLocations"
    private static let limit = 8

    static func load() -> [RecentLocation] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([RecentLocation].self, from: data) else { return [] }
        return items
    }

    static func save(_ items: [RecentLocation]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Records a folder the user just granted access to and returns the new list.
    static func remember(_ url: URL, in items: [RecentLocation]) -> [RecentLocation] {
        let options: URL.BookmarkCreationOptions = FileAccess.isSandboxed ? [.withSecurityScope] : []
        guard let bookmark = try? url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return items
        }
        var updated = items.filter { $0.path != url.path }
        updated.insert(RecentLocation(path: url.path, bookmark: bookmark, lastUsed: Date()), at: 0)
        if updated.count > limit { updated.removeLast(updated.count - limit) }
        save(updated)
        return updated
    }

    /// Resolves a bookmark back into a URL the app may read.
    static func resolve(_ location: RecentLocation) -> URL? {
        var stale = false
        let options: URL.BookmarkResolutionOptions = FileAccess.isSandboxed ? [.withSecurityScope] : []
        return try? URL(resolvingBookmarkData: location.bookmark, options: options, relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// A remembered folder that is, or contains, `url`.
    static func covering(_ url: URL, in items: [RecentLocation]) -> RecentLocation? {
        let path = url.path
        return items
            .filter { path == $0.path || $0.path == "/" || path.hasPrefix($0.path + "/") }
            .max { $0.path.count < $1.path.count }
    }
}
