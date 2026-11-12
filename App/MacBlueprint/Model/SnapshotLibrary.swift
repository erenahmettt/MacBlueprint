import BlueprintCore
import Foundation
import SwiftData

/// A saved snapshot in the sidebar. The JSON file next to it is the source of
/// truth; this record only keeps what the sidebar needs to show.
@Model
final class SnapshotRecord {
    @Attribute(.unique) var id: UUID
    var label: String?
    var createdAt: Date
    var savedAt: Date
    var fileName: String
    var model: String?
    var osVersion: String
    var appCount: Int

    init(snapshot: Snapshot, fileName: String) {
        self.id = UUID()
        self.label = snapshot.label
        self.createdAt = snapshot.createdAt
        self.savedAt = Date()
        self.fileName = fileName
        self.model = snapshot.machine.model
        self.osVersion = snapshot.machine.osVersion
        self.appCount = snapshot.apps.filter { $0.source != .system }.count
    }

    var title: String {
        label ?? createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    var subtitle: String {
        "\(appCount) apps · macOS \(osVersion)"
    }
}

/// Stores snapshot files in ~/Library/Application Support/MacBlueprint/Snapshots.
struct SnapshotLibrary: Sendable {
    let directory: URL

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "MacBlueprint/Snapshots", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    func save(_ snapshot: Snapshot) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "snapshot-\(UUID().uuidString).json")
        try snapshot.jsonData().write(to: url, options: .atomic)
        return url
    }

    func url(for record: SnapshotRecord) -> URL {
        directory.appending(path: record.fileName)
    }

    func load(_ record: SnapshotRecord) throws -> Snapshot {
        try Snapshot.decode(from: Data(contentsOf: url(for: record)))
    }

    func delete(_ record: SnapshotRecord) {
        try? FileManager.default.removeItem(at: url(for: record))
    }
}
