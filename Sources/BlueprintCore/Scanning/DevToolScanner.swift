import Foundation

/// Detects developer tools (node, python, swift, ...) and version managers (nvm, pyenv, ...).
///
/// Care is taken never to trigger macOS install prompts: `/usr/bin/git`,
/// `/usr/bin/python3` and friends are stubs that pop up a "install command line
/// developer tools" dialog when the tools are missing, and `/usr/bin/java`
/// does the same without a JDK. Those stubs are only run when it is safe.
public struct DevToolScanner: Scanner {
    public let id = "devtools"

    public struct ToolSpec: Sendable {
        public var name: String
        public var arguments: [String]
        /// Regex whose first capture group is the version.
        public var versionPattern: String

        public init(_ name: String, _ arguments: [String] = ["--version"], version: String = #"(\d+\.\d+(?:\.\d+)?)"#) {
            self.name = name
            self.arguments = arguments
            self.versionPattern = version
        }
    }

    public static let defaultTools: [ToolSpec] = [
        ToolSpec("node"),
        ToolSpec("pnpm"),
        ToolSpec("yarn"),
        ToolSpec("bun"),
        ToolSpec("deno"),
        ToolSpec("python3"),
        ToolSpec("uv"),
        ToolSpec("swift", version: #"Swift version (\d+\.\d+(?:\.\d+)?)"#),
        ToolSpec("git"),
        ToolSpec("go", ["version"], version: #"go(\d+\.\d+(?:\.\d+)?)"#),
        ToolSpec("rustc"),
        ToolSpec("ruby"),
        ToolSpec("java", ["-version"], version: #"version "([^"]+)""#),
        ToolSpec("docker"),
        ToolSpec("gh"),
    ]

    /// `/usr/bin` stubs that need Xcode or the Command Line Tools.
    static let developerToolStubs: Set<String> = ["git", "python3", "swift"]

    struct ManagerSpec {
        var name: String
        /// Home-relative directory whose presence means the manager is installed.
        var root: String
        /// Home-relative directory listing installed versions.
        var versions: String
        /// When true, `versions` holds `<tool>/<version>` folders (asdf, mise, sdkman).
        var perTool = false
    }

    static let managers: [ManagerSpec] = [
        ManagerSpec(name: "nvm", root: ".nvm", versions: ".nvm/versions/node"),
        ManagerSpec(name: "fnm", root: "Library/Application Support/fnm", versions: "Library/Application Support/fnm/node-versions"),
        ManagerSpec(name: "volta", root: ".volta", versions: ".volta/tools/image/node"),
        ManagerSpec(name: "pyenv", root: ".pyenv", versions: ".pyenv/versions"),
        ManagerSpec(name: "rbenv", root: ".rbenv", versions: ".rbenv/versions"),
        ManagerSpec(name: "rustup", root: ".rustup", versions: ".rustup/toolchains"),
        ManagerSpec(name: "asdf", root: ".asdf", versions: ".asdf/installs", perTool: true),
        ManagerSpec(name: "mise", root: ".local/share/mise", versions: ".local/share/mise/installs", perTool: true),
        ManagerSpec(name: "sdkman", root: ".sdkman", versions: ".sdkman/candidates", perTool: true),
    ]

    public let tools: [ToolSpec]

    public init(tools: [ToolSpec] = DevToolScanner.defaultTools) {
        self.tools = tools
    }

    public func scan(_ context: ScanContext) async -> DevEnvironment {
        let developerDirectory = await self.developerDirectory(context)
        let javaAvailable = await self.javaAvailable(context)

        let found = await withTaskGroup(of: DevTool?.self) { group in
            for spec in tools {
                guard let path = context.runner.locate(spec.name) else { continue }
                if path.hasPrefix("/usr/bin/") {
                    if Self.developerToolStubs.contains(spec.name) && developerDirectory == nil { continue }
                    if spec.name == "java" && !javaAvailable { continue }
                }
                group.addTask { await probe(spec, at: path, context) }
            }
            var tools: [DevTool] = []
            for await tool in group {
                if let tool { tools.append(tool) }
            }
            return tools
        }

        return DevEnvironment(
            developerDirectory: developerDirectory,
            tools: found.sorted { $0.name < $1.name },
            versionManagers: versionManagers(context)
        )
    }

    private func probe(_ spec: ToolSpec, at path: String, _ context: ScanContext) async -> DevTool? {
        do {
            let result = try await context.runner.run(path, spec.arguments, timeout: 10)
            if result.timedOut { context.warnings.add(id, "\(spec.name) timed out") }
            let version = Text.firstMatch(spec.versionPattern, in: result.combinedOutput)
            return DevTool(name: spec.name, version: version, path: path, manager: Self.manager(forPath: path))
        } catch {
            context.warnings.add(id, "could not run \(spec.name): \(error)")
            return nil
        }
    }

    private func developerDirectory(_ context: ScanContext) async -> String? {
        guard let result = try? await context.runner.run("/usr/bin/xcode-select", ["-p"], timeout: 5),
              result.succeeded else { return nil }
        let path = Text.trimmed(result.stdout)
        return path.isEmpty ? nil : path
    }

    private func javaAvailable(_ context: ScanContext) async -> Bool {
        guard let result = try? await context.runner.run("/usr/libexec/java_home", [], timeout: 5) else { return false }
        return result.succeeded
    }

    /// Guesses how a tool was installed from where its binary lives.
    static func manager(forPath path: String) -> String? {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let rules: [(String, String)] = [
            ("/.nvm/", "nvm"),
            ("/fnm/", "fnm"),
            ("/.volta/", "volta"),
            ("/.pyenv/", "pyenv"),
            ("/.rbenv/", "rbenv"),
            ("/.asdf/", "asdf"),
            ("/mise/", "mise"),
            ("/.sdkman/", "sdkman"),
            ("/.cargo/", "rustup"),
            ("/.rustup/", "rustup"),
            ("/.bun/", "bun"),
            ("/.deno/", "deno"),
            ("/opt/homebrew/", "homebrew"),
            ("/usr/local/Cellar/", "homebrew"),
            ("/usr/local/Homebrew/", "homebrew"),
            ("/Applications/Xcode", "xcode"),
            ("/Library/Developer/CommandLineTools/", "xcode-clt"),
            ("/usr/bin/", "system"),
        ]
        for candidate in [resolved, path] {
            if let match = rules.first(where: { candidate.contains($0.0) }) { return match.1 }
        }
        return nil
    }

    private func versionManagers(_ context: ScanContext) -> [VersionManager] {
        Self.managers.compactMap { spec in
            guard context.fs.isDirectory(context.fs.homePath(spec.root)) else { return nil }
            let versionsPath = context.fs.homePath(spec.versions)
            var versions: [String] = []
            for entry in (try? context.fs.list(versionsPath)) ?? [] {
                if spec.perTool {
                    for version in (try? context.fs.list(versionsPath.appendingPath(entry))) ?? [] where version != "current" {
                        versions.append("\(entry)@\(version)")
                    }
                } else {
                    versions.append(entry)
                }
            }
            return VersionManager(name: spec.name, installedVersions: versions.sorted { $0.compare($1, options: .numeric) == .orderedAscending })
        }
    }
}
