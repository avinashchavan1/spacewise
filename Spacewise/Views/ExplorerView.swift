import SwiftUI

/// Treemap on the left, the current folder's contents on the right.
struct ExplorerView: View {
    @Environment(AppModel.self) private var model
    @State private var highlighted: FSNode?
    @State private var selection = Set<ObjectIdentifier>()

    private static let rowLimit = 1000

    var body: some View {
        let _ = model.revision

        if let focus = model.focus {
            let children = Array(focus.children.prefix(ExplorerView.rowLimit))

            VStack(spacing: 0) {
                if model.isStale {
                    StaleBanner()
                        .padding([.horizontal, .top], 12)
                }
                BreadcrumbBar(focus: focus)
                Divider()
                HSplitView {
                    VStack(spacing: 0) {
                        TreemapView(root: focus, revision: model.revision, highlighted: $highlighted,
                                    onOpen: { model.open($0) },
                                    menu: { NodeMenuItems(model: model, nodes: [$0]) })
                            .padding(10)
                        Divider()
                        HighlightFooter(node: highlighted?.isInTree == true ? highlighted : nil)
                    }
                    .frame(minWidth: 380)

                    contentsList(focus: focus, children: children)
                        .frame(minWidth: 300, idealWidth: 380, maxWidth: 560)
                }
            }
            .onChange(of: ObjectIdentifier(focus)) {
                highlighted = nil
                selection = []
            }
        } else {
            NoScanView(item: .explore)
        }
    }

    private func contentsList(focus: FSNode, children: [FSNode]) -> some View {
        List(selection: $selection) {
            ForEach(children) { node in
                ExplorerRow(node: node, parentSize: focus.size)
            }
            if focus.children.count > children.count {
                Text("\(formatCount(focus.children.count - children.count)) smaller items are not shown.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: ObjectIdentifier.self) { ids in
            NodeMenuItems(model: model, nodes: children.filter { ids.contains(ObjectIdentifier($0)) })
        } primaryAction: { ids in
            if let node = children.first(where: { ids.contains(ObjectIdentifier($0)) }) {
                if node.isDirectory && !node.children.isEmpty {
                    model.open(node)
                } else {
                    model.quickLook(node)
                }
            }
        }
        .onChange(of: selection) { _, newValue in
            if newValue.count == 1, let node = children.first(where: { newValue.contains(ObjectIdentifier($0)) }) {
                highlighted = node
            }
        }
        .overlay {
            if children.isEmpty {
                ContentUnavailableView("Empty Folder", systemImage: "folder")
            }
        }
    }
}

private struct ExplorerRow: View {
    @Environment(AppModel.self) private var model
    let node: FSNode
    let parentSize: Int64

    var body: some View {
        HStack(spacing: 8) {
            CollectToggle(model: model, node: node)
            FileIconView(node: node, size: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            SizeBar(fraction: parentSize > 0 ? Double(node.size) / Double(parentSize) : 0,
                    color: node.category?.color ?? .accentColor)
                .frame(width: 60)
            Text(formatBytes(node.size))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        if node.flags.contains(.unreadable) { return "No permission to read" }
        if node.flags.contains(.skipped) { return "Not scanned" }
        return node.contentsDescription
    }
}

/// Path from the scanned folder down to the one being shown.
private struct BreadcrumbBar: View {
    @Environment(AppModel.self) private var model
    let focus: FSNode

    var body: some View {
        let chain = focus.ancestorsFromRoot

        HStack(spacing: 6) {
            Button {
                model.goUp()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(focus.parent == nil)
            .help("Go to the enclosing folder")
            .keyboardShortcut(.upArrow, modifiers: .command)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(chain) { node in
                        if node !== chain.first {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Button {
                            model.focus = node
                        } label: {
                            HStack(spacing: 4) {
                                FileIconView(node: node, size: 14)
                                Text(node.displayName)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(node === focus ? .primary : .secondary)
                    }
                }
            }
            .defaultScrollAnchor(.trailing)

            Spacer(minLength: 8)
            Text("\(formatBytes(focus.size)) · \(formatFiles(Int(focus.fileCount)))")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

/// Details of the block under the pointer.
private struct HighlightFooter: View {
    @Environment(AppModel.self) private var model
    let node: FSNode?

    var body: some View {
        HStack(spacing: 8) {
            if let node {
                FileIconView(node: node, size: 18)
                Text(abbreviatePath(node.path))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(formatBytes(node.size))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button("Show in Finder") { model.reveal([node]) }
                    .controlSize(.small)
                CollectToggle(model: model, node: node)
            } else {
                Text("Point at a block to see what it is. Double-click a folder to open it.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 34)
    }
}
