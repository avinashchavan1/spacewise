import SwiftUI

@main
struct SpacewiseApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Spacewise", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 860, minHeight: 540)
                #if DEBUG
                .task { DemoLaunch.run(model) }
                #endif
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Scan Folder…") { model.chooseFolderAndScan() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Scan Home Folder") { model.requestScan(of: FileAccess.realHomeURL) }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Divider()
                Button("Rescan") { model.rescan() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.result == nil || model.phase == .scanning)
                Button("Stop Scanning") { model.cancelScan() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(model.phase != .scanning)
            }
            CommandMenu("Cleanup") {
                Button("Move Cleanup List to Trash…") { model.requestTrash(model.collected) }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(model.collected.isEmpty || model.isDeleting)
                Button("Clear Cleanup List") { model.clearCollection() }
                    .disabled(model.collected.isEmpty)
            }
            SidebarCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
