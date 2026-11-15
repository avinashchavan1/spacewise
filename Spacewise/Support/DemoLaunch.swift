#if DEBUG
import AppKit

/// Debug-only launch arguments used to capture screenshots automatically, e.g.
///
///     Spacewise -SpacewiseScan /path -SpacewiseTab cleanup -SpacewiseWindowSize 1280x800
///
/// None of this is compiled into Release builds.
@MainActor
enum DemoLaunch {
    static let scanKey = "SpacewiseScan"
    static let homeKey = "SpacewiseHome"
    static let tabKey = "SpacewiseTab"
    static let organizeKey = "SpacewiseOrganize"
    static let collectSafeKey = "SpacewiseCollectSafe"
    static let windowSizeKey = "SpacewiseWindowSize"
    static let focusKey = "SpacewiseFocus"

    private static var didRun = false

    static func run(_ model: AppModel) {
        guard !didRun else { return }
        didRun = true
        let defaults = UserDefaults.standard

        if let size = defaults.string(forKey: windowSizeKey) {
            let parts = size.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 {
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
                        window.setFrame(NSRect(x: 40, y: 40, width: parts[0], height: parts[1]), display: true)
                    }
                }
            }
        }

        let tab = defaults.string(forKey: tabKey).flatMap(SidebarItem.init(rawValue:))
        guard let path = defaults.string(forKey: scanKey) else {
            if let tab { model.selection = tab }
            return
        }

        model.requestScan(of: URL(fileURLWithPath: path, isDirectory: true))
        Task {
            while model.phase != .ready {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if let focus = defaults.string(forKey: focusKey), let node = model.result?.root.descendant(atPath: focus) {
                model.open(node)
            }
            if defaults.bool(forKey: collectSafeKey) {
                model.collect((model.result?.suggestions ?? []).filter { $0.safety == .safe }.flatMap(\.items))
            }
            if let tab {
                model.selection = tab
                if tab == .duplicates {
                    model.findDuplicates(minimumSize: 100_000)
                }
            }
        }
    }
}
#endif
