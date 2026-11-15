import SwiftUI

/// One line of a file table. Values are copied out of the node once so
/// sorting and filtering never walk the tree.
struct FileRow: Identifiable {
    let node: FSNode
    let name: String
    let size: Int64
    let modified: Date
    let location: String
    let kind: String
    let category: FileCategory

    var id: ObjectIdentifier { ObjectIdentifier(node) }

    init(_ node: FSNode) {
        self.node = node
        name = node.displayName
        size = node.size
        modified = node.modifiedDate
        location = node.locationDescription
        kind = node.kindDescription
        category = node.category ?? .other
    }
}

struct LargeFilesView: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [FileRow] = []
    @State private var selection = Set<FileRow.ID>()
    @State private var sortOrder = [KeyPathComparator(\FileRow.size, order: .reverse)]
    @State private var searchText = ""
    @State private var categoryFilter: FileCategory?
    @State private var minimumMB = 0

    private struct RowsKey: Hashable {
        let revision: Int
        let search: String
        let category: FileCategory?
        let minimumMB: Int
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Picker("Type", selection: $categoryFilter) {
                    Text("All Types").tag(FileCategory?.none)
                    Divider()
                    ForEach(FileCategory.allCases, id: \.self) { category in
                        Text(category.title).tag(FileCategory?.some(category))
                    }
                }
                .frame(maxWidth: 240)

                Picker("Larger than", selection: $minimumMB) {
                    Text("Any Size").tag(0)
                    Text("10 MB").tag(10)
                    Text("100 MB").tag(100)
                    Text("1 GB").tag(1000)
                }
                .frame(maxWidth: 220)

                Spacer()
                Text("\(formatItems(rows.count)) · \(formatBytes(rows.reduce(0) { $0 + $1.size }))")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            FileTable(rows: $rows, selection: $selection, sortOrder: $sortOrder)
                .overlay {
                    if rows.isEmpty {
                        if searchText.isEmpty {
                            ContentUnavailableView("No Files", systemImage: "doc",
                                                   description: Text("No files match these filters."))
                        } else {
                            ContentUnavailableView.search(text: searchText)
                        }
                    }
                }
        }
        .searchable(text: $searchText, prompt: "Search large files")
        .task(id: RowsKey(revision: model.revision, search: searchText, category: categoryFilter, minimumMB: minimumMB)) {
            rebuildRows()
        }
    }

    private func rebuildRows() {
        let nodes = model.result?.analysis.largestFiles ?? []
        let minimum = Int64(minimumMB) * 1_000_000
        let query = searchText.trimmingCharacters(in: .whitespaces)
        var built: [FileRow] = []
        built.reserveCapacity(nodes.count)
        for node in nodes {
            if node.size < minimum { break }   // the list is sorted largest first
            let row = FileRow(node)
            if let categoryFilter, row.category != categoryFilter { continue }
            if !query.isEmpty,
               !row.name.localizedCaseInsensitiveContains(query),
               !row.location.localizedCaseInsensitiveContains(query) { continue }
            built.append(row)
        }
        built.sort(using: sortOrder)
        rows = built
        let valid = Set(built.map(\.id))
        selection = selection.intersection(valid)
    }
}

/// Sortable table of files with a checkbox column for the cleanup list.
struct FileTable: View {
    @Environment(AppModel.self) private var model
    @Binding var rows: [FileRow]
    @Binding var selection: Set<FileRow.ID>
    @Binding var sortOrder: [KeyPathComparator<FileRow>]

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { row in
                HStack(spacing: 6) {
                    CollectToggle(model: model, node: row.node)
                    FileNameCell(node: row.node)
                }
            }
            .width(min: 180, ideal: 300)

            TableColumn("Size", value: \.size) { row in
                Text(formatBytes(row.size))
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 90, max: 120)

            TableColumn("Kind", value: \.kind) { row in
                Text(row.kind)
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 90, max: 130)

            TableColumn("Modified", value: \.modified) { row in
                Text(row.modified.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110, max: 150)

            TableColumn("Location", value: \.location) { row in
                Text(row.location)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(row.location)
            }
            .width(min: 120, ideal: 260)
        }
        .contextMenu(forSelectionType: FileRow.ID.self) { ids in
            NodeMenuItems(model: model, nodes: nodes(for: ids))
        } primaryAction: { ids in
            if let node = nodes(for: ids).first {
                model.quickLook(node)
            }
        }
        .onChange(of: sortOrder) { _, newOrder in
            rows.sort(using: newOrder)
        }
    }

    private func nodes(for ids: Set<FileRow.ID>) -> [FSNode] {
        rows.filter { ids.contains($0.id) }.map(\.node)
    }
}
