import Foundation

/// What a `base` Mac has that a `target` Mac is missing.
///
/// Typically `base` is a snapshot of the old Mac and `target` is a fresh scan
/// of the new one. Only "missing" items are restored; version differences and
/// extras are reported for information.
public struct SnapshotDiff: Codable, Sendable, Equatable {
    public var missingApps: [AppItem]
    public var missingTaps: [String]
    public var missingFormulae: [BrewFormula]
    public var missingCasks: [BrewCask]
    public var missingExtensions: [EditorInventory]
    public var missingDevTools: [DevTool]
    /// Managers that are absent, or present but missing some versions (only the missing versions are listed).
    public var missingVersionManagers: [VersionManager]
    public var missingShellFrameworks: [String]
    public var missingPrompt: String?
    /// The old Mac had Xcode or the Command Line Tools, the new one does not.
    public var missingDeveloperTools: Bool
    public var versionChanges: [VersionChange]
    /// Apps on the target that the base never had (informational).
    public var extraApps: [AppItem]
    public var architectureChange: ArchitectureChange?

    public var isEmpty: Bool {
        missingApps.isEmpty && missingTaps.isEmpty && missingFormulae.isEmpty && missingCasks.isEmpty
            && missingExtensions.isEmpty && missingDevTools.isEmpty && missingVersionManagers.isEmpty
            && missingShellFrameworks.isEmpty && missingPrompt == nil && !missingDeveloperTools
    }

    public var missingCount: Int {
        missingApps.count + missingTaps.count + missingFormulae.count + missingCasks.count
            + missingExtensions.reduce(0) { $0 + $1.extensions.count } + missingDevTools.count
            + missingVersionManagers.reduce(0) { $0 + max(1, $1.installedVersions.count) }
            + missingShellFrameworks.count + (missingPrompt == nil ? 0 : 1) + (missingDeveloperTools ? 1 : 0)
    }
}

public struct VersionChange: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case app, formula, cask, devTool }
    public var kind: Kind
    public var name: String
    public var from: String
    public var to: String
}

public struct ArchitectureChange: Codable, Sendable, Equatable {
    public var from: String
    public var to: String
}

