import Foundation

/// Folders that Spacewise never offers to remove, because losing them would
/// break macOS, the user account or installed tools. Their contents can still
/// be removed one by one.
enum ProtectedLocations {
    /// Folders directly inside the home folder that macOS expects to exist.
    static let homeFolders: Set<String> = [
        "Applications", "Desktop", "Documents", "Downloads", "Library",
        "Movies", "Music", "Pictures", "Public", "Sites", ".Trash",
    ]

    /// Other locations that hold installed tools.
    static let extraPaths: Set<String> = [
        "/opt/homebrew", "/usr/local", "/Applications/Utilities",
    ]

    /// True when the item at `path` must not be moved to the Trash.
    /// `homePath` is the user's real home folder.
    static func isProtected(_ path: String, homePath: String) -> Bool {
        let path = DiskScanner.normalize(path)
        let home = DiskScanner.normalize(homePath)
        let components = path.split(separator: "/")

        // The disk itself and everything directly on it: /System, /Users, /Applications, /opt…
        if components.count <= 1 { return true }
        // macOS itself (read-only, but never offer it).
        if components[0] == "System" { return true }
        // /private/var, /private/etc, /private/tmp…
        if components[0] == "private" && components.count == 2 { return true }
        // Every user's home folder, and anything above it.
        if components[0] == "Users" && components.count == 2 { return true }
        if path == home || home.hasPrefix(path + "/") { return true }
        if extraPaths.contains(path) { return true }

        if path.hasPrefix(home + "/") {
            let inside = path.dropFirst(home.count + 1).split(separator: "/")
            // ~/Desktop, ~/Documents, ~/Library…
            if inside.count == 1 && homeFolders.contains(String(inside[0])) { return true }
            // ~/Library/Application Support, ~/Library/Caches, ~/Library/Preferences…
            if inside.count == 2 && inside[0] == "Library" { return true }
        }
        return false
    }
}
