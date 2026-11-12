import Foundation

/// Everything needed to bring a Mac up to a snapshot, split into what can be
/// automated (Homebrew, App Store via `mas`, editor extensions) and what needs
/// a human (hand-installed apps, version managers, shell frameworks).
///
/// A plan is data only. Turning it into files is the job of the exporters,
/// and running those files is always the user's decision.
public struct RestorePlan: Codable, Sendable, Equatable {
    public struct CaskInstall: Codable, Sendable, Equatable {
        public var token: String
        /// Why this cask is here when it was not a cask on the old Mac.
        public var note: String?
        /// Matched on the app name only: plausible, but worth a look before installing.
        public var needsReview: Bool = false
    }

    public struct AppStoreInstall: Codable, Sendable, Equatable {
        public var name: String
        public var id: Int
    }

    public struct ManualApp: Codable, Sendable, Equatable {
        public var name: String
        public var bundleId: String?
        public var version: String?
        public var hint: String
    }

    public struct ManualStep: Codable, Sendable, Equatable {
        public var title: String
        public var commands: [String]
        public var note: String?
    }

    public var taps: [String] = []
    public var formulae: [String] = []
    public var casks: [CaskInstall] = []
    public var appStoreApps: [AppStoreInstall] = []
    public var extensions: [EditorInventory] = []
    public var manualApps: [ManualApp] = []
    public var manualSteps: [ManualStep] = []
    public var warnings: [String] = []
    /// Informational: what changed version between the two Macs.
    public var versionChanges: [VersionChange] = []
    /// `mas` was added only to install App Store apps (not because the old Mac had it).
    public var addedMas = false

    public var usesHomebrew: Bool { !taps.isEmpty || !formulae.isEmpty || !casks.isEmpty || !appStoreApps.isEmpty }
    public var extensionCount: Int { extensions.reduce(0) { $0 + $1.extensions.count } }
    public var automatedCount: Int { taps.count + formulae.count + casks.count + appStoreApps.count + extensionCount }
    public var isEmpty: Bool { automatedCount == 0 && manualApps.isEmpty && manualSteps.isEmpty }
}

extension RestorePlan {
    /// Builds a plan from a diff.
    /// - Parameter catalog: when given, hand-installed apps are matched to Homebrew casks.
    public static func make(from diff: SnapshotDiff, catalog: CaskCatalog? = nil) -> RestorePlan {
        var plan = RestorePlan()
        plan.taps = diff.missingTaps
        plan.formulae = diff.missingFormulae.map(\.name)
        plan.casks = diff.missingCasks.map { CaskInstall(token: $0.token) }
        plan.extensions = diff.missingExtensions
        plan.versionChanges = diff.versionChanges

        for app in diff.missingApps {
            if let token = app.caskToken {
                if !plan.casks.contains(where: { $0.token == token }) {
                    plan.casks.append(CaskInstall(token: token))
                }
                continue
            }
            switch app.source {
            case .appStore:
                if let id = app.appStoreId {
                    plan.appStoreApps.append(AppStoreInstall(name: app.name, id: id))
                } else {
                    plan.manualApps.append(ManualApp(name: app.name, bundleId: app.bundleId, version: app.version, hint: "Install it from the App Store."))
                }
            case .manual, .homebrew:
                if let match = catalog?.match(app) {
                    if !plan.casks.contains(where: { $0.token == match.token }) {
                        plan.casks.append(CaskInstall(token: match.token, note: note(for: app, match.evidence), needsReview: match.evidence == .appName))
                    }
                } else {
                    let hint = catalog == nil
                        ? "Download it from the developer."
                        : "No Homebrew cask found; download it from the developer."
                    plan.manualApps.append(ManualApp(name: app.name, bundleId: app.bundleId, version: app.version, hint: hint))
                }
            case .system:
                break
            }
        }

        if !plan.appStoreApps.isEmpty && !plan.formulae.contains("mas") {
            plan.formulae.append("mas")
            plan.addedMas = true
        }

        plan.manualSteps = manualSteps(diff, plan: plan)
        plan.warnings = warnings(diff, plan: plan)
        return plan
    }

    private static func note(for app: AppItem, _ evidence: CaskCatalog.Match.Evidence) -> String {
        switch evidence {
        case .bundleIdAndName, .bundleId: "was installed by hand; matched \(app.name).app by bundle ID"
        case .appName: "was installed by hand; matched by app name \(app.name).app"
        }
    }

    // MARK: Manual steps

    static let versionManagerTools: Set<String> = ["nvm", "fnm", "volta", "pyenv", "rbenv", "rustup", "asdf", "mise", "sdkman"]

