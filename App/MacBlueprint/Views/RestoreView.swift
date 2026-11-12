import BlueprintCore
import SwiftUI

/// The restore checklist: pick what to install, then dry-run, install or export.
struct RestoreView: View {
    @Environment(AppModel.self) private var model
    @Environment(RestoreRunner.self) private var runner
    @State private var confirmingInstall = false

    var body: some View {
        @Bindable var runner = runner

        Group {
            if let plan = model.plan {
                if plan.isEmpty {
                    ContentUnavailableView("Nothing to restore", systemImage: "checkmark.circle", description: Text("This Mac already has everything from the snapshot."))
                } else {
                    PlanList(plan: plan)
                }
            } else {
                ContentUnavailableView {
                    Label("No restore plan yet", systemImage: "square.and.arrow.down.on.square")
                } description: {
                    Text("Compare this Mac with a snapshot of your old Mac first.")
                } actions: {
                    Button("Go to Compare") { model.sidebar = .compare }
                }
            }
        }
        .navigationTitle("Restore")
        .navigationSubtitle(model.plan.map { _ in "\(model.selection.count) selected" } ?? "")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    export()
                } label: {
                    Label("Export Files", systemImage: "folder")
                }
                .help("Save PLAN.md, Brewfile and restore.sh to a folder")
                .disabled(model.plan == nil)

                Button {
                    run(dryRun: true)
                } label: {
                    Label("Dry Run", systemImage: "eye")
                }
                .help("Show every command without changing anything")
                .disabled(model.selection.isEmpty)

                Button {
                    confirmingInstall = true
                } label: {
                    Label("Install \(model.selection.count)", systemImage: "arrow.down.circle")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selection.isEmpty)
            }
        }
        .confirmationDialog("Install \(model.selection.count) items on this Mac?", isPresented: $confirmingInstall) {
            Button("Install") { run(dryRun: false) }
            Button("Dry Run First") { run(dryRun: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("MacBlueprint will run Homebrew, mas and your editors' command-line tools. Some installers may ask for your password. You can stop at any time.")
        }
        .sheet(isPresented: $runner.isPresented) {
            RunLogView()
        }
    }

    private func run(dryRun: Bool) {
        guard let plan = model.selectedPlan, let source = model.restoreSource else { return }
        runner.start(plan, source: source, dryRun: dryRun)
    }

    private func export() {
        guard let plan = model.selectedPlan, let source = model.restoreSource,
              let folder = Panels.chooseFolder(prompt: "Export Here") else { return }
        let directory = folder.appending(path: "MacBlueprint Restore", directoryHint: .isDirectory)
        do {
            try RestoreFiles.write(plan, source: source, to: directory)
            NSWorkspace.shared.activateFileViewerSelecting([directory.appending(path: RestoreFiles.planFile)])
        } catch {
            model.errorMessage = "Couldn't write the restore files. \(error.localizedDescription)"
        }
    }
}

private struct PlanList: View {
    @Environment(AppModel.self) private var model
    let plan: RestorePlan

    var body: some View {
        let items = plan.items
        List {
            if !plan.warnings.isEmpty {
                Section {
                    ForEach(plan.warnings, id: \.self) { warning in
                        // Warnings use Markdown for commands, e.g. `mas`.
                        Label(LocalizedStringKey(warning), systemImage: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                    }
                }
            }

            Section {
                Toggle(isOn: Binding(
                    get: { model.matchCasks },
                    set: { enabled in Task { await model.setMatchCasks(enabled) } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Find Homebrew casks for apps you installed by hand")
                            if model.isLoadingCatalog { ProgressView().controlSize(.small) }
                        }
                        Text("Downloads Homebrew's public list of apps. Nothing about your Mac is sent.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            group("Apps", systemImage: "square.grid.2x2", items.filter { $0.kind == .cask || $0.kind == .appStore })
            group("Homebrew Packages", systemImage: "mug", items.filter { $0.kind == .tap || $0.kind == .formula })
            ForEach(plan.extensions, id: \.editor) { inventory in
                group("\(inventory.editor.displayName) Extensions", systemImage: "puzzlepiece.extension",
                      items.filter { $0.kind == .editorExtension(inventory.editor) })
            }

            if !plan.manualApps.isEmpty || !plan.manualSteps.isEmpty {
                Section {
                    ForEach(plan.manualApps, id: \.name) { app in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                            Text(app.hint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(plan.manualSteps, id: \.title) { step in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(step.title)
                            if let note = step.note {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(step.commands, id: \.self) { CommandRow(command: $0) }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Label("Needs You (\(plan.manualApps.count + plan.manualSteps.count))", systemImage: "hand.raised")
                } footer: {
                    Text("These can't be installed automatically. They're also listed in PLAN.md when you export.")
                }
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, systemImage: String, _ items: [RestoreItem]) -> some View {
        if !items.isEmpty {
            let ids = items.map(\.id)
            let selectedCount = ids.filter(model.isSelected).count
            Section {
                ForEach(items) { item in
                    Toggle(isOn: Binding(
                        get: { model.isSelected(item.id) },
                        set: { model.setSelected(item.id, $0) }
                    )) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                if let detail = item.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if !item.selectedByDefault {
                                Text("Check match")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .foregroundStyle(.orange)
                                    .background(.orange.opacity(0.14), in: Capsule())
                                    .help("Matched by app name only. Make sure it's the same app before installing.")
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Label("\(title) (\(selectedCount)/\(items.count))", systemImage: systemImage)
                    Spacer()
                    Button(selectedCount == items.count ? "Deselect All" : "Select All") {
                        model.setSelected(ids, selectedCount != items.count)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
    }
}

/// Live output of restore.sh.
struct RunLogView: View {
    @Environment(RestoreRunner.self) private var runner
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(runner.isDryRun ? "Dry Run" : "Installing")
                        .font(.headline)
                    Text(statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(runner.output.isEmpty ? " " : runner.output)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: runner.output) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }

            HStack {
                Button("Copy Log") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(runner.output, forType: .string)
                }
                Spacer()
                if runner.phase == .running {
                    Button("Stop", role: .destructive) { runner.stop() }
                } else {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 440)
        .interactiveDismissDisabled(runner.phase == .running)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch runner.phase {
        case .running:
            ProgressView().controlSize(.small)
        case .finished(let status) where status == 0:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title2)
        default:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title2)
        }
    }

    private var statusText: String {
        switch runner.phase {
        case .idle: ""
        case .running: runner.isDryRun ? "Listing commands. Nothing is installed." : "This can take a while. Keep the window open."
        case .finished(let status) where status == 0: runner.isDryRun ? "Done. Nothing was changed." : "Done. Check the log for steps that failed."
        case .finished(let status): "Stopped with exit code \(status)."
        case .failed(let message): "Couldn't start: \(message)"
        }
    }
}
