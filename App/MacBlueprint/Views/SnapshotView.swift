import BlueprintCore
import SwiftData
import SwiftUI

/// The live scan of this Mac, with save and export actions.
struct ThisMacView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @State private var isSaving = false
    @State private var label = ""

    var body: some View {
        Group {
            if let snapshot = model.thisMac {
                SnapshotView(snapshot: snapshot, title: "This Mac")
            } else {
                ProgressView("Scanning this Mac…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("This Mac")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await model.scan() }
                } label: {
                    Label("Scan Again", systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanning)
                .help("Scan this Mac again (⌘R)")

                Button {
                    isSaving = true
                } label: {
                    Label("Save Snapshot", systemImage: "square.and.arrow.down")
                }
                .disabled(model.thisMac == nil)
                .help("Keep this snapshot to compare with later")

                if let snapshot = model.thisMac {
                    ExportMenu(snapshot: snapshot)
                }
            }
        }
        .sheet(isPresented: $isSaving) {
            SaveSnapshotSheet(label: $label) {
                model.saveThisMac(label: label, context: context)
                label = ""
            }
        }
    }
}

/// A snapshot saved earlier (or opened from another Mac).
struct SavedSnapshotView: View {
    @Environment(AppModel.self) private var model
    let record: SnapshotRecord
    @State private var snapshot: Snapshot?
    @State private var error: String?

    var body: some View {
        Group {
            if let snapshot {
                SnapshotView(snapshot: snapshot, title: record.title)
            } else if let error {
                ContentUnavailableView("Couldn't open this snapshot", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(record.title)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.compare(with: record)
                } label: {
                    Label("Compare with This Mac", systemImage: "arrow.left.arrow.right")
                }
                .help("See what this Mac is missing from this snapshot")
                if let snapshot {
                    ExportMenu(snapshot: snapshot)
                }
            }
        }
        .task {
            do { snapshot = try model.library.load(record) } catch { self.error = error.localizedDescription }
        }
    }
}

private struct ExportMenu: View {
    let snapshot: Snapshot