extension SnapshotDiff {
    /// Compares two snapshots.
    /// - Parameters:
    ///   - base: the Mac you want to reproduce (usually the old one).
    ///   - target: the Mac you are setting up. Pass an empty snapshot to restore everything.
    public static func compare(base: Snapshot, target: Snapshot) -> SnapshotDiff {
        // Apps
        let targetAppKeys = Set(target.apps.map(\.key))
        let targetAppFiles = Set(target.apps.map { ($0.path as NSString).lastPathComponent.lowercased() })
        let baseApps = base.apps.filter { $0.source != .system }
        let missingApps = baseApps.filter { !targetAppKeys.contains($0.key) }
        let baseAppKeys = Set(base.apps.map(\.key))
        let extraApps = target.apps.filter { $0.source != .system && !baseAppKeys.contains($0.key) }

        // Homebrew
        let targetTaps = Set(target.homebrew.taps)
        let missingTaps = base.homebrew.taps.filter { !targetTaps.contains($0) }

        let targetFormulae = Set(target.homebrew.formulae.map { shortName($0.name) })
        let missingFormulae = base.homebrew.formulae
            .filter { $0.onRequest && !targetFormulae.contains(shortName($0.name)) }

        let targetCasks = Set(target.homebrew.casks.map { shortName($0.token) })
        let missingCasks = base.homebrew.casks.filter { cask in
            guard !targetCasks.contains(shortName(cask.token)) else { return false }
            // Already installed some other way (e.g. downloaded by hand)? Nothing to restore.
            let installedAnyway = !cask.apps.isEmpty && cask.apps.allSatisfy { targetAppFiles.contains($0.lowercased()) }
            return !installedAnyway
        }

        // Editors
        let missingExtensions: [EditorInventory] = base.editors.compactMap { editor in
            let installed = Set(target.editors.first { $0.editor == editor.editor }?.extensions.map(\.id) ?? [])
            let missing = editor.extensions.filter { !installed.contains($0.id) }
            return missing.isEmpty ? nil : EditorInventory(editor: editor.editor, extensions: missing)
        }

        // Developer environment
        let targetTools = Set(target.devEnvironment.tools.map(\.name))
        let missingDevTools = base.devEnvironment.tools.filter { !targetTools.contains($0.name) }

        let missingVersionManagers: [VersionManager] = base.devEnvironment.versionManagers.compactMap { manager in
            guard let installed = target.devEnvironment.versionManagers.first(where: { $0.name == manager.name }) else {
                return manager
            }
            let have = Set(installed.installedVersions)
            let missing = manager.installedVersions.filter { !have.contains($0) }
            return missing.isEmpty ? nil : VersionManager(name: manager.name, installedVersions: missing)
        }

        // Shell
        let targetFrameworks = Set(target.shell.frameworks)
        let missingFrameworks = base.shell.frameworks.filter { !targetFrameworks.contains($0) }
        let missingPrompt = (base.shell.prompt != nil && base.shell.prompt != target.shell.prompt) ? base.shell.prompt : nil

        return SnapshotDiff(
            missingApps: missingApps,
            missingTaps: missingTaps,
            missingFormulae: missingFormulae,
            missingCasks: missingCasks,
            missingExtensions: missingExtensions,
            missingDevTools: missingDevTools,
            missingVersionManagers: missingVersionManagers,
            missingShellFrameworks: missingFrameworks,
            missingPrompt: missingPrompt,
            missingDeveloperTools: base.devEnvironment.developerDirectory != nil && target.devEnvironment.developerDirectory == nil,
            versionChanges: versionChanges(base: base, target: target),
            extraApps: extraApps,
            architectureChange: base.machine.architecture == target.machine.architecture
                ? nil
                : ArchitectureChange(from: base.machine.architecture, to: target.machine.architecture)
        )
    }

    /// `user/tap/name` and `name` refer to the same package for comparison purposes.
    private static func shortName(_ name: String) -> String {
        String(name.split(separator: "/").last ?? Substring(name)).lowercased()
    }

    private static func versionChanges(base: Snapshot, target: Snapshot) -> [VersionChange] {
        var changes: [VersionChange] = []

        func compare<T>(_ kind: VersionChange.Kind, _ old: [T], _ new: [T], key: (T) -> String, name: (T) -> String, version: (T) -> String?) {
            let newByKey = Dictionary(new.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
            for item in old {
                guard let match = newByKey[key(item)],
                      let from = version(item), let to = version(match), from != to else { continue }
                changes.append(VersionChange(kind: kind, name: name(item), from: from, to: to))
            }
        }

        compare(.app, base.apps.filter { $0.source != .system }, target.apps, key: \.key, name: \.name, version: \.version)
        compare(.formula, base.homebrew.formulae.filter(\.onRequest), target.homebrew.formulae, key: { shortName($0.name) }, name: \.name, version: \.version)
        compare(.cask, base.homebrew.casks, target.homebrew.casks, key: { shortName($0.token) }, name: \.token, version: \.version)
        compare(.devTool, base.devEnvironment.tools, target.devEnvironment.tools, key: \.name, name: \.name, version: \.version)
        return changes
    }
}

extension Snapshot {
    /// A snapshot of a Mac with nothing installed. Diffing against it yields "restore everything".
    public static func empty(machine: MachineInfo) -> Snapshot {
        Snapshot(
            createdAt: Date(timeIntervalSince1970: 0),
            label: nil,
            machine: machine,
            apps: [],
            homebrew: .notInstalled,
            editors: [],
            devEnvironment: DevEnvironment(developerDirectory: nil, tools: [], versionManagers: []),
            shell: ShellInfo(loginShell: nil, frameworks: [], prompt: nil),
            warnings: []
        )
    }
}
