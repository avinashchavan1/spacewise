import Charts
import SwiftUI

struct FileTypesView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: FileCategory?
    @State private var rows: [FileRow] = []
    @State private var selection = Set<FileRow.ID>()
    @State private var sortOrder = [KeyPathComparator(\FileRow.size, order: .reverse)]

    private struct Slice: Identifiable {
        let category: FileCategory
        let bytes: Int64
        let files: Int
        var id: Int { category.rawValue }
    }

    private struct RowsKey: Hashable {
        let revision: Int
        let category: FileCategory?
    }

    var body: some View {
        let slices = makeSlices()
        let total = max(1, slices.reduce(Int64(0)) { $0 + $1.bytes })
        let current = selected ?? slices.first?.category

        HSplitView {
            VStack(spacing: 16) {
                ZStack {
                    Chart(slices) { slice in
                        SectorMark(angle: .value("Size", Double(slice.bytes)),
                                   innerRadius: .ratio(0.64),
                                   angularInset: 1.5)
                            .cornerRadius(4)
                            .foregroundStyle(slice.category.color)
                            .opacity(current == nil || current == slice.category ? 1 : 0.35)
                    }
                    .chartLegend(.hidden)

                    VStack(spacing: 2) {
                        Text(formatBytes(slices.first { $0.category == current }?.bytes ?? total))
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                        Text(current?.title ?? "Total")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: 120)
                }
                .frame(height: 230)
                .padding(.top, 16)
                .padding(.horizontal, 16)

                List(selection: Binding(get: { current }, set: { selected = $0 })) {
                    ForEach(slices) { slice in
                        HStack(spacing: 8) {
                            Image(systemName: slice.category.symbol)
                                .foregroundStyle(slice.category.color)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(slice.category.title)
                                Text(formatFiles(slice.files))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(formatBytes(slice.bytes))
                                    .monospacedDigit()
                                Text((Double(slice.bytes) / Double(total)).formatted(.percent.precision(.fractionLength(0))))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .tag(slice.category)
                    }
                }
                .listStyle(.inset)
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)

            VStack(spacing: 0) {
                HStack {
                    Text(current.map { "Largest in \($0.title)" } ?? "Largest Files")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                Divider()
                FileTable(rows: $rows, selection: $selection, sortOrder: $sortOrder)
            }
            .frame(minWidth: 400)
        }
        .task(id: RowsKey(revision: model.revision, category: current)) {
            reloadRows(for: current)
        }
    }

    private func reloadRows(for category: FileCategory?) {
        let nodes = category.flatMap { model.result?.analysis.largestByCategory[$0] } ?? []
        var built = nodes.map { FileRow($0) }
        built.sort(using: sortOrder)
        rows = built
        selection = []
    }

    private func makeSlices() -> [Slice] {
        let _ = model.revision
        let totals = model.result?.analysis.categoryTotals ?? [:]
        return totals
            .map { Slice(category: $0.key, bytes: $0.value.bytes, files: $0.value.files) }
            .filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
    }
}