    var body: some View {
        Menu {
            Button("Snapshot (JSON)…") {
                if let url = Panels.save(suggestedName: "\(baseName).json", type: .json) {
                    try? snapshot.jsonData().write(to: url, options: .atomic)
                }
            }
            Button("Report (Markdown)…") {
                if let url = Panels.save(suggestedName: "\(baseName).md", type: .plainText) {
                    try? Data(MarkdownExporter.render(snapshot).utf8).write(to: url, options: .atomic)
                }
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .help("Export this snapshot")
    }

    private var baseName: String {
        let date = snapshot.createdAt.formatted(.iso8601.year().month().day())
        return "macblueprint-\(date)"
    }
}

private struct SaveSnapshotSheet: View {
    @Binding var label: String
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Snapshot")
                .font(.headline)
            Text("Give it a name you'll recognize on your next Mac. It's saved on this Mac only; export it to move it.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("Name", text: $label, prompt: Text("Work MacBook"))
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func save() {
        onSave()
        dismiss()
    }
}

/// Shows any snapshot: summary tiles and one tab per area.
struct SnapshotView: View {
    let snapshot: Snapshot
    let title: String

    enum Tab: String, CaseIterable, Identifiable {
        case apps = "Apps"
        case homebrew = "Homebrew"
        case extensions = "Extensions"
        case developer = "Developer"
        var id: Self { self }
    }

    @State private var tab: Tab = .apps
    @State private var search = ""
    @State private var source: AppItem.Source?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 12)
            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
            .padding(.bottom, 12)
            Divider()
            content
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Filter")
    }

    // MARK: Header

    private var installedApps: [AppItem] { snapshot.apps.filter { $0.source != .system } }
    private var extensionCount: Int { snapshot.editors.reduce(0) { $0 + $1.extensions.count } }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(machineLine)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                StatTile(
                    title: "Apps",
                    value: "\(installedApps.count)",
                    detail: "\(installedApps.filter { $0.source == .appStore }.count) from the App Store, plus \(snapshot.apps.count - installedApps.count) built-in",
                    systemImage: "square.grid.2x2"
                )
                StatTile(
                    title: "Homebrew",
                    value: snapshot.homebrew.installed ? "\(snapshot.homebrew.formulae.filter(\.onRequest).count + snapshot.homebrew.casks.count)" : "—",
                    detail: snapshot.homebrew.installed ? "\(snapshot.homebrew.casks.count) casks" : "Not installed",
                    systemImage: "mug"
                )
                StatTile(
                    title: "Extensions",
                    value: "\(extensionCount)",
                    detail: snapshot.editors.map(\.editor.displayName).joined(separator: ", ").nilIfEmpty ?? "No editors",
                    systemImage: "puzzlepiece.extension"
                )
                StatTile(
                    title: "Dev Tools",
                    value: "\(snapshot.devEnvironment.tools.count)",
                    detail: snapshot.devEnvironment.versionManagers.map(\.name).joined(separator: ", ").nilIfEmpty ?? "No version managers",
                    systemImage: "hammer"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var machineLine: String {
        let machine = snapshot.machine
        let chip = machine.architecture == "arm64" ? "Apple silicon" : "Intel"
        return [machine.model, chip, "macOS \(machine.osVersion)", snapshot.createdAt.formatted(date: .abbreviated, time: .shortened)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .apps: appsTable
        case .homebrew: homebrewList
        case .extensions: extensionsList
        case .developer: developerList
        }
    }

    private var filteredApps: [AppItem] {
        snapshot.apps.filter { app in
            (source == nil || app.source == source)
                && (search.isEmpty || app.name.localizedCaseInsensitiveContains(search) || (app.bundleId ?? "").localizedCaseInsensitiveContains(search))
        }
    }

    private var appsTable: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Source", selection: $source) {
                    Text("All Sources").tag(AppItem.Source?.none)
                    Divider()
                    Text("App Store").tag(AppItem.Source?.some(.appStore))
                    Text("Homebrew").tag(AppItem.Source?.some(.homebrew))
                    Text("Installed by Hand").tag(AppItem.Source?.some(.manual))
                    Text("Built-in").tag(AppItem.Source?.some(.system))
                }
                .fixedSize()
                Spacer()
                Text("\(filteredApps.count) apps")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Table(filteredApps) {
                TableColumn("Name") { app in
                    HStack(spacing: 8) {
                        AppIcon(path: app.path)
                        Text(app.name)
                    }
                }
                TableColumn("Version") { app in
                    Text(app.version ?? "—").foregroundStyle(.secondary)
                }
                .width(min: 70, ideal: 100)
                TableColumn("Source") { app in
                    SourceBadge(source: app.source)
                }
                .width(min: 100, ideal: 130)
                TableColumn("Bundle ID") { app in
                    Text(app.bundleId ?? "—")
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func matches(_ text: String) -> Bool {
        search.isEmpty || text.localizedCaseInsensitiveContains(search)
    }

    @ViewBuilder
    private var homebrewList: some View {
        let brew = snapshot.homebrew
        if !brew.installed {
            ContentUnavailableView(
                "Homebrew isn't installed",
                systemImage: "mug",
                description: Text("Homebrew installs command-line tools and apps. Get it from brew.sh.")
            )
        } else {
            let requested = brew.formulae.filter { $0.onRequest && matches($0.name) }
            List {
                Section("Formulae (\(requested.count))") {
                    ForEach(requested, id: \.name) { formula in
                        LabeledContent(formula.name, value: formula.version ?? "")
                    }
                }
                Section("Casks (\(brew.casks.count))") {
                    ForEach(brew.casks.filter { matches($0.token) }, id: \.token) { cask in
                        LabeledContent(cask.token, value: cask.version ?? "")
                    }
                }
                if !brew.taps.isEmpty {
                    Section("Taps") {
                        ForEach(brew.taps, id: \.self) { Text($0) }
                    }
                }
                let dependencies = brew.formulae.count - brew.formulae.filter(\.onRequest).count
                if dependencies > 0 {
                    Text("Plus \(dependencies) formulae installed as dependencies. They come back on their own.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var extensionsList: some View {
        if snapshot.editors.isEmpty {
            ContentUnavailableView("No editors found", systemImage: "puzzlepiece.extension", description: Text("VS Code, Cursor, VSCodium, Windsurf and Antigravity are supported."))
        } else {
            List {
                ForEach(snapshot.editors, id: \.editor) { editor in
                    Section("\(editor.editor.displayName) (\(editor.extensions.count))") {
                        ForEach(editor.extensions.filter { matches($0.id) }, id: \.id) { ext in
                            LabeledContent(ext.id, value: ext.version ?? "")
                        }
                    }
                }
            }
        }
    }

    private var developerList: some View {
        let env = snapshot.devEnvironment
        return List {
            Section("Tools") {
                ForEach(env.tools.filter { matches($0.name) }, id: \.name) { tool in
                    LabeledContent {
                        Text([tool.version, tool.manager.map { "via \($0)" }].compactMap { $0 }.joined(separator: " "))
                    } label: {
                        Text(tool.name)
                    }
                }
                LabeledContent("Xcode tools", value: env.developerDirectory ?? "Not installed")
            }
            if !env.versionManagers.isEmpty {
                Section("Version Managers") {
                    ForEach(env.versionManagers, id: \.name) { manager in
                        LabeledContent(manager.name, value: manager.installedVersions.joined(separator: ", ").nilIfEmpty ?? "No versions")
                    }
                }
            }
            Section("Shell") {
                LabeledContent("Login shell", value: snapshot.shell.loginShell ?? "Unknown")
                LabeledContent("Frameworks", value: snapshot.shell.frameworks.joined(separator: ", ").nilIfEmpty ?? "None")
                LabeledContent("Prompt", value: snapshot.shell.prompt ?? "Default")
            }
            if !snapshot.warnings.isEmpty {
                Section("Scan Notes") {
                    ForEach(snapshot.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
