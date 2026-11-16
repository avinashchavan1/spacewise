import SwiftUI

/// Thin proportional bar used next to sizes.
struct SizeBar: View {
    let fraction: Double
    var color: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color)
                    .frame(width: max(3, geometry.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

/// Checkbox that puts an item on the cleanup list.
struct CollectToggle: View {
    let model: AppModel
    let node: FSNode

    var body: some View {
        Toggle("Add to cleanup list", isOn: Binding(
            get: { model.isCollected(node) },
            set: { model.setCollected(node, $0) }
        ))
        .toggleStyle(.checkbox)
        .labelsHidden()
        .disabled(model.isProtected(node) || (!model.isCollected(node) && model.isCoveredByCollection(node)))
        .help(model.isProtected(node) ? "Protected: macOS or your account depends on this folder" : "Add to the cleanup list")
    }
}

/// Icon, name and location of a file, for lists and tables.
struct FileNameCell: View {
    let node: FSNode
    var showsLocation = false

    var body: some View {
        HStack(spacing: 8) {
            FileIconView(node: node, size: showsLocation ? 28 : 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if showsLocation {
                    Text(node.locationDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
        }
    }
}

/// Context menu shared by every list of files.
struct NodeMenuItems: View {
    let model: AppModel
    let nodes: [FSNode]

    var body: some View {
        if nodes.isEmpty {
            Text("No Selection")
        } else {
            Button("Show in Finder") { model.reveal(nodes) }
            if nodes.count == 1, let node = nodes.first {
                Button("Quick Look") { model.quickLook(node) }
                Button("Show in Explore") { model.open(node) }
            }
            Button(nodes.count == 1 ? "Copy Path" : "Copy Paths") { model.copyPath(nodes) }
            Divider()
            let protected = nodes.contains { model.isProtected($0) }
            if nodes.allSatisfy({ model.isCollected($0) }) {
                Button("Remove from Cleanup List") { model.uncollect(nodes) }
            } else {
                Button("Add to Cleanup List") { model.collect(nodes) }
                    .disabled(protected)
            }
            Button("Move to Trash…", role: .destructive) { model.requestTrash(nodes) }
                .disabled(protected)
        }
    }
}

/// Small rounded label, used for "Safe" and "Review".
struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Headline number with a caption, used on the overview.
struct StatTile: View {
    let title: String
    let value: String
    var symbol: String
    var tint: Color = .accentColor

    var body: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
        }
    }
}

/// Shown on screens that need a scan when there is none yet.
struct NoScanView: View {
    @Environment(AppModel.self) private var model
    let item: SidebarItem

    var body: some View {
        ContentUnavailableView {
            Label("Nothing Scanned Yet", systemImage: item.symbol)
        } description: {
            Text("Scan a folder or disk to see \(item.title.lowercased()).")
        } actions: {
            Button("Scan Home Folder") { model.requestScan(of: FileAccess.realHomeURL) }
                .buttonStyle(.borderedProminent)
            Button("Choose Folder…") { model.chooseFolderAndScan() }
        }
    }
}

/// Banner shown when files moved since the scan.
struct StaleBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.arrow.circlepath")
                .foregroundStyle(.orange)
            Text("Files have moved since this scan, so sizes may be out of date.")
            Spacer()
            Button("Rescan") { model.rescan() }
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
