import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \SnapshotRecord.savedAt, order: .reverse) private var records: [SnapshotRecord]

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            List(selection: $model.sidebar) {
                Section("This Mac") {
                    Label("Overview", systemImage: "laptopcomputer")
                        .tag(SidebarItem.thisMac)
                }
                Section("Move to This Mac") {
                    Label("Compare", systemImage: "arrow.left.arrow.right")
                        .tag(SidebarItem.compare)
                    Label("Restore", systemImage: "square.and.arrow.down.on.square")
                        .badge(model.selection.count)
                        .tag(SidebarItem.restore)
                }
                if !records.isEmpty {
                    Section("Saved Snapshots") {
                        ForEach(records) { record in
                            SavedSnapshotRow(record: record)
                                .tag(SidebarItem.saved(record.id))
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
        } detail: {
            detail
        }
        .fileImporter(isPresented: $model.isImporting, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                model.importSnapshot(at: url, context: context)
            }
        }
        // Drop a snapshot on the window, or `open -a MacBlueprint old-mac.json`.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == "json" }) else { return false }
            model.importSnapshot(at: url, context: context)
            return true
        }
        .onOpenURL { url in
            guard url.isFileURL else { return }
            model.importSnapshot(at: url, context: context)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task {
            if model.thisMac == nil { await model.scan() }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.sidebar {
        case .thisMac, nil:
            ThisMacView()
        case .compare, .restore:
            ContentUnavailableView("Coming soon", systemImage: "hammer")
        case .saved(let id):
            if let record = records.first(where: { $0.id == id }) {
                SavedSnapshotView(record: record)
                    .id(record.id)
            } else {
                ContentUnavailableView("Snapshot not found", systemImage: "doc.questionmark")
            }
        }
    }
}

private struct SavedSnapshotRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    let record: SnapshotRecord

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(record.title)
                Text(record.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "doc.text")
        }
        .contextMenu {
            Button("Compare with This Mac") { model.compare(with: record) }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([model.library.url(for: record)])
            }
            Divider()
            Button("Delete", role: .destructive) { model.delete(record, context: context) }
        }
    }
}
