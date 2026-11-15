import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.confirmBeforeTrash) private var confirmBeforeTrash = true
    @AppStorage(SettingsKey.oldDownloadDays) private var oldDownloadDays = 180
    @AppStorage(SettingsKey.duplicateMinimumMB) private var duplicateMinimumMB = 1

    var body: some View {
        Form {
            Section("Removing Files") {
                Toggle("Ask before moving items to the Trash", isOn: $confirmBeforeTrash)
                Text("Removed items go to the Trash, so you can put them back until you empty it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Suggestions") {
                Picker("Treat downloads as old after", selection: $oldDownloadDays) {
                    Text("1 month").tag(30)
                    Text("3 months").tag(90)
                    Text("6 months").tag(180)
                    Text("1 year").tag(365)
                }
                Picker("Smallest file to check for duplicates", selection: $duplicateMinimumMB) {
                    Text("100 KB").tag(0)
                    Text("1 MB").tag(1)
                    Text("10 MB").tag(10)
                    Text("100 MB").tag(100)
                }
                Text("Changes apply to the next scan.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Text("Spacewise reads file names and sizes on this Mac only. Nothing leaves your computer.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Open Full Disk Access Settings…") { FileAccess.openFullDiskAccessSettings() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
