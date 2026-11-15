import Foundation

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
}

func formatCount(_ count: Int) -> String {
    count.formatted(.number)
}

func formatItems(_ count: Int) -> String {
    count == 1 ? "1 item" : "\(formatCount(count)) items"
}

func formatFiles(_ count: Int) -> String {
    count == 1 ? "1 file" : "\(formatCount(count)) files"
}

/// Replaces the home directory prefix with "~" the way the Finder and Terminal do.
func abbreviatePath(_ path: String) -> String {
    let home = FileAccess.realHomePath
    if path == home { return "~" }
    if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
    return path
}

extension FSNode: Identifiable {}

extension FSNode {
    var modifiedDate: Date { Date(timeIntervalSince1970: TimeInterval(modified)) }

    var category: FileCategory? {
        FileCategory.category(of: self)
    }

    /// Folder that contains this item, abbreviated for display.
    var locationDescription: String {
        guard let parent else { return "" }
        return abbreviatePath(parent.path)
    }

    var kindDescription: String {
        if isDirectory && !isPackage { return "Folder" }
        let ext = fileExtension
        if isPackage && ext == "app" { return "Application" }
        return ext.isEmpty ? "Document" : ext.uppercased()
    }

    /// Description of what is inside, for folders.
    var contentsDescription: String {
        isDirectory ? formatFiles(Int(fileCount)) : kindDescription
    }
}
