import Foundation
import Testing
@testable import BlueprintCore

/// Builds small snapshots for diff and restore tests.
enum Fixtures {
    static let arm = MachineInfo(model: "Mac15,6", architecture: "arm64", osVersion: "26.1.0")

    static func snapshot(
        apps: [AppItem] = [],
        homebrew: BrewInventory = .notInstalled,
        editors: [EditorInventory] = [],
        developerDirectory: String? = "/Library/Developer/CommandLineTools",
        tools: [DevTool] = [],
        managers: [VersionManager] = [],
        frameworks: [String] = [],
        prompt: String? = nil,
        architecture: String = "arm64"
    ) -> Snapshot {
        Snapshot(
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            label: "Old Mac",
            machine: MachineInfo(model: "Mac15,6", architecture: architecture, osVersion: "26.1.0"),
            apps: apps,
            homebrew: homebrew,
            editors: editors,
            devEnvironment: DevEnvironment(developerDirectory: developerDirectory, tools: tools, versionManagers: managers),
            shell: ShellInfo(loginShell: "/bin/zsh", frameworks: frameworks, prompt: prompt),
            warnings: []
        )
    }

    static func app(_ name: String, _ bundleId: String, _ source: AppItem.Source, version: String = "1.0", appStoreId: Int? = nil, cask: String? = nil) -> AppItem {
        AppItem(name: name, bundleId: bundleId, version: version, path: "/Applications/\(name).app", source: source, appStoreId: appStoreId, caskToken: cask)
    }
}

@Suite struct DiffTests {
    @Test func findsMissingAppsButIgnoresBuiltInOnes() {
        let base = Fixtures.snapshot(apps: [
            Fixtures.app("Safari", "com.apple.Safari", .system),
            Fixtures.app("Raycast", "com.raycast.macos", .manual),
            Fixtures.app("Xcode", "com.apple.dt.Xcode", .appStore, appStoreId: 497799835),
        ])
        let target = Fixtures.snapshot(apps: [
            Fixtures.app("Xcode", "com.apple.dt.Xcode", .appStore, version: "2.0"),
            Fixtures.app("Notion", "notion.id", .manual),
        ])

        let diff = SnapshotDiff.compare(base: base, target: target)

        #expect(diff.missingApps.map(\.name) == ["Raycast"])
        #expect(diff.extraApps.map(\.name) == ["Notion"])
        #expect(diff.versionChanges == [VersionChange(kind: .app, name: "Xcode", from: "1.0", to: "2.0")])
    }

    @Test func comparesHomebrewIgnoringDependenciesAndTapPrefixes() {
        let base = Fixtures.snapshot(homebrew: BrewInventory(
            installed: true,
            taps: ["nikitabobko/tap", "homebrew/services"],
            formulae: [
                BrewFormula(name: "git", version: "2.47", onRequest: true),
                BrewFormula(name: "pcre2", version: "10", onRequest: false),
                BrewFormula(name: "nikitabobko/tap/aerospace", version: "0.15", onRequest: true),
            ],
            casks: [
                BrewCask(token: "visual-studio-code", version: "1", apps: ["Visual Studio Code.app"]),
                BrewCask(token: "spotify", version: "1", apps: ["Spotify.app"]),
            ]
        ))
        let target = Fixtures.snapshot(
            apps: [Fixtures.app("Spotify", "com.spotify.client", .manual)],
            homebrew: BrewInventory(installed: true, taps: ["homebrew/services"], formulae: [BrewFormula(name: "aerospace", version: "0.15", onRequest: true)])
        )

        let diff = SnapshotDiff.compare(base: base, target: target)

        #expect(diff.missingTaps == ["nikitabobko/tap"])
        #expect(diff.missingFormulae.map(\.name) == ["git"], "dependencies are skipped and tap prefixes are ignored")
        #expect(diff.missingCasks.map(\.token) == ["visual-studio-code"], "Spotify is already installed by hand")
    }

    @Test func findsMissingExtensionsPerEditor() {
        let base = Fixtures.snapshot(editors: [
            EditorInventory(editor: .vscode, extensions: [EditorExtension(id: "a.one", version: "1"), EditorExtension(id: "b.two", version: "1")]),
            EditorInventory(editor: .cursor, extensions: [EditorExtension(id: "c.three", version: "1")]),
        ])
        let target = Fixtures.snapshot(editors: [
            EditorInventory(editor: .vscode, extensions: [EditorExtension(id: "a.one", version: "2")]),
        ])

        let diff = SnapshotDiff.compare(base: base, target: target)

        #expect(diff.missingExtensions == [
            EditorInventory(editor: .vscode, extensions: [EditorExtension(id: "b.two", version: "1")]),
            EditorInventory(editor: .cursor, extensions: [EditorExtension(id: "c.three", version: "1")]),
        ])
    }

    @Test func findsMissingDeveloperSetup() {
        let base = Fixtures.snapshot(
            managers: [VersionManager(name: "nvm", installedVersions: ["v20.11.0", "v24.13.1"]), VersionManager(name: "pyenv", installedVersions: ["3.12.1"])],
            frameworks: ["oh-my-zsh"],
            prompt: "starship"
        )
        let target = Fixtures.snapshot(
            developerDirectory: nil,
            managers: [VersionManager(name: "nvm", installedVersions: ["v24.13.1"])]
        )

        let diff = SnapshotDiff.compare(base: base, target: target)

        #expect(diff.missingVersionManagers == [
            VersionManager(name: "nvm", installedVersions: ["v20.11.0"]),
            VersionManager(name: "pyenv", installedVersions: ["3.12.1"]),
        ])
        #expect(diff.missingShellFrameworks == ["oh-my-zsh"])
        #expect(diff.missingPrompt == "starship")
        #expect(diff.missingDeveloperTools)
    }

    @Test func identicalSnapshotsHaveNoDifferences() {
        let snapshot = SnapshotTests.sample()
        let diff = SnapshotDiff.compare(base: snapshot, target: snapshot)
        #expect(diff.isEmpty)
        #expect(diff.missingCount == 0)
        #expect(diff.versionChanges.isEmpty)
        #expect(diff.architectureChange == nil)
    }

    @Test func restoringEverythingMeansComparingWithAnEmptyMac() {
        let snapshot = SnapshotTests.sample()
        let diff = SnapshotDiff.compare(base: snapshot, target: .empty(machine: Fixtures.arm))
        #expect(diff.missingApps.count == 2)
        #expect(diff.missingFormulae.map(\.name) == ["git"])
        #expect(diff.missingDeveloperTools)
    }

    @Test func reportsArchitectureChanges() {
        let diff = SnapshotDiff.compare(base: Fixtures.snapshot(architecture: "x86_64"), target: Fixtures.snapshot())
        #expect(diff.architectureChange == ArchitectureChange(from: "x86_64", to: "arm64"))
    }
}
