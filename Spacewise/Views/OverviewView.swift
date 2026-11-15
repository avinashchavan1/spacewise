import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 520), spacing: 14)]
    private let tileColumns = [GridItem(.adaptive(minimum: 190, maximum: 320), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if model.isStale {
                    StaleBanner()
                }
                if let result = model.result {
                    ResultSummary(result: result)
                }

                section("Disks") {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(model.volumes) { volume in
                            VolumeCard(volume: volume)
                        }
                    }
                }

                section("Folders") {
                    LazyVGrid(columns: tileColumns, alignment: .leading, spacing: 14) {
                        ForEach(QuickLocation.all) { location in
                            QuickLocationButton(location: location)
                        }
                        Button {
                            model.chooseFolderAndScan()
                        } label: {
                            QuickLocationLabel(title: "Choose Folder…", detail: "Any folder or disk", symbol: "folder.badge.plus")
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !model.recents.isEmpty {
                    section("Recent") {
                        VStack(spacing: 0) {
                            ForEach(model.recents) { recent in
                                Button {
                                    model.scan(recent)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .foregroundStyle(.secondary)
                                        Text(recent.name)
                                        Text(abbreviatePath(recent.path))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 7)
                                    .padding(.horizontal, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if recent.id != model.recents.last?.id {
                                    Divider().padding(.leading, 36)
                                }
                            }
                        }
                        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("macOS protects some folders, such as Mail and Messages. To include them in a scan, allow Spacewise under Full Disk Access.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Privacy Settings…") { FileAccess.openFullDiskAccessSettings() }
                            .buttonStyle(.link)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { model.refreshVolumes() }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }
}

// MARK: - Scan summary

private struct ResultSummary: View {
    @Environment(AppModel.self) private var model
    let result: ScanResult

    private let tileColumns = [GridItem(.adaptive(minimum: 190, maximum: 320), spacing: 14)]

    var body: some View {
        let _ = model.revision
        let root = result.root

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.displayName)
                        .font(.largeTitle.weight(.bold))
                    Text("\(abbreviatePath(root.path)) · scanned \(result.finishedAt.formatted(date: .omitted, time: .shortened)) in \(durationText)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Explore") { model.selection = .explore }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }

            LazyVGrid(columns: tileColumns, alignment: .leading, spacing: 14) {
                StatTile(title: "Space used", value: formatBytes(root.size), symbol: "internaldrive")
                StatTile(title: "Files", value: formatCount(Int(root.fileCount)), symbol: "doc.on.doc", tint: .blue)
                Button {
                    model.selection = .cleanup
                } label: {
                    StatTile(title: "Safe to clean up", value: formatBytes(model.safelyReclaimableBytes),
                             symbol: "sparkles", tint: .green)
                }
                .buttonStyle(.plain)
                .help("Open cleanup suggestions")
            }

            if result.unreadableCount > 0 {
                Label("\(formatCount(result.unreadableCount)) folders could not be read and are not counted.",
                      systemImage: "eye.slash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 14) {
                GroupBox("Largest Folders") {
                    VStack(spacing: 2) {
                        ForEach(Array(root.children.prefix(6))) { child in
                            Button {
                                model.open(child)
                            } label: {
                                HStack(spacing: 8) {
                                    FileIconView(node: child, size: 18)
                                    Text(child.displayName)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 8)
                                    SizeBar(fraction: root.size > 0 ? Double(child.size) / Double(root.size) : 0)
                                        .frame(width: 90)
                                    Text(formatBytes(child.size))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                        .frame(width: 78, alignment: .trailing)
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                }

                GroupBox("By Type") {
                    VStack(alignment: .leading, spacing: 10) {
                        CategoryStrip(totals: result.analysis.categoryTotals)
                            .frame(height: 14)
                        ForEach(topCategories, id: \.category) { entry in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(entry.category.color)
                                    .frame(width: 9, height: 9)
                                Text(entry.category.title)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(formatBytes(entry.bytes))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("See All Types") { model.selection = .fileTypes }
                            .buttonStyle(.link)
                    }
                    .padding(6)
                }
            }
        }
    }

    private var durationText: String {
        result.duration < 1 ? "under a second" : String(format: "%.1f seconds", result.duration)
    }

    private var topCategories: [(category: FileCategory, bytes: Int64)] {
        result.analysis.categoryTotals
            .map { (category: $0.key, bytes: $0.value.bytes) }
            .filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
            .prefix(5)
            .map { $0 }
    }
}

/// One horizontal bar split by file type.
struct CategoryStrip: View {
    let totals: [FileCategory: CategoryTotal]

    var body: some View {
        let entries = FileCategory.allCases
            .map { (category: $0, bytes: totals[$0]?.bytes ?? 0) }
            .filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
        let total = max(1, entries.reduce(Int64(0)) { $0 + $1.bytes })

        GeometryReader { geometry in
            HStack(spacing: 1.5) {
                ForEach(entries, id: \.category) { entry in
                    Rectangle()
                        .fill(entry.category.color)
                        .frame(width: max(1, (geometry.size.width - CGFloat(entries.count) * 1.5) * CGFloat(entry.bytes) / CGFloat(total)))
                        .help("\(entry.category.title): \(formatBytes(entry.bytes))")
                }
            }
        }
        .clipShape(Capsule())
        .accessibilityLabel("Space used by file type")
    }
}

// MARK: - Disks and folders

private struct VolumeCard: View {
    @Environment(AppModel.self) private var model
    let volume: VolumeInfo

    var body: some View {
        GroupBox {
            HStack(spacing: 14) {
                Image(systemName: volume.symbol)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(volume.name)
                            .font(.headline)
                            .lineLimit(1)
                        if !volume.format.isEmpty {
                            Text(volume.format)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    ProgressView(value: volume.usedFraction)
                        .tint(volume.usedFraction > 0.9 ? .red : .accentColor)
                    Text("\(formatBytes(volume.available)) available of \(formatBytes(volume.total))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Button("Scan") { model.requestScan(of: volume.url) }
            }
            .padding(8)
        }
    }
}

private struct QuickLocation: Identifiable {
    let title: String
    let symbol: String
    let path: String

    var id: String { path }

    static var all: [QuickLocation] {
        let home = FileAccess.realHomePath
        return [
            QuickLocation(title: "Home", symbol: "house", path: home),
            QuickLocation(title: "Downloads", symbol: "arrow.down.circle", path: home + "/Downloads"),
            QuickLocation(title: "Documents", symbol: "doc", path: home + "/Documents"),
            QuickLocation(title: "Desktop", symbol: "menubar.dock.rectangle", path: home + "/Desktop"),
            QuickLocation(title: "Applications", symbol: "square.grid.2x2", path: "/Applications"),
        ]
    }
}

private struct QuickLocationButton: View {
    @Environment(AppModel.self) private var model
    let location: QuickLocation

    var body: some View {
        Button {
            model.requestScan(of: URL(fileURLWithPath: location.path, isDirectory: true))
        } label: {
            QuickLocationLabel(title: location.title, detail: abbreviatePath(location.path), symbol: location.symbol)
        }
        .buttonStyle(.plain)
    }
}

private struct QuickLocationLabel: View {
    let title: String
    let detail: String
    let symbol: String
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovered = $0 }
    }
}
