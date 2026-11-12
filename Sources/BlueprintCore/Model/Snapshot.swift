import Foundation

/// A portable description of how a Mac is set up.
///
/// A snapshot is the source of truth of MacBlueprint: it is plain JSON, can be
/// committed to git, carried on a USB stick, or diffed against another Mac.
/// It deliberately contains no user name, host name, or secret.
public struct Snapshot: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var createdAt: Date
    /// A user-chosen label such as "Work MacBook". Never derived from the host name.
    public var label: String?
    public var tool: ToolInfo
    public var machine: MachineInfo
    public var apps: [AppItem]
    public var homebrew: BrewInventory
    public var editors: [EditorInventory]
    public var devEnvironment: DevEnvironment
    public var shell: ShellInfo
    /// Non-fatal problems hit while scanning, e.g. "homebrew: not installed".
    public var warnings: [String]

    public init(
        schemaVersion: Int = Snapshot.currentSchemaVersion,
        createdAt: Date,
        label: String?,
        tool: ToolInfo = .current,
        machine: MachineInfo,
        apps: [AppItem],
        homebrew: BrewInventory,
        editors: [EditorInventory],
        devEnvironment: DevEnvironment,
        shell: ShellInfo,
        warnings: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.label = label
        self.tool = tool
        self.machine = machine
        self.apps = apps
        self.homebrew = homebrew
        self.editors = editors
        self.devEnvironment = devEnvironment
        self.shell = shell
        self.warnings = warnings
    }
}

public struct ToolInfo: Codable, Sendable, Equatable {
    public var name: String
    public var version: String

    public static let current = ToolInfo(name: "macblueprint", version: MacBlueprint.version)
}

public enum MacBlueprint {
    public static let version = "0.3.1"
}

public struct MachineInfo: Codable, Sendable, Equatable {
    /// Hardware model identifier, e.g. "Mac15,6".
    public var model: String?
    /// "arm64" or "x86_64".
    public var architecture: String
    /// e.g. "26.1.0".
    public var osVersion: String

    public init(model: String?, architecture: String, osVersion: String) {
        self.model = model
        self.architecture = architecture
        self.osVersion = osVersion
    }
}
