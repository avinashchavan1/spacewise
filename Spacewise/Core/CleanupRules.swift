import Foundation

/// A group of items that are usually safe or worthwhile to remove.
struct CleanupSuggestion: Identifiable, @unchecked Sendable {
    enum Safety: Int, Sendable {
        /// Recreated automatically when needed.
        case safe
        /// The user should look before deleting.
        case review
    }

    enum Kind: String, Sendable, CaseIterable {
        case trash
        case userCaches
        case logs
        case xcodeDerivedData
        case xcodeDeviceSupport
        case xcodeArchives
        case simulators
        case packageCaches
        case dependencyFolders
        case installers
        case oldDownloads
        case iosBackups
    }

    let kind: Kind
    let title: String
    let detail: String
    let safety: Safety
    var items: [FSNode]

    var id: String { kind.rawValue }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
}

enum CleanupRules {
    struct Options: Sendable {
        /// The user's real home directory (not the sandbox container).
        var homePath: String
        /// Downloads untouched for this long are suggested for review.
        var oldDownloadAge: TimeInterval = 180 * 24 * 3600
        /// Ignore anything smaller than this.
        var minimumItemSize: Int64 = 1 << 20
        var now: Date = Date()
    }

    static func suggestions(root: FSNode, options: Options) -> [CleanupSuggestion] {
        var result: [CleanupSuggestion] = []
        let home = DiskScanner.normalize(options.homePath)
        let minimum = options.minimumItemSize

        func node(_ relativePath: String) -> FSNode? {
            root.descendant(atPath: home + "/" + relativePath)
        }

        /// The children of a known folder, biggest first.
        func contents(of relativePaths: [String]) -> [FSNode] {
            relativePaths
                .compactMap { node($0) }
                .flatMap { $0.children }
                .filter { $0.size >= minimum }
                .sorted { $0.size > $1.size }
        }

        /// The folders themselves, when present.
        func folders(_ relativePaths: [String]) -> [FSNode] {
            relativePaths
                .compactMap { node($0) }
                .filter { $0.size >= minimum }
                .sorted { $0.size > $1.size }
        }

        func add(_ kind: CleanupSuggestion.Kind, _ title: String, _ detail: String,
                 _ safety: CleanupSuggestion.Safety, _ items: [FSNode]) {
            guard !items.isEmpty else { return }
            result.append(CleanupSuggestion(kind: kind, title: title, detail: detail, safety: safety, items: items))
        }

        add(.trash, "Trash",
            "Items already in the Trash still take up space until it is emptied.",
            .safe, contents(of: [".Trash"]))

        add(.userCaches, "App Caches",
            "Temporary data apps keep to load faster. Apps rebuild it when needed.",
            .safe, contents(of: ["Library/Caches"]))

        add(.logs, "Logs",
            "Diagnostic logs written by apps and the system.",
            .safe, contents(of: ["Library/Logs"]))

        add(.xcodeDerivedData, "Xcode Build Data",
            "Derived data and module caches. Xcode rebuilds them on the next build.",
            .safe, contents(of: ["Library/Developer/Xcode/DerivedData"]))

        add(.xcodeDeviceSupport, "Xcode Device Support",
            "Debug symbols for devices you connected. Xcode downloads them again if needed.",
            .safe, contents(of: [
                "Library/Developer/Xcode/iOS DeviceSupport",
                "Library/Developer/Xcode/watchOS DeviceSupport",
                "Library/Developer/Xcode/tvOS DeviceSupport",
                "Library/Developer/Xcode/visionOS DeviceSupport",
            ]))

        add(.xcodeArchives, "Xcode Archives",
            "Archived builds of your apps. Keep the ones you may need to symbolicate crash reports.",
            .review, contents(of: ["Library/Developer/Xcode/Archives"]))

        add(.simulators, "Simulators",
            "Simulator devices and their caches. Unused devices can be removed.",
            .review, folders(["Library/Developer/CoreSimulator/Caches"])
                + contents(of: ["Library/Developer/CoreSimulator/Devices"]))

        add(.packageCaches, "Package Manager Caches",
            "Downloaded packages kept by developer tools. They are fetched again when needed.",
            .safe, folders([
                ".npm/_cacache", ".yarn/cache", ".pnpm-store", "Library/pnpm/store",
                ".gradle/caches", ".m2/repository", ".cocoapods/repos", ".cargo/registry",
                ".cache", ".bun/install/cache", ".pub-cache", "go/pkg/mod",
                "Library/Caches/Homebrew", "Library/Caches/pip", "Library/Caches/CocoaPods",
                "Library/Caches/org.swift.swiftpm", "Library/Caches/Yarn",
            ]).filter { item in
                // Entries under Library/Caches are already listed under App Caches.
                !(item.parent?.name == "Caches" && item.parent?.parent?.name == "Library")
            })

        add(.iosBackups, "iPhone and iPad Backups",
            "Local device backups. Delete only backups you no longer need.",
            .review, contents(of: ["Library/Application Support/MobileSync/Backup"]))

        // Pattern-based rules need a walk over the tree.
        var dependencyFolders: [FSNode] = []
        root.walk { item in
            guard item.isDirectory else { return false }
            if item.isPackage && item !== root { return false }
            if item.name == "Library" && item.parent?.path == home { return false }
            guard let parent = item.parent else { return true }
            let isDependencyFolder: Bool
            switch item.name {
            case "node_modules":
                isDependencyFolder = true
            case "Pods":
                isDependencyFolder = parent.child(named: "Podfile") != nil
            case "target":
                isDependencyFolder = parent.child(named: "Cargo.toml") != nil
            case ".build":
                isDependencyFolder = parent.child(named: "Package.swift") != nil
            case ".venv", "venv":
                isDependencyFolder = item.child(named: "pyvenv.cfg") != nil
            case ".gradle", "build":
                isDependencyFolder = parent.child(named: "build.gradle") != nil
                    || parent.child(named: "build.gradle.kts") != nil
            case ".next", ".nuxt":
                isDependencyFolder = parent.child(named: "package.json") != nil
            default:
                isDependencyFolder = false
            }
            if isDependencyFolder {
                if item.size >= minimum { dependencyFolders.append(item) }
                return false
            }
            return true
        }
        add(.dependencyFolders, "Project Dependencies and Build Folders",
            "Folders such as node_modules, Pods and build output. Your tools recreate them from the project.",
            .review, dependencyFolders.sorted { $0.size > $1.size })

        if let downloads = node("Downloads") {
            let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip", "ipsw"]
            var installers: [FSNode] = []
            var stale: [FSNode] = []
            let cutoff = Int64(options.now.timeIntervalSince1970 - options.oldDownloadAge)
            for item in downloads.children where item.size >= minimum {
                if installerExtensions.contains(item.fileExtension) {
                    installers.append(item)
                } else if item.modified < cutoff && !item.name.hasPrefix(".") {
                    stale.append(item)
                }
            }
            add(.installers, "Installers in Downloads",
                "Disk images and installer packages. They are rarely needed after the app is installed.",
                .review, installers)
            let days = Int(options.oldDownloadAge / 86400)
            add(.oldDownloads, "Old Downloads",
                "Items in Downloads that have not changed in more than \(days) days.",
                .review, stale)
        }

        return result.sorted { $0.totalSize > $1.totalSize }
    }
}
