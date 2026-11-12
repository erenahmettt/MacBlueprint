import Foundation
import Testing
@testable import BlueprintCore

@Suite struct SnapshotTests {
    static func sample() -> Snapshot {
        Snapshot(
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            label: "Work | MacBook",
            machine: MachineInfo(model: "Mac15,6", architecture: "arm64", osVersion: "26.1.0"),
            apps: [
                AppItem(name: "Xcode", bundleId: "com.apple.dt.Xcode", version: "26.3", path: "/Applications/Xcode.app", source: .appStore, appStoreId: 497799835),
                AppItem(name: "Visual Studio Code", bundleId: "com.microsoft.VSCode", version: "1.95.0", path: "/Applications/Visual Studio Code.app", source: .homebrew, caskToken: "visual-studio-code"),
            ],
            homebrew: BrewInventory(
                installed: true,
                prefix: "/opt/homebrew",
                taps: ["homebrew/services"],
                formulae: [BrewFormula(name: "git", version: "2.47.0", onRequest: true), BrewFormula(name: "pcre2", version: "10.44", onRequest: false)],
                casks: [BrewCask(token: "visual-studio-code", version: "1.95.0", apps: ["Visual Studio Code.app"])]
            ),
            editors: [EditorInventory(editor: .vscode, extensions: [EditorExtension(id: "ms-vscode.cpptools", version: "1.32.2")])],
            devEnvironment: DevEnvironment(
                developerDirectory: "/Applications/Xcode.app/Contents/Developer",
                tools: [DevTool(name: "node", version: "24.13.1", path: "/x/node", manager: "nvm")],
                versionManagers: [VersionManager(name: "nvm", installedVersions: ["v24.13.1"])]
            ),
            shell: ShellInfo(loginShell: "/bin/zsh", frameworks: ["oh-my-zsh"], prompt: "starship"),
            warnings: []
        )
    }

    @Test func roundTripsThroughJSON() throws {
        let snapshot = Self.sample()
        let decoded = try Snapshot.decode(from: snapshot.jsonData())
        #expect(decoded == snapshot)
    }

    @Test func jsonIsDeterministic() throws {
        #expect(try Self.sample().jsonData() == Self.sample().jsonData())
    }

    @Test func rejectsSnapshotsFromTheFuture() throws {
        let json = Data(#"{"schemaVersion": 999}"#.utf8)
        #expect(throws: SnapshotCodingError.self) { try Snapshot.decode(from: json) }
    }

    @Test func markdownReportCoversEverySection() {
        let markdown = MarkdownExporter.render(Self.sample())

        #expect(markdown.contains("# MacBlueprint — Work \\| MacBook"))
        #expect(markdown.contains("| Xcode | 26.3 | appStore (id 497799835) |"))
        #expect(markdown.contains("homebrew (`visual-studio-code`)"))
        #expect(markdown.contains("- `git` 2.47.0"))
        #expect(!markdown.contains("`pcre2`"), "dependencies are summarised, not listed")
        #expect(markdown.contains("## Visual Studio Code extensions"))
        #expect(markdown.contains("| node | 24.13.1 | nvm |"))
        #expect(markdown.contains("- Prompt: starship"))
    }
}
