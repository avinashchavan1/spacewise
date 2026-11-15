import Foundation

/// Plans how to sort the loose files of a folder into subfolders.
enum Organizer {
    enum Strategy: String, CaseIterable, Identifiable, Sendable {
        case byType
        case byMonth
        case byYear
        case byExtension

        var id: String { rawValue }

        var title: String {
            switch self {
            case .byType: return "File Type"
            case .byMonth: return "Month Modified"
            case .byYear: return "Year Modified"
            case .byExtension: return "Extension"
            }
        }

        var explanation: String {
            switch self {
            case .byType: return "Images, Videos, Documents, Archives and so on."
            case .byMonth: return "One folder per month, such as 2026-03."
            case .byYear: return "One folder per year."
            case .byExtension: return "One folder per extension, such as PDF or ZIP."
            }
        }
    }

    struct Entry: Sendable {
        var name: String
        var isDirectory: Bool
        var modified: Date
        var size: Int64

        init(name: String, isDirectory: Bool, modified: Date, size: Int64 = 0) {
            self.name = name
            self.isDirectory = isDirectory
            self.modified = modified
            self.size = size
        }
    }

    struct Move: Sendable, Identifiable, Equatable {
        /// File name inside the folder being organized.
        var name: String
        /// Destination subfolder, relative to the folder being organized.
        var folder: String
        var size: Int64

        var id: String { name }
    }

    /// Decides where each loose file goes. Folders, hidden files and
    /// in-progress downloads stay where they are.
    static func plan(entries: [Entry], strategy: Strategy, calendar: Calendar = Calendar(identifier: .gregorian)) -> [Move] {
        var moves: [Move] = []
        for entry in entries {
            if entry.isDirectory || entry.name.hasPrefix(".") { continue }
            let ext = fileExtension(entry.name)
            if ["crdownload", "download", "part", "partial", "tmp"].contains(ext) { continue }

            let folder: String
            switch strategy {
            case .byType:
                folder = FileCategory.category(forExtension: ext).folderName
            case .byExtension:
                folder = ext.isEmpty ? "No Extension" : ext.uppercased()
            case .byYear:
                folder = String(calendar.component(.year, from: entry.modified))
            case .byMonth:
                let parts = calendar.dateComponents([.year, .month], from: entry.modified)
                let month = parts.month ?? 1
                folder = "\(parts.year ?? 1970)-\(month < 10 ? "0" : "")\(month)"
            }
            moves.append(Move(name: entry.name, folder: folder, size: entry.size))
        }
        return moves.sorted {
            $0.folder == $1.folder
                ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                : $0.folder < $1.folder
        }
    }

    /// A name that does not collide with `existing`, in the Finder's style:
    /// "Report.pdf" becomes "Report 2.pdf".
    static func uniqueName(for name: String, existing: Set<String>) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        guard taken.contains(name.lowercased()) else { return name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var counter = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            if !taken.contains(candidate.lowercased()) { return candidate }
            counter += 1
        }
    }

    private static func fileExtension(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }
}
