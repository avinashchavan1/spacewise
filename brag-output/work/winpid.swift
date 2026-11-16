import CoreGraphics
import Foundation
let pid = Int(CommandLine.arguments[1])!
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
if let w = info.first(where: { ($0[kCGWindowOwnerPID as String] as? Int) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 && ((($0[kCGWindowBounds as String] as? [String: Double])?["Width"]) ?? 0) > 400 }),
   let n = w[kCGWindowNumber as String] as? Int { print(n) } else { exit(1) }
