import Foundation

// MARK: - Apps

public struct AppItem: Codable, Sendable, Equatable, Hashable {
    public enum Source: String, Codable, Sendable {
        /// Installed from the Mac App Store.
        case appStore
        /// Installed as a Homebrew cask.
        case homebrew
        /// Ships with macOS (e.g. Safari); never restored.
        case system
        /// Anything else, usually dragged into /Applications by hand.
        case manual
    }

    public var name: String
    public var bundleId: String?
    public var version: String?
    public var path: String
    public var source: Source
    /// Mac App Store ID, used for `mas install <id>`.
    public var appStoreId: Int?
    /// Homebrew cask token, when the app is known to come from a cask.
    public var caskToken: String?

    public init(
        name: String,
        bundleId: String?,
        version: String?,
        path: String,
        source: Source,
        appStoreId: Int? = nil,
        caskToken: String? = nil
    ) {
        self.name = name
        self.bundleId = bundleId
        self.version = version
        self.path = path
        self.source = source
        self.appStoreId = appStoreId
        self.caskToken = caskToken
    }

    /// Stable identity used when comparing snapshots.
    public var key: String { (bundleId ?? name).lowercased() }
}

// MARK: - Homebrew

public struct BrewInventory: Codable, Sendable, Equatable {
    public var installed: Bool
    public var prefix: String?
    public var taps: [String]
    public var formulae: [BrewFormula]
    public var casks: [BrewCask]

    public init(installed: Bool, prefix: String? = nil, taps: [String] = [], formulae: [BrewFormula] = [], casks: [BrewCask] = []) {
        self.installed = installed
        self.prefix = prefix
        self.taps = taps
        self.formulae = formulae
        self.casks = casks
    }

    public static let notInstalled = BrewInventory(installed: false)
}

public struct BrewFormula: Codable, Sendable, Equatable, Hashable {
    /// Full name; includes the tap for third-party formulae ("user/tap/name").
    public var name: String
    public var version: String?
    /// `false` when the formula was only pulled in as a dependency.
    public var onRequest: Bool

    public init(name: String, version: String?, onRequest: Bool) {
        self.name = name
        self.version = version
        self.onRequest = onRequest
    }
}

public struct BrewCask: Codable, Sendable, Equatable, Hashable {
    public var token: String
    public var version: String?
    /// `.app` bundle names this cask installs, used to link casks to apps.
    public var apps: [String]

    public init(token: String, version: String?, apps: [String] = []) {
        self.token = token
        self.version = version
        self.apps = apps
    }
}

// MARK: - Editors

public enum EditorKind: String, Codable, Sendable, CaseIterable {
    case vscode
    case cursor
    case vscodium
    case windsurf
    case antigravity
    case antigravityIDE = "antigravity-ide"

    public var displayName: String {
        switch self {
        case .vscode: "Visual Studio Code"
        case .cursor: "Cursor"
        case .vscodium: "VSCodium"
        case .windsurf: "Windsurf"
        case .antigravity: "Antigravity"
        case .antigravityIDE: "Antigravity IDE"
        }
    }

    /// Extensions directory, relative to the home directory.
    public var extensionsDirectory: String {
        switch self {
        case .vscode: ".vscode/extensions"
        case .cursor: ".cursor/extensions"
        case .vscodium: ".vscode-oss/extensions"
        case .windsurf: ".windsurf/extensions"
        case .antigravity: ".antigravity/extensions"
        case .antigravityIDE: ".antigravity-ide/extensions"
        }
    }

    /// Command-line launchers that accept `--install-extension`, in order of preference.
    /// Absolute paths point inside the app bundle, for when the command is not on PATH.
    public var cliCandidates: [String] {
        switch self {
        case .vscode: ["code", "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"]
        case .cursor: ["cursor", "/Applications/Cursor.app/Contents/Resources/app/bin/cursor"]
        case .vscodium: ["codium", "/Applications/VSCodium.app/Contents/Resources/app/bin/codium"]
        case .windsurf: ["windsurf", "/Applications/Windsurf.app/Contents/Resources/app/bin/windsurf"]
        case .antigravity: ["antigravity", "/Applications/Antigravity.app/Contents/Resources/app/bin/antigravity"]
        case .antigravityIDE: ["antigravity-ide", "/Applications/Antigravity IDE.app/Contents/Resources/app/bin/antigravity-ide"]
        }
    }
}

public struct EditorInventory: Codable, Sendable, Equatable {
    public var editor: EditorKind
    public var extensions: [EditorExtension]

    public init(editor: EditorKind, extensions: [EditorExtension]) {
        self.editor = editor
        self.extensions = extensions
    }
}

public struct EditorExtension: Codable, Sendable, Equatable, Hashable {
    /// Marketplace identifier, lowercased ("ms-vscode.cpptools").
    public var id: String
    public var version: String?

    public init(id: String, version: String?) {
        self.id = id.lowercased()
        self.version = version
    }
}

// MARK: - Developer environment

public struct DevEnvironment: Codable, Sendable, Equatable {
    /// Output of `xcode-select -p`, or nil when no developer tools are installed.
    public var developerDirectory: String?
    public var tools: [DevTool]
    public var versionManagers: [VersionManager]

    public init(developerDirectory: String?, tools: [DevTool], versionManagers: [VersionManager]) {
        self.developerDirectory = developerDirectory
        self.tools = tools
        self.versionManagers = versionManagers
    }
}

public struct DevTool: Codable, Sendable, Equatable, Hashable {
    public var name: String
    public var version: String?
    public var path: String
    /// How the tool was installed, when it can be told from its path ("nvm", "homebrew", ...).
    public var manager: String?

    public init(name: String, version: String?, path: String, manager: String?) {
        self.name = name
        self.version = version
        self.path = path
        self.manager = manager
    }
}

public struct VersionManager: Codable, Sendable, Equatable, Hashable {
    public var name: String
    public var installedVersions: [String]

    public init(name: String, installedVersions: [String]) {
        self.name = name
        self.installedVersions = installedVersions
    }
}

// MARK: - Shell

public struct ShellInfo: Codable, Sendable, Equatable {
    public var loginShell: String?
    /// Frameworks detected by their presence only, e.g. "oh-my-zsh". File contents are never read.
    public var frameworks: [String]
    public var prompt: String?

    public init(loginShell: String?, frameworks: [String], prompt: String?) {
        self.loginShell = loginShell
        self.frameworks = frameworks
        self.prompt = prompt
    }
}
