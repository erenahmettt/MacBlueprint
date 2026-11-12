import BlueprintCore
import SwiftData
import SwiftUI

/// What the old Mac (a snapshot) has that this Mac doesn't.
struct CompareView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \SnapshotRecord.savedAt, order: .reverse) private var records: [SnapshotRecord]

    var body: some View {
        Group {
            if model.thisMac == nil {
                ProgressView("Scanning this Mac…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let base = model.base, let diff = model.diff {
                DiffList(baseName: base.name, diff: diff)
            } else {
                emptyState
            }
        }
        .navigationTitle("Compare")
        .toolbar {
            ToolbarItemGroup {
                if model.base != nil {
                    snapshotMenu
                    Button {
                        model.sidebar = .restore
                    } label: {
                        Label("Review Restore Plan", systemImage: "arrow.right.circle")
                    }
                    .disabled(model.diff?.isEmpty ?? true)
                }
            }
        }
    }

    private var snapshotMenu: some View {
        Menu {
            Button("Open Snapshot…") { model.isImporting = true }
            if !records.isEmpty {
                Divider()
                ForEach(records) { record in
                    Button(record.title) { model.compare(with: record) }
                }
            }
        } label: {
            Label("Change Snapshot", systemImage: "doc.text")
        }
        .help("Compare with a different snapshot")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Compare with your old Mac", systemImage: "arrow.left.arrow.right")
        } description: {
            Text("Open a snapshot of your old Mac to see what this one is missing. Make one there with MacBlueprint or by running `macblueprint scan`.")
        } actions: {
            Button("Open Snapshot…") { model.isImporting = true }
                .buttonStyle(.borderedProminent)
            if let latest = records.first {
                Button("Use “\(latest.title)”") { model.compare(with: latest) }
            }
        }
    }
}

private struct DiffList: View {
    let baseName: String
    let diff: SnapshotDiff

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: diff.isEmpty ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(diff.isEmpty ? .green : .accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(diff.isEmpty ? "This Mac has everything" : "\(diff.missingCount) things from “\(baseName)” aren't on this Mac")
                            .font(.headline)
                        Text(diff.isEmpty ? "Nothing from “\(baseName)” is missing." : "Review them in the restore plan and pick what to install.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                if let change = diff.architectureChange {
                    Label("The old Mac was \(change.from == "arm64" ? "Apple silicon" : "Intel"); this one is \(change.to == "arm64" ? "Apple silicon" : "Intel").", systemImage: "cpu")
                        .foregroundStyle(.orange)
                }
            }

            section("Apps", systemImage: "square.grid.2x2", diff.missingApps.map { app in
                Row(title: app.name, detail: description(of: app), icon: app.path)
            })
            section("Homebrew", systemImage: "mug",
                    diff.missingTaps.map { Row(title: $0, detail: "tap") }
                    + diff.missingFormulae.map { Row(title: $0.name, detail: "formula") }
                    + diff.missingCasks.map { Row(title: $0.token, detail: "cask") })
            ForEach(diff.missingExtensions, id: \.editor) { editor in
                section("\(editor.editor.displayName) Extensions", systemImage: "puzzlepiece.extension",
                        editor.extensions.map { Row(title: $0.id, detail: $0.version) })
            }
            section("Developer Setup", systemImage: "hammer",
                    diff.missingVersionManagers.map { Row(title: $0.name, detail: $0.installedVersions.joined(separator: ", ")) }
                    + diff.missingDevTools.map { Row(title: $0.name, detail: [$0.version, $0.manager.map { "via \($0)" }].compactMap { $0 }.joined(separator: " ")) }
                    + diff.missingShellFrameworks.map { Row(title: $0, detail: "shell framework") }
                    + (diff.missingPrompt.map { [Row(title: $0, detail: "prompt")] } ?? [])
                    + (diff.missingDeveloperTools ? [Row(title: "Xcode Command Line Tools", detail: nil)] : []))

            if !diff.versionChanges.isEmpty {
                Section("Different Versions (\(diff.versionChanges.count))") {
                    ForEach(diff.versionChanges, id: \.name) { change in
                        LabeledContent(change.name, value: "\(change.from) → \(change.to)")
                    }
                }
            }
            if !diff.extraApps.isEmpty {
                Section("Only on This Mac (\(diff.extraApps.count))") {
                    Text(diff.extraApps.map(\.name).joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    struct Row: Identifiable {
        var title: String
        var detail: String?
        var icon: String?
        var id: String { title + (detail ?? "") }
    }

    @ViewBuilder
    private func section(_ title: String, systemImage: String, _ rows: [Row]) -> some View {
        if !rows.isEmpty {
            Section {
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        if let icon = row.icon { AppIcon(path: icon) }
                        Text(row.title)
                        Spacer()
                        if let detail = row.detail {
                            Text(detail).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Label("\(title) (\(rows.count))", systemImage: systemImage)
            }
        }
    }

    private func description(of app: AppItem) -> String {
        switch app.source {
        case .appStore: "App Store"
        case .homebrew: "Homebrew cask"
        case .manual: "Installed by hand"
        case .system: "Built-in"
        }
    }
}
