import SwiftUI

/// Sorts the loose files of one folder into subfolders, with a preview and undo.
struct OrganizeView: View {
    @Environment(AppModel.self) private var model
    @State private var folder: URL?
    @State private var strategy: Organizer.Strategy = .byType
    @State private var plan: [Organizer.Move] = []
    @State private var lastRecord: FolderOrganizer.Record?
    @State private var lastFolder: URL?
    @State private var isWorking = false
    @State private var loadError: String?

    private struct PlanKey: Hashable {
        let folder: URL?
        let strategy: Organizer.Strategy
    }

    private struct Destination: Identifiable {
        let name: String
        let moves: [Organizer.Move]
        var id: String { name }
        var size: Int64 { moves.reduce(0) { $0 + $1.size } }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Folder")
                        .frame(width: 96, alignment: .trailing)
                    if let folder {
                        Image(nsImage: FileIcons.icon(forPath: folder.path))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(abbreviatePath(folder.path))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("None selected")
                            .foregroundStyle(.secondary)
                    }
                    Button("Choose…") { chooseFolder() }
                    Spacer()
                }
                HStack(spacing: 8) {
                    Text("Sort files by")
                        .frame(width: 96, alignment: .trailing)
                    Picker("Sort files by", selection: $strategy) {
                        ForEach(Organizer.Strategy.allCases) { strategy in
                            Text(strategy.title).tag(strategy)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    Spacer()
                }
                Text(strategy.explanation + " Only loose files move; existing folders and hidden files stay where they are.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 104)
            }
            .padding(16)

            Divider()

            preview

            Divider()

            HStack(spacing: 12) {
                if let lastRecord, let lastFolder {
                    Text("Moved \(formatFiles(lastRecord.moves.count)) in \(lastFolder.lastPathComponent).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Undo") { undo() }
                        .disabled(isWorking)
                }
                Spacer()
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(plan.isEmpty ? "Organize" : "Organize \(formatFiles(plan.count))") { apply() }
                    .buttonStyle(.borderedProminent)
                    .disabled(folder == nil || plan.isEmpty || isWorking)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        #if DEBUG
        .onAppear {
            if folder == nil, let demo = UserDefaults.standard.string(forKey: DemoLaunch.organizeKey) {
                folder = URL(fileURLWithPath: demo, isDirectory: true)
            }
        }
        #endif
        .task(id: PlanKey(folder: folder, strategy: strategy)) {
            reloadPlan()
        }
    }

    @ViewBuilder
    private var preview: some View {
        if folder == nil {
            ContentUnavailableView {
                Label("Choose a Folder to Tidy", systemImage: "folder.badge.gearshape")
            } description: {
                Text("Downloads and Desktop are good places to start. You see every move before anything changes.")
            } actions: {
                Button("Choose Folder…") { chooseFolder() }
            }
            .frame(maxHeight: .infinity)
        } else if let loadError {
            ContentUnavailableView("Can’t Organize This Folder", systemImage: "exclamationmark.triangle",
                                   description: Text(loadError))
                .frame(maxHeight: .infinity)
        } else if plan.isEmpty {
            ContentUnavailableView("Already Tidy", systemImage: "checkmark.circle",
                                   description: Text("There are no loose files to move in this folder."))
                .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(destinations) { destination in
                    Section {
                        ForEach(destination.moves) { move in
                            HStack(spacing: 8) {
                                Image(systemName: "doc")
                                    .foregroundStyle(.secondary)
                                Text(move.name)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(formatBytes(move.size))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        HStack {
                            Label(destination.name, systemImage: "folder")
                                .font(.callout.weight(.medium))
                            Spacer()
                            Text("\(formatFiles(destination.moves.count)) · \(formatBytes(destination.size))")
                                .font(.callout)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var destinations: [Destination] {
        Dictionary(grouping: plan, by: \.folder)
            .map { Destination(name: $0.key, moves: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func chooseFolder() {
        let start = folder ?? URL(fileURLWithPath: FileAccess.realHomePath + "/Downloads", isDirectory: true)
        if let chosen = FileAccess.chooseFolder(startingAt: start,
                                                message: "Choose the folder whose files you want to sort into subfolders.",
                                                prompt: "Choose") {
            folder = chosen
        }
    }

    private func reloadPlan() {
        loadError = nil
        guard let folder else {
            plan = []
            return
        }
        guard ProtectedLocations.canOrganize(folder.path, homePath: FileAccess.realHomePath) else {
            plan = []
            loadError = "Spacewise doesn’t sort “\(abbreviatePath(folder.path))” because macOS or your apps rely on how its files are laid out. Choose Desktop, Downloads, Documents or another folder of your own."
            return
        }
        do {
            let entries = try FolderOrganizer.entries(in: folder)
            plan = Organizer.plan(entries: entries, strategy: strategy, calendar: .current)
        } catch {
            plan = []
            loadError = error.localizedDescription
        }
    }

    private func apply() {
        guard let folder, !plan.isEmpty,
              ProtectedLocations.canOrganize(folder.path, homePath: FileAccess.realHomePath) else { return }
        let moves = plan
        isWorking = true
        Task {
            let record = await Task.detached(priority: .userInitiated) {
                FolderOrganizer.apply(moves, in: folder)
            }.value
            isWorking = false
            lastRecord = record.moves.isEmpty ? nil : record
            lastFolder = folder
            finish(errors: record.errors, title: "Some Files Couldn’t Be Moved", folder: folder)
        }
    }

    private func undo() {
        guard let record = lastRecord, let undoFolder = lastFolder else { return }
        isWorking = true
        Task {
            let errors = await Task.detached(priority: .userInitiated) {
                FolderOrganizer.undo(record)
            }.value
            isWorking = false
            lastRecord = nil
            finish(errors: errors, title: "Some Files Couldn’t Be Moved Back", folder: undoFolder)
        }
    }

    private func finish(errors: [String], title: String, folder: URL) {
        reloadPlan()
        if let root = model.result?.root {
            let rootPath = root.path
            if folder.path == rootPath || folder.path.hasPrefix(rootPath == "/" ? "/" : rootPath + "/") {
                model.markStale()
            }
        }
        if !errors.isEmpty {
            let more = errors.count > 6 ? "\n…and \(errors.count - 6) more." : ""
            model.alert = AlertInfo(title: title, message: errors.prefix(6).joined(separator: "\n") + more)
        }
    }
}
