import Foundation
import Testing
@testable import BlueprintCore

@Suite struct RestorePlanTests {
    static func oldMac() -> Snapshot {
        Fixtures.snapshot(
            apps: [
                Fixtures.app("Visual Studio Code", "com.microsoft.VSCode", .homebrew, cask: "visual-studio-code"),
                Fixtures.app("Spotify", "com.spotify.client", .manual),
                Fixtures.app("Indie Tool", "dev.indie.tool", .manual, version: "2.0"),
                Fixtures.app("Magnet", "id.arunro.magnet", .appStore, appStoreId: 441258766),
                Fixtures.app("Mystery", "dev.mystery", .appStore),
            ],
            homebrew: BrewInventory(
                installed: true,
                taps: ["nikitabobko/tap"],
                formulae: [BrewFormula(name: "git", version: "2.47", onRequest: true), BrewFormula(name: "starship", version: "1", onRequest: true)],
                casks: [BrewCask(token: "visual-studio-code", version: "1", apps: ["Visual Studio Code.app"])]
            ),
            editors: [EditorInventory(editor: .vscode, extensions: [EditorExtension(id: "esbenp.prettier-vscode", version: "11")])],
            tools: [
                DevTool(name: "node", version: "24.13.1", path: "/Users/x/.nvm/versions/node/v24.13.1/bin/node", manager: "nvm"),
                DevTool(name: "git", version: "2.47", path: "/opt/homebrew/bin/git", manager: "homebrew"),
                DevTool(name: "zig", version: "0.13.0", path: "/Users/x/zig/zig", manager: nil),
            ],
            managers: [VersionManager(name: "nvm", installedVersions: ["v24.13.1"]), VersionManager(name: "pyenv", installedVersions: ["3.12.1"])],
            frameworks: ["oh-my-zsh"],
            prompt: "starship",
            architecture: "x86_64"
        )
    }

    static func plan(catalog: CaskCatalog? = nil) -> RestorePlan {
        let newMac = Fixtures.snapshot(developerDirectory: nil)
        return RestorePlan.make(from: SnapshotDiff.compare(base: oldMac(), target: newMac), catalog: catalog)
    }

    @Test func automatesHomebrewAppStoreAndExtensions() {
        let plan = Self.plan()

        #expect(plan.taps == ["nikitabobko/tap"])
        #expect(plan.formulae == ["git", "starship", "mas"], "mas is added because App Store apps are planned")
        #expect(plan.casks.map(\.token) == ["visual-studio-code"], "an app's cask is not listed twice")
        #expect(plan.appStoreApps == [RestorePlan.AppStoreInstall(name: "Magnet", id: 441258766)])
        #expect(plan.extensionCount == 1)
    }

    @Test func leavesHandInstalledAppsToTheUserWithoutACatalog() {
        let manual = Self.plan().manualApps.map(\.name)
        #expect(manual == ["Spotify", "Indie Tool", "Mystery"])
        #expect(Self.plan().manualApps.last?.hint == "Install it from the App Store.")
    }

    @Test func turnsHandInstalledAppsIntoCasksWithACatalog() throws {
        let plan = Self.plan(catalog: try CaskCatalogTests.catalog())

        let spotify = try #require(plan.casks.first { $0.token == "spotify" })
        #expect(spotify.note?.contains("bundle ID") == true)
        #expect(plan.manualApps.map(\.name) == ["Indie Tool", "Mystery"])
        #expect(plan.warnings.contains { $0.contains("installed by hand will now be installed through Homebrew") })
    }