    private static func manualSteps(_ diff: SnapshotDiff, plan: RestorePlan) -> [ManualStep] {
        var steps: [ManualStep] = []

        if diff.missingDeveloperTools {
            steps.append(ManualStep(
                title: "Install the Xcode Command Line Tools",
                commands: ["xcode-select --install"],
                note: "Needed by Homebrew, git and most developer tools. Install the full Xcode from the App Store instead if you build Apple apps."
            ))
        }

        for manager in diff.missingVersionManagers {
            steps.append(versionManagerStep(manager, formulae: plan.formulae))
        }

        let coveredByManager = Set(diff.missingVersionManagers.map(\.name))
        for tool in diff.missingDevTools {
            switch tool.manager {
            case "homebrew", "system", "xcode", "xcode-clt":
                continue // restored with Homebrew or the Command Line Tools
            case let manager? where versionManagerTools.contains(manager):
                if coveredByManager.contains(manager) { continue }
                steps.append(ManualStep(title: "Install \(tool.name) \(tool.version ?? "") with \(manager)", commands: [], note: nil))
            default:
                steps.append(ManualStep(
                    title: "Install \(tool.name)\(tool.version.map { " \($0)" } ?? "")",
                    commands: [],
                    note: "It was at \(tool.path) on the old Mac."
                ))
            }
        }

        for framework in diff.missingShellFrameworks {
            let links = [
                "oh-my-zsh": "https://ohmyz.sh",
                "prezto": "https://github.com/sorin-ionescu/prezto",
                "antidote": "https://getantidote.github.io",
                "zinit": "https://github.com/zdharma-continuum/zinit",
                "oh-my-bash": "https://ohmybash.nntoan.com",
                "oh-my-fish": "https://github.com/oh-my-fish/oh-my-fish",
            ]
            steps.append(ManualStep(
                title: "Set up \(framework)",
                commands: [],
                note: "Follow the official instructions at \(links[framework] ?? "the project's website"). Your settings in dotfiles are not restored yet."
            ))
        }

        if let prompt = diff.missingPrompt {
            switch prompt {
            case "starship" where plan.formulae.contains("starship"):
                break
            case "starship":
                steps.append(ManualStep(title: "Install the starship prompt", commands: ["brew install starship"], note: "Then add `eval \"$(starship init zsh)\"` to ~/.zshrc."))
            case "powerlevel10k":
                steps.append(ManualStep(title: "Install powerlevel10k", commands: [], note: "See https://github.com/romkatv/powerlevel10k#installation, then run `p10k configure`."))
            default:
                steps.append(ManualStep(title: "Install the \(prompt) prompt", commands: [], note: nil))
            }
        }

        return steps
    }

    private static func versionManagerStep(_ manager: VersionManager, formulae: [String]) -> ManualStep {
        let versions = manager.installedVersions
        func setup(_ formula: String) -> [String] { formulae.contains(formula) ? [] : ["brew install \(formula)"] }

        switch manager.name {
        case "nvm":
            return ManualStep(
                title: "Install Node.js with nvm",
                commands: versions.map { "nvm install \($0.drop { $0 == "v" })" },
                note: "Install nvm first: https://github.com/nvm-sh/nvm#installing-and-updating"
            )
        case "fnm":
            return ManualStep(title: "Install Node.js with fnm", commands: setup("fnm") + versions.map { "fnm install \($0)" }, note: nil)
        case "volta":
            return ManualStep(title: "Install Node.js with Volta", commands: versions.map { "volta install node@\($0)" }, note: "Install Volta first: https://volta.sh")
        case "pyenv":
            return ManualStep(title: "Install Python with pyenv", commands: setup("pyenv") + versions.map { "pyenv install \($0)" }, note: nil)
        case "rbenv":
            return ManualStep(title: "Install Ruby with rbenv", commands: setup("rbenv") + versions.map { "rbenv install \($0)" }, note: nil)
        case "rustup":
            let toolchains = versions.map { $0.replacingOccurrences(of: #"-(aarch64|x86_64)-apple-darwin$"#, with: "", options: .regularExpression) }
            return ManualStep(title: "Install Rust with rustup", commands: setup("rustup") + toolchains.map { "rustup toolchain install \($0)" }, note: nil)
        case "asdf":
            return ManualStep(title: "Install tools with asdf", commands: setup("asdf") + versions.map { "asdf install \($0.replacingOccurrences(of: "@", with: " "))" }, note: "Add each plugin first with `asdf plugin add <name>`.")
        case "mise":
            return ManualStep(title: "Install tools with mise", commands: setup("mise") + versions.map { "mise install \($0)" }, note: nil)
        case "sdkman":
            return ManualStep(title: "Install JVM tools with SDKMAN!", commands: versions.map { "sdk install \($0.replacingOccurrences(of: "@", with: " "))" }, note: "Install SDKMAN! first: https://sdkman.io/install")
        default:
            return ManualStep(title: "Set up \(manager.name)", commands: [], note: versions.isEmpty ? nil : "Versions: \(versions.joined(separator: ", "))")
        }
    }

    private static func warnings(_ diff: SnapshotDiff, plan: RestorePlan) -> [String] {
        var warnings: [String] = []
        if let change = diff.architectureChange {
            if change.to == "arm64" {
                warnings.append("The old Mac had an Intel chip and this one has Apple silicon. Some older apps are Intel-only and need Rosetta 2 (`softwareupdate --install-rosetta`).")
            } else {
                warnings.append("The old Mac had Apple silicon and this one has an Intel chip. Apps built only for Apple silicon won't run here.")
            }
        }
        if !plan.appStoreApps.isEmpty {
            warnings.append("Sign in to the App Store before installing. `mas` can only install apps your Apple ID has already bought or downloaded.")
        }
        if plan.casks.contains(where: { $0.note != nil }) {
            warnings.append("Some apps that you installed by hand will now be installed through Homebrew. Check the matches in PLAN.md and delete any `cask` line you don't want from the Brewfile.")
        }
        return warnings
    }
}
