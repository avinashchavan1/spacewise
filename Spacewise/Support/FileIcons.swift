import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Finder icons, cached so scrolling long lists stays smooth. Plain files
/// share one icon per extension; apps and other packages get their own.
@MainActor
enum FileIcons {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 600
        return cache
    }()

    static func icon(for node: FSNode) -> NSImage {
        let key: String
        if node.isDirectory {
            key = node.isPackage ? "path:" + node.path : "folder"
        } else {
            key = "ext:" + node.fileExtension
        }
        if let cached = cache.object(forKey: key as NSString) { return cached }

        let image: NSImage
        if node.isDirectory {
            image = node.isPackage
                ? NSWorkspace.shared.icon(forFile: node.path)
                : NSWorkspace.shared.icon(for: .folder)
        } else if let type = UTType(filenameExtension: node.fileExtension) {
            image = NSWorkspace.shared.icon(for: type)
        } else {
            image = NSWorkspace.shared.icon(for: .data)
        }
        cache.setObject(image, forKey: key as NSString)
        return image
    }

    static func icon(forPath path: String) -> NSImage {
        let key = "path:" + path
        if let cached = cache.object(forKey: key as NSString) { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(image, forKey: key as NSString)
        return image
    }
}

struct FileIconView: View {
    let node: FSNode
    var size: CGFloat = 18

    var body: some View {
        Image(nsImage: FileIcons.icon(for: node))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