    @Test func describesManualDeveloperSteps() {
        let steps = Self.plan().manualSteps

        #expect(steps.map(\.title) == [
            "Install the Xcode Command Line Tools",
            "Install Node.js with nvm",
            "Install Python with pyenv",
            "Install zig 0.13.0",
            "Set up oh-my-zsh",
        ], "node is covered by nvm, git by Homebrew, and starship is already a formula")
        #expect(steps[1].commands == ["nvm install 24.13.1"])
        #expect(steps[2].commands == ["brew install pyenv", "pyenv install 3.12.1"])
    }

    @Test func warnsAboutArchitectureAndAppStoreSignIn() {
        let warnings = Self.plan().warnings
        #expect(warnings.contains { $0.contains("Intel chip") && $0.contains("Rosetta") })
        #expect(warnings.contains { $0.contains("Sign in to the App Store") })
    }
}

@Suite struct RestoreExporterTests {
    static let source = RestoreSource(
        snapshotLabel: "Old Mac",
        snapshotDate: Date(timeIntervalSince1970: 1_800_000_000),
        generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
        comparedAgainst: "this Mac"
    )

    @Test func writesAValidBrewfile() {
        let brewfile = BrewfileExporter.render(RestorePlanTests.plan(catalog: try? CaskCatalogTests.catalog()), source: Self.source)

        #expect(brewfile.contains("tap \"nikitabobko/tap\"\n"))
        #expect(brewfile.contains("brew \"git\"\n"))
        #expect(brewfile.contains("cask \"spotify\"  # was installed by hand"))
        #expect(brewfile.contains("mas \"Magnet\", id: 441258766\n"))
    }

    @Test func escapesRubyStrings() {
        #expect(BrewfileExporter.ruby(##"He said "hi" #{x} \"##) == ##""He said \"hi\" \#{x} \\""##)
    }

    @Test func quotesShellArguments() {
        #expect(ScriptExporter.shellQuote("it's") == #"'it'\''s'"#)
    }

    @Test func scriptIsValidBashAndDryRunChangesNothing() throws {
        let script = ScriptExporter.render(RestorePlanTests.plan(), source: Self.source)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("macblueprint-script-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("restore.sh")
        try Data(script.utf8).write(to: file)

        let syntax = try bash(["-n", file.path])
        #expect(syntax.status == 0, "bash -n: \(syntax.output)")

        // Homebrew and VS Code may or may not be installed where the tests run
        // (they are on GitHub's runners), and the script then uses their full
        // paths, so only the end of each command is checked.
        let dryRun = try bash([file.path, "--dry-run"], path: "/usr/bin:/bin")
        let commands = dryRun.output.split(separator: "\n").filter { $0.contains("would run:") }
        #expect(dryRun.status == 0, "\(dryRun.output)")
        #expect(commands.contains { $0.hasSuffix("brew bundle --file=Brewfile") }, "\(dryRun.output)")
        #expect(commands.contains { $0.hasSuffix("--install-extension esbenp.prettier-vscode") }, "\(dryRun.output)")
        #expect(!dryRun.output.contains("    $ "), "nothing actually ran")

        let declined = try bash([file.path], path: "/usr/bin:/bin", input: "n\n")
        #expect(declined.output.contains("Nothing was changed."))
    }

    @Test func scriptForAnEmptyPlanExitsEarly() {
        let script = ScriptExporter.render(RestorePlan(), source: Self.source)
        #expect(script.contains("Nothing to install automatically"))
        #expect(!script.contains("brew bundle"))
    }

    @Test func planListsWhatNeedsTheUser() {
        let markdown = PlanExporter.render(RestorePlanTests.plan(), source: Self.source)

        #expect(markdown.contains("From \"Old Mac\""))
        #expect(markdown.contains("## Before you start"))
        #expect(markdown.contains("- [ ] `visual-studio-code`"))
        #expect(markdown.contains("- [ ] **Indie Tool** (v2.0, `dev.indie.tool`)"))
        #expect(markdown.contains("  nvm install 24.13.1"))
        #expect(markdown.contains("Not restored: passwords, SSH keys"))
    }

    private func bash(_ arguments: [String], path: String? = nil, input: String = "") throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = arguments
        if let path { process.environment = ["PATH": path, "HOME": NSTemporaryDirectory()] }
        let output = Pipe()
        let stdin = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = stdin
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
