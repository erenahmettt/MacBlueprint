import SwiftData
import SwiftUI

@main
struct MacBlueprintApp: App {
    @State private var model = AppModel()
    @State private var runner = RestoreRunner()

    var body: some Scene {
        WindowGroup("MacBlueprint") {
            ContentView()
                .environment(model)
                .environment(runner)
                .frame(minWidth: 880, minHeight: 560)
        }
        .defaultSize(width: 1080, height: 700)
        .modelContainer(Self.modelContainer)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Snapshot…") { model.isImporting = true }
                    .keyboardShortcut("o")
            }
            CommandMenu("Snapshot") {
                Button("Scan This Mac Again") { Task { await model.scan() } }
                    .keyboardShortcut("r")
                    .disabled(model.isScanning)
            }
        }
    }

    /// The list of saved snapshots lives in MacBlueprint's own folder. Without
    /// an explicit URL, SwiftData uses ~/Library/Application Support/default.store
    /// for apps outside the sandbox, a file other apps may share.
    static let modelContainer: ModelContainer = {
        let url = URL.applicationSupportDirectory.appending(path: "MacBlueprint/Library.store")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            return try ModelContainer(for: SnapshotRecord.self, configurations: ModelConfiguration(url: url))
        } catch {
            // Saved snapshots are files on disk; losing the index for a session is not fatal.
            return try! ModelContainer(for: SnapshotRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }()
}
