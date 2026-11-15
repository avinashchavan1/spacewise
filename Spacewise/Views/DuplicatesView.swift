import SwiftUI

struct DuplicatesView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.duplicateMinimumMB) private var minimumMB = 1

    private static let groupLimit = 400

    var body: some View {
        switch model.duplicateState {
        case .idle:
            ContentUnavailableView {
                Label("Find Duplicate Files", systemImage: "doc.on.doc")
            } description: {
                Text("Spacewise compares the contents of files with the same size, so only exact copies are reported. Files inside apps and libraries are skipped.")
            } actions: {
                Picker("Smallest file to check", selection: $minimumMB) {
                    Text("100 KB").tag(0)
                    Text("1 MB").tag(1)
                    Text("10 MB").tag(10)
                    Text("100 MB").tag(100)
                }
                .frame(width: 280)
                Button("Find Duplicates") { model.findDuplicates(minimumSize: minimumBytes) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }

        case .running:
            VStack(spacing: 14) {
                ProgressView(value: model.duplicateProgress.fraction)
                    .frame(width: 340)
                Text("Comparing \(formatFiles(model.duplicateProgress.filesTotal))…")
                    .font(.title3.weight(.medium))
                Text("\(formatBytes(model.duplicateProgress.bytesDone)) read")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button("Stop") { model.cancelDuplicateSearch() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(40)

        case .finished:
            if model.duplicateGroups.isEmpty {
                ContentUnavailableView {
                    Label("No Duplicates", systemImage: "checkmark.circle")
                } description: {
                    Text("No identical files of \(formatBytes(minimumBytes)) or more were found.")
                } actions: {
                    Button("Search Again") { model.duplicateState = .idle }
                }
            } else {
                results
            }
        }
    }

    private var minimumBytes: Int64 {
        minimumMB == 0 ? 100_000 : Int64(minimumMB) * 1_000_000
    }

    private var results: some View {
        let groups = model.duplicateGroups
        let reclaimable = groups.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
        let shown = Array(groups.prefix(DuplicatesView.groupLimit).enumerated())

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(formatCount(groups.count)) sets of identical files")
                        .font(.headline)
                    Text("Keeping one copy of each frees \(formatBytes(reclaimable)).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Search Again") { model.duplicateState = .idle }
                Button("Select All Extra Copies") { model.collectExtraDuplicates() }
                    .help("Adds every copy except the first of each set to the cleanup list")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider()

            List {
                ForEach(shown, id: \.offset) { entry in
                    Section {
                        ForEach(entry.element.files) { node in
                            DuplicateRow(node: node)
                        }
                    } header: {
                        DuplicateHeader(group: entry.element)
                    }
                }
                if groups.count > shown.count {
                    Text("\(formatCount(groups.count - shown.count)) smaller sets are not shown.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct DuplicateHeader: View {
    @Environment(AppModel.self) private var model
    let group: DuplicateGroup

    var body: some View {
        let allSelected = group.files.allSatisfy { model.isCoveredByCollection($0) }

        HStack(spacing: 8) {
            Text("\(group.files.count) copies · \(formatBytes(group.fileSize)) each")
                .font(.callout.weight(.medium))
            if allSelected {
                Label("Every copy is selected", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            Text("Frees \(formatBytes(group.reclaimableBytes))")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

private struct DuplicateRow: View {
    @Environment(AppModel.self) private var model
    let node: FSNode

    var body: some View {
        HStack(spacing: 8) {
            CollectToggle(model: model, node: node)
            FileNameCell(node: node, showsLocation: true)
            Spacer(minLength: 8)
            Text(node.modifiedDate.formatted(date: .abbreviated, time: .omitted))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
        .contextMenu {
            NodeMenuItems(model: model, nodes: [node])
        }
    }
}
