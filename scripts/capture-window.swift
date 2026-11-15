// Prints the window number of the frontmost on-screen window owned by the given app.
// Usage: swift scripts/capture-window.swift Spacewise
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? "Spacewise"
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let match = info.first { window in
    (window[kCGWindowOwnerName as String] as? String) == owner
        && (window[kCGWindowLayer as String] as? Int) == 0
        && ((window[kCGWindowBounds as String] as? [String: Double])?["Width"] ?? 0) > 400
}
if let number = match?[kCGWindowNumber as String] as? Int {
    print(number)
} else {
    FileHandle.standardError.write("No window found for \(owner)\n".data(using: .utf8)!)
    exit(1)
}
