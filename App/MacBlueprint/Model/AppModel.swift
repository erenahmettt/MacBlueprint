import BlueprintCore
import Foundation
import Observation
import SwiftData

enum SidebarItem: Hashable {
    case thisMac
    case compare
    case restore
    case saved(UUID)
}

/// App-wide state: the live scan of this Mac, the snapshot being compared
/// against, and the restore plan with the user's selection.
@MainActor
@Observable
final class AppModel {
    struct Base {
        var snapshot: Snapshot
        var name: String
    }

    var sidebar: SidebarItem? = .thisMac
    var isImporting = false
    var errorMessage: String?

    private(set) var thisMac: Snapshot?
    private(set) var isScanning = false

    private(set) var base: Base?
    private(set) var diff: SnapshotDiff?
    private(set) var plan: RestorePlan?
    var selection: Set<String> = []

    private(set) var matchCasks = false
    private(set) var isLoadingCatalog = false
    private var catalog: CaskCatalog?

    let library = SnapshotLibrary()

    // MARK: Scanning

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        let builder = SnapshotBuilder()
        thisMac = await builder.build()
        recompute()
    }

    /// Saves the current scan to the sidebar.
    func saveThisMac(label: String, context: ModelContext) {
        guard var snapshot = thisMac else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.label = trimmed.isEmpty ? nil : trimmed
        do {
            let url = try library.save(snapshot)
            let record = SnapshotRecord(snapshot: snapshot, fileName: url.lastPathComponent)
            context.insert(record)
            sidebar = .saved(record.id)
        } catch {
            errorMessage = "Couldn't save the snapshot. \(error.localizedDescription)"
        }
    }

    // MARK: Choosing what to compare against

    /// Opens a snapshot file (e.g. from the old Mac), keeps a copy in the library and compares with it.
    func importSnapshot(at url: URL, context: ModelContext) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let snapshot = try Snapshot.decode(from: Data(contentsOf: url))
            let copy = try library.save(snapshot)
            context.insert(SnapshotRecord(snapshot: snapshot, fileName: copy.lastPathComponent))
            setBase(snapshot, name: snapshot.label ?? url.deletingPathExtension().lastPathComponent)
        } catch {
            errorMessage = "\(url.lastPathComponent) isn't a MacBlueprint snapshot. \(error.localizedDescription)"
        }
    }

    func compare(with record: SnapshotRecord) {
        do {
            setBase(try library.load(record), name: record.title)
        } catch {
            errorMessage = "Couldn't open “\(record.title)”. \(error.localizedDescription)"
        }
    }

    func delete(_ record: SnapshotRecord, context: ModelContext) {
        if sidebar == .saved(record.id) { sidebar = .thisMac }
        library.delete(record)
        context.delete(record)
    }

    private func setBase(_ snapshot: Snapshot, name: String) {
        base = Base(snapshot: snapshot, name: name)
        recompute()
        sidebar = .compare
    }

    // MARK: Restore plan

    func setMatchCasks(_ enabled: Bool) async {
        matchCasks = enabled
        if enabled && catalog == nil {
            isLoadingCatalog = true
            defer { isLoadingCatalog = false }
            do {
                catalog = try await CaskCatalogStore().load().catalog
            } catch {
                matchCasks = false
                errorMessage = "Couldn't download Homebrew's app list. \(error.localizedDescription)"
            }
        }
        recompute()
    }

    /// The plan with only the steps the user kept selected.
    var selectedPlan: RestorePlan? {
        plan?.selecting(selection)
    }

    var restoreSource: RestoreSource? {
        base.map { RestoreSource(snapshotLabel: $0.snapshot.label ?? $0.name, snapshotDate: $0.snapshot.createdAt, comparedAgainst: "this Mac") }
    }

    func isSelected(_ id: String) -> Bool { selection.contains(id) }

    func setSelected(_ id: String, _ selected: Bool) {
        if selected { selection.insert(id) } else { selection.remove(id) }
    }

    func setSelected(_ ids: [String], _ selected: Bool) {
        if selected { selection.formUnion(ids) } else { selection.subtract(ids) }
    }

    private func recompute() {
        guard let base, let thisMac else {
            diff = nil
            plan = nil
            selection = []
            return
        }
        let diff = SnapshotDiff.compare(base: base.snapshot, target: thisMac)
        let plan = RestorePlan.make(from: diff, catalog: matchCasks ? catalog : nil)
        self.diff = diff
        self.plan = plan
        selection = plan.defaultSelection
    }
}
