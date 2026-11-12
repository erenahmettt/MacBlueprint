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
        .modelContainer(for: SnapshotRecord.self)
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
}
