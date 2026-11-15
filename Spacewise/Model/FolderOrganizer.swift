import Foundation

/// Carries out an `Organizer` plan on disk and can put everything back.
enum FolderOrganizer {
    struct Record {
        var moves: [(from: URL, to: URL)] = []
        var createdFolders: [URL] = []
        var errors: [String] = []
    }

    /// The loose items of a folder. Packages such as apps count as files.
    static func entries(in folder: URL) throws -> [Organizer.Entry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey, .totalFileAllocatedSizeKey]
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [])
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isFolder = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
            return Organizer.Entry(
                name: url.lastPathComponent,
                isDirectory: isFolder,
                modified: values?.contentModificationDate ?? Date(),
                size: Int64(values?.totalFileAllocatedSize ?? 0)
            )
        }
    }

    static func apply(_ moves: [Organizer.Move], in folder: URL) -> Record {
        let manager = FileManager.default
        var record = Record()
        var namesByFolder: [String: Set<String>] = [:]

        for move in moves {
            let destinationFolder = folder.appendingPathComponent(move.folder, isDirectory: true)
            do {
                if namesByFolder[move.folder] == nil {
                    if manager.fileExists(atPath: destinationFolder.path) {
                        namesByFolder[move.folder] = Set(try manager.contentsOfDirectory(atPath: destinationFolder.path))
                    } else {
                        try manager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
                        record.createdFolders.append(destinationFolder)
                        namesByFolder[move.folder] = []
                    }
                }
                let name = Organizer.uniqueName(for: move.name, existing: namesByFolder[move.folder] ?? [])
                let source = folder.appendingPathComponent(move.name)
                let destination = destinationFolder.appendingPathComponent(name)
                try manager.moveItem(at: source, to: destination)
                namesByFolder[move.folder]?.insert(name)
                record.moves.append((from: source, to: destination))
            } catch {
                record.errors.append("\(move.name): \(error.localizedDescription)")
            }
        }
        return record
    }

    /// Moves everything back and removes the folders that were created, if empty.
    static func undo(_ record: Record) -> [String] {
        let manager = FileManager.default
        var errors: [String] = []
        for move in record.moves.reversed() {
            do {
                if manager.fileExists(atPath: move.from.path) {
                    errors.append("\(move.from.lastPathComponent): an item with this name already exists.")
                    continue
                }
                try manager.moveItem(at: move.to, to: move.from)
            } catch {
                errors.append("\(move.to.lastPathComponent): \(error.localizedDescription)")
            }
        }
        for folder in record.createdFolders {
            let remaining = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
            if remaining.filter({ $0 != ".DS_Store" }).isEmpty {
                try? manager.removeItem(at: folder)
            }
        }
        return errors
    }
}
