import SwiftUI

/// Bottom bar summarizing the cleanup list, visible on every screen.
struct CollectorBar: View {
    @Environment(AppModel.self) private var model
    @State private var showsReview = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(formatItems(model.collected.count)) on the cleanup list")
                        .font(.callout.weight(.medium))
                    Text("Frees \(formatBytes(model.collectedSize))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                if model.isDeleting {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Clear") { model.clearCollection() }
                Button("Review…") { showsReview = true }
                Button("Move to Trash…") { model.requestTrash(model.collected) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isDeleting)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
        .sheet(isPresented: $showsReview) {
            CollectionReviewSheet()
                .environment(model)
        }
    }
}

struct CollectionReviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cleanup List")
                        .font(.headline)
                    Text("\(formatItems(model.collected.count)) · \(formatBytes(model.collectedSize))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)

            Divider()

            List {
                ForEach(model.collected) { node in
                    HStack(spacing: 10) {
                        FileNameCell(node: node, showsLocation: true)
                        Spacer()
                        Text(formatBytes(node.size))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button {
                            model.uncollect([node])
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Keep this item")
                    }
                    .contextMenu {
                        Button("Show in Finder") { model.reveal([node]) }
                        Button("Keep This Item") { model.uncollect([node]) }
                    }
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Button("Clear List") {
                    model.clearCollection()
                    dismiss()
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash…") {
                    dismiss()
                    // Let the sheet close before the confirmation appears on the window.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        model.requestTrash(model.collected)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.collected.isEmpty || model.isDeleting)
            }
            .padding(16)
        }
        .frame(width: 620, height: 460)
    }
}
