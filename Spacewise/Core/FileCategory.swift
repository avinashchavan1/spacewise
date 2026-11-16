import Foundation

/// Broad file type used for the breakdown chart, treemap colours and organizing.
enum FileCategory: Int, CaseIterable, Hashable, Sendable {
    case applications
    case videos
    case images
    case audio
    case documents
    case archives
    case developer
    case system
    case other

    var title: String {
        switch self {
        case .applications: return "Applications"
        case .videos: return "Videos"
        case .images: return "Images"
        case .audio: return "Audio"
        case .documents: return "Documents"
        case .archives: return "Archives & Disk Images"
        case .developer: return "Code & Developer"
        case .system: return "System & Caches"
        case .other: return "Other"
        }
    }

    /// Folder name used when organizing files by type.
    var folderName: String {
        switch self {
        case .applications: return "Applications"
        case .videos: return "Videos"
        case .images: return "Images"
        case .audio: return "Audio"
        case .documents: return "Documents"
        case .archives: return "Archives"
        case .developer: return "Code"
        case .system: return "System"
        case .other: return "Other"
        }
    }

    /// Extensions of directories the Finder presents as a single file.
    static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "plugin", "kext", "appex", "xpc", "prefpane", "qlgenerator",
        "saver", "component", "mdimporter", "photoslibrary", "musiclibrary", "tvlibrary",
        "imovielibrary", "fcpbundle", "logicx", "band", "xcodeproj", "xcworkspace", "playground",
        "xcarchive", "dsym", "rtfd", "pages", "numbers", "key", "sparsebundle", "pkg", "mpkg",
        "scptd", "wdgt", "docset", "lproj", "nib", "aplibrary", "theater", "photolibrary",
        "migratedphotolibrary", "screenflow", "sketch", "download",
    ]

    /// Where an item sits, which matters for files without a useful extension:
    /// most cache and app-support data on a Mac has none.
    enum Location: UInt8, Sendable {
        case normal
        /// Inside ~/Library or a hidden folder: unknown files count as system data.
        case library
        /// Inside a cache, log or build-data folder: everything counts as system data.
        case cache
    }

    private static let cacheFolderNames: Set<String> = [
        "Caches", "Logs", "DerivedData", "CoreSimulator", "ModuleCache.noindex", "_cacache", ".cache",
    ]

    /// Location of the contents of a folder called `name` inside a folder at `parent`.
    static func location(insideFolderNamed name: String, parent: Location) -> Location {
        if parent == .cache { return .cache }
        if cacheFolderNames.contains(name) || name.hasSuffix(" DeviceSupport") { return .cache }
        if name == "Library" || (name.hasPrefix(".") && name != ".Trash") { return .library }
        return parent
    }

    /// Location of the contents of `folder`, derived from its ancestors.
    static func location(inside folder: FSNode?) -> Location {
        guard let folder else { return .normal }
        var location = Location.normal
        for node in folder.ancestorsFromRoot {
            let name = node.parent == nil ? (node.name as NSString).lastPathComponent : node.name
            location = self.location(insideFolderNamed: name, parent: location)
        }
        return location
    }

    static func category(forFileExtension ext: String, in location: Location) -> FileCategory {
        if location == .cache { return .system }
        let category = category(forExtension: ext)
        if category == .other && location == .library { return .system }
        return category
    }

    static func category(forPackageExtension ext: String, in location: Location) -> FileCategory {
        location == .cache ? .system : category(forPackageExtension: ext)
    }

    /// Category of a file or package, or nil for a plain folder.
    static func category(of node: FSNode) -> FileCategory? {
        guard !node.isDirectory || node.isPackage else { return nil }
        let location = location(inside: node.parent)
        return node.isDirectory
            ? category(forPackageExtension: node.fileExtension, in: location)
            : category(forFileExtension: node.fileExtension, in: location)
    }

    static func isPackage(directoryExtension ext: String) -> Bool {
        packageExtensions.contains(ext)
    }

    static func category(forExtension ext: String) -> FileCategory {
        byExtension[ext] ?? .other
    }

    /// Category for a package directory, so its contents are counted as one thing.
    static func category(forPackageExtension ext: String) -> FileCategory {
        switch ext {
        case "app", "appex", "prefpane", "saver", "wdgt":
            return .applications
        case "photoslibrary", "photolibrary", "aplibrary", "migratedphotolibrary":
            return .images
        case "musiclibrary", "band", "logicx":
            return .audio
        case "tvlibrary", "imovielibrary", "fcpbundle", "theater", "screenflow":
            return .videos
        case "pages", "numbers", "key", "rtfd", "sketch":
            return .documents
        case "sparsebundle", "pkg", "mpkg", "download":
            return .archives
        case "xcodeproj", "xcworkspace", "playground", "xcarchive", "dsym", "docset", "nib", "scptd":
            return .developer
        default:
            return .system
        }
    }

    private static let byExtension: [String: FileCategory] = {
        var map: [String: FileCategory] = [:]
        func add(_ category: FileCategory, _ extensions: String) {
            for ext in extensions.split(separator: " ") {
                map[String(ext)] = category
            }
        }
        add(.videos, "mp4 mov m4v mkv avi wmv flv webm mpg mpeg m2ts mts ts 3gp vob ogv prores braw r3d mxf")
        add(.images, "jpg jpeg png gif heic heif tiff tif bmp webp raw cr2 cr3 nef arw dng orf rw2 raf psd psb ai svg ico icns eps xcf avif jxl exr hdr tga")
        add(.audio, "mp3 m4a aac wav flac aiff aif ogg oga opus wma alac caf mid midi m4b m4r amr ape")
        add(.documents, "pdf doc docx xls xlsx ppt pptx txt rtf md markdown pages numbers key odt ods odp csv tsv epub mobi azw3 tex djvu xps one eml msg ics vcf")
        add(.archives, "zip rar 7z tar gz tgz bz2 tbz xz txz zst lz lzma cab dmg iso img pkg mpkg xip sit sitx jar war apk ipa deb rpm cpgz vhd vmdk vdi qcow2 toast cdr sparseimage")
        add(.developer, "swift m mm h hpp c cc cpp cxx cs java kt kts scala go rs py pyc pyo rb php js jsx mjs cjs ts tsx vue svelte css scss sass less html htm xml json yaml yml toml ini cfg conf gradle sh bash zsh fish bat ps1 sql sqlite sqlite3 db o a so dylib class dex wasm lock log map patch diff ipynb r lua pl pm dart ex exs erl hs clj nim zig asm s plist storyboard xib xcconfig pbxproj entitlements strings car metallib tbd swiftmodule swiftdoc swiftinterface pch hmap dia")
        // Machine-learning models and weights, and compiled modules of developer tools.
        add(.developer, "safetensors gguf ggml onnx pt pth ckpt h5 keras tflite mlmodel npy npz node jmod pcm")
        add(.applications, "app exe msi")
        add(.system, "cache tmp temp bak swp dat bin sys dll kext ds_store localized")
        return map
    }()
}
