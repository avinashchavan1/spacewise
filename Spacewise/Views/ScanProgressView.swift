import SwiftUI

struct ScanProgressView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let progress = model.progress
        let expected = model.scanExpectedBytes

        VStack(spacing: 18) {
            Image(systemName: "internaldrive")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse)

            Text("Scanning \(scanName)")
                .font(.title2.weight(.semibold))

            Group {
                if expected > 0 {
                    ProgressView(value: Double(min(progress.bytes, expected)), total: Double(expected))
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
            }
            .frame(width: 340)

            Text("\(formatFiles(progress.files)) · \(formatBytes(progress.bytes))")
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Text(abbreviatePath(progress.currentPath))
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520)
                .frame(height: 16)

            Button("Stop") { model.cancelScan() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(40)
    }

    private var scanName: String {
        guard let url = model.scanningURL else { return "" }
        return url.path == "/" ? "Macintosh HD" : FileManager.default.displayName(atPath: url.path)
    }
}
