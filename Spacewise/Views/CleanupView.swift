import SwiftUI

struct CleanupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.revision
        let suggestions = model.result?.suggestions ?? []

        if suggestions.isEmpty {
            ContentUnavailableView("Nothing to Clean Up", systemImage: "sparkles",
                                   description: Text("No caches, build folders or old downloads were found in this scan. Scanning your Home folder finds the most."))
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(formatBytes(suggestions.reduce(Int64(0)) { $0 + $1.totalSize })) could be freed")
                            .font(.headline)
                        Text("Items marked Safe are recreated automatically. Look through the ones marked Review first.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Select All Safe Items") {
                        model.collect(suggestions.filter { $0.safety == .safe }.flatMap(\.items))
                    }
                    .disabled(!suggestions.contains { $0.safety == .safe })
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)

                Divider()

                List {
                    ForEach(suggestions) { suggestion in
                        SuggestionSection(suggestion: suggestion)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct SuggestionSection: View {
    @Environment(AppModel.self) private var model
    let suggestion: CleanupSuggestion
    @State private var isExpanded = false

    private static let itemLimit = 200

    var body: some View {
        let items = suggestion.items
        let allSelected = !items.isEmpty && items.allSatisfy { model.isCoveredByCollection($0) }

        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(Array(items.prefix(SuggestionSection.itemLimit))) { node in
                HStack(spacing: 8) {
                    CollectToggle(model: model, node: node)
                    FileNameCell(node: node, showsLocation: true)
                    Spacer(minLength: 8)
                    Text(formatBytes(node.size))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 1)
                .contextMenu {
                    NodeMenuItems(model: model, nodes: [node])
                }
            }
            if items.count > SuggestionSection.itemLimit {
                Text("\(formatCount(items.count - SuggestionSection.itemLimit)) more items are included when you select the whole group.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } label: {
            HStack(spacing: 10) {
                Toggle("Select all of \(suggestion.title)", isOn: Binding(
                    get: { allSelected },
                    set: { isOn in
                        if isOn {
                            model.collect(items)
                        } else {
                            model.uncollect(items)
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()

                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(suggestion.title)
                            .font(.body.weight(.medium))
                        Badge(text: suggestion.safety == .safe ? "Safe" : "Review",
                              color: suggestion.safety == .safe ? .green : .orange)
                    }
                    Text(suggestion.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatBytes(suggestion.totalSize))
                        .font(.body.weight(.medium))
                        .monospacedDigit()
                    Text(formatItems(items.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var symbol: String {
        switch suggestion.kind {
        case .trash: return "trash"
        case .userCaches: return "internaldrive"
        case .logs: return "doc.plaintext"
        case .xcodeDerivedData, .xcodeDeviceSupport, .xcodeArchives: return "hammer"
        case .simulators: return "iphone"
        case .packageCaches: return "shippingbox"
        case .dependencyFolders: return "folder.badge.gearshape"
        case .installers: return "opticaldiscdrive"
        case .oldDownloads: return "arrow.down.circle"
        case .iosBackups: return "iphone.and.arrow.forward"
        }
    }
}
