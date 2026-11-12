import Foundation

/// Lists extensions of VS Code and its forks (Cursor, VSCodium, Windsurf, Antigravity).
///
/// Reads the editor's `extensions.json` manifest directly instead of calling
/// `code --list-extensions`, because the `code` command is often not on PATH.
/// Falls back to parsing extension folder names when the manifest is missing.
public struct EditorScanner: Scanner {
    public let id = "editors"

    public init() {}

    public func scan(_ context: ScanContext) async -> [EditorInventory] {
        EditorKind.allCases.compactMap { editor in
            let directory = context.fs.homePath(editor.extensionsDirectory)
            guard context.fs.isDirectory(directory) else { return nil }

            let extensions: [EditorExtension]
            if let data = try? context.fs.read(directory.appendingPath("extensions.json")),
               let fromManifest = Self.parseManifest(data) {
                extensions = fromManifest
            } else {
                extensions = Self.parseFolderNames((try? context.fs.list(directory)) ?? [])
            }
            return EditorInventory(editor: editor, extensions: extensions)
        }
    }

    /// Parses `extensions.json`: `[{"identifier": {"id": "..."}, "version": "..."}]`.
    static func parseManifest(_ data: Data) -> [EditorExtension]? {
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let extensions = entries.compactMap { entry -> EditorExtension? in
            guard let identifier = entry["identifier"] as? [String: Any],
                  let id = identifier["id"] as? String else { return nil }
            return EditorExtension(id: id, version: entry["version"] as? String)
        }
        return deduplicated(extensions)
    }

    /// Parses folder names like `ms-python.python-2024.1.0-darwin-arm64`.
    static func parseFolderNames(_ names: [String]) -> [EditorExtension] {
        let extensions = names.compactMap { name -> EditorExtension? in
            guard let id = Text.firstMatch(#"^(.+?)-\d+\.\d+\.\d+"#, in: name), id.contains(".") else { return nil }
            let version = Text.firstMatch(#"-(\d+\.\d+\.\d+[0-9A-Za-z.+]*)"#, in: name)
            return EditorExtension(id: id, version: version)
        }
        return deduplicated(extensions)
    }

    /// Keeps the highest version when an extension appears more than once.
    private static func deduplicated(_ extensions: [EditorExtension]) -> [EditorExtension] {
        var byId: [String: EditorExtension] = [:]
        for ext in extensions {
            if let existing = byId[ext.id],
               (existing.version ?? "").compare(ext.version ?? "", options: .numeric) != .orderedAscending {
                continue
            }
            byId[ext.id] = ext
        }
        return byId.values.sorted { $0.id < $1.id }
    }
}
