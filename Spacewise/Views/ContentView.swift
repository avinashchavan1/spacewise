import QuickLook
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 300)
        } detail: {
            DetailView()
        }
        .quickLookPreview($model.quickLookURL)
        .alert(model.alert?.title ?? "",
               isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
               presenting: model.alert) { _ in
            Button("OK") {}
        } message: { info in
            Text(info.message)
        }
        .confirmationDialog(trashTitle,
                            isPresented: Binding(get: { !model.pendingTrash.isEmpty },
                                                 set: { if !$0 { model.pendingTrash = [] } }),
                            titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                let nodes = model.pendingTrash
                model.pendingTrash = []
                model.moveToTrash(nodes)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This frees \(formatBytes(model.pendingTrash.reduce(0) { $0 + $1.size })). You can put items back from the Trash until you empty it.")
        }
    }

    private var trashTitle: String {
        let count = model.pendingTrash.count
        if count == 1, let node = model.pendingTrash.first {
            return "Move “\(node.displayName)” to the Trash?"
        }
        return "Move \(formatCount(count)) items to the Trash?"
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: $model.selection) {
            Section("Analyze") {
                row(.overview)
                row(.explore)
                row(.largeFiles)
                row(.fileTypes)
            }
            Section("Tidy Up") {
                row(.cleanup)
                    .badge(cleanupBadge)
                row(.duplicates)
                row(.organize)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if let disk = model.volumes.first(where: { $0.isStartupDisk }) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(disk.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    ProgressView(value: disk.usedFraction)
                        .tint(disk.usedFraction > 0.9 ? .red : .accentColor)
                    Text("\(formatBytes(disk.available)) available")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.symbol)
            .tag(item)
    }

    private var cleanupBadge: Text? {
        let bytes = (model.result?.suggestions ?? []).reduce(Int64(0)) { $0 + $1.totalSize }
        return bytes > 0 ? Text(formatBytes(bytes)) : nil
    }
}

struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let item = model.selection ?? .overview

        Group {
            if model.phase == .scanning {
                ScanProgressView()
            } else if item.needsScan && model.result == nil {
                NoScanView(item: item)
            } else {
                switch item {
                case .overview: OverviewView()
                case .explore: ExplorerView()
                case .largeFiles: LargeFilesView()
                case .fileTypes: FileTypesView()
                case .duplicates: DuplicatesView()
                case .cleanup: CleanupView()
                case .organize: OrganizeView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !model.collected.isEmpty && model.phase != .scanning {
                CollectorBar()
            }
        }
        .navigationTitle(item.title)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.rescan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .help("Scan the same folder again")
                .disabled(model.result == nil || model.phase == .scanning)

                Button {
                    model.chooseFolderAndScan()
                } label: {
                    Label("Scan Folder", systemImage: "folder.badge.plus")
                }
                .help("Choose a folder or disk to scan")
            }
        }
    }

    private var subtitle: String {
        if model.phase == .scanning { return "Scanning…" }
        guard let result = model.result else { return "" }
        let _ = model.revision
        return "\(result.displayName) — \(formatBytes(result.root.size))"
    }
}
