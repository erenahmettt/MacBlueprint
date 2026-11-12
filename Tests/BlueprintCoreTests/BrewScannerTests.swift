import Foundation
import Testing
@testable import BlueprintCore

@Suite struct BrewScannerTests {
    /// Trimmed-down real output of `brew info --json=v2 --installed`.
    static let infoJSON = """
    {
      "formulae": [
        {
          "name": "git", "full_name": "git", "tap": "homebrew/core",
          "installed": [{ "version": "2.47.0", "installed_on_request": true, "installed_as_dependency": false }]
        },
        {
          "name": "pcre2", "full_name": "pcre2", "tap": "homebrew/core",
          "installed": [{ "version": "10.44", "installed_on_request": false, "installed_as_dependency": true }]
        },
        {
          "name": "aerospace", "full_name": "nikitabobko/tap/aerospace", "tap": "nikitabobko/tap",
          "installed": [{ "version": "0.15.2", "installed_on_request": true }]
        }
      ],
      "casks": [
        {
          "token": "visual-studio-code", "full_token": "visual-studio-code", "installed": "1.95.0",
          "artifacts": [
            { "app": ["Visual Studio Code.app"] },
            { "binary": ["$APPDIR/Visual Studio Code.app/Contents/Resources/app/bin/code"] },
            { "zap": [{ "trash": ["~/.vscode"] }] }
          ]
        },
        {
          "token": "renamed", "full_token": "renamed", "installed": "2.0",
          "artifacts": [{ "app": ["Original.app", { "target": "Renamed.app" }] }]
        }
      ]
    }
    """

    @Test func parsesFormulaeCasksAndTaps() async throws {
        let tree = try FixtureTree()
        let runner = MockRunner(installed: ["brew": "/opt/homebrew/bin/brew"]) { _, args in
            switch args.first {
            case "info": CommandResult(exitCode: 0, stdout: Self.infoJSON)
            case "tap": CommandResult(exitCode: 0, stdout: "nikitabobko/tap\nhomebrew/services\n")
            default: nil
            }
        }

        let brew = await BrewScanner().scan(tree.context(runner: runner))

        #expect(brew.installed)
        #expect(brew.prefix == "/opt/homebrew")
        #expect(brew.taps == ["homebrew/services", "nikitabobko/tap"])
        #expect(brew.formulae.map(\.name) == ["git", "nikitabobko/tap/aerospace", "pcre2"])
        #expect(brew.formulae.first { $0.name == "pcre2" }?.onRequest == false)
        #expect(brew.casks.first { $0.token == "visual-studio-code" }?.apps == ["Visual Studio Code.app"])
        #expect(brew.casks.first { $0.token == "renamed" }?.apps == ["Renamed.app"])
    }

    @Test func reportsMissingHomebrewWithoutFailing() async throws {
        let tree = try FixtureTree()
        let context = tree.context()

        let brew = await BrewScanner().scan(context)

        #expect(brew == .notInstalled)
        #expect(context.warnings.all == ["homebrew: not installed"])
    }

    @Test func linksAppsToTheirCasks() {
        let apps = [
            AppItem(name: "Visual Studio Code", bundleId: "com.microsoft.VSCode", version: nil, path: "/Applications/Visual Studio Code.app", source: .manual),
            AppItem(name: "Keynote", bundleId: "com.apple.iWork.Keynote", version: nil, path: "/Applications/Keynote.app", source: .appStore),
            AppItem(name: "Other", bundleId: "dev.other", version: nil, path: "/Applications/Other.app", source: .manual),
        ]
        let casks = [
            BrewCask(token: "visual-studio-code", version: "1.95.0", apps: ["Visual Studio Code.app"]),
            BrewCask(token: "keynote-lookalike", version: "1", apps: ["Keynote.app"]),
        ]

        let linked = SnapshotBuilder.link(apps, to: casks)

        #expect(linked[0].source == .homebrew)
        #expect(linked[0].caskToken == "visual-studio-code")
        #expect(linked[1].source == .appStore, "App Store apps keep their source")
        #expect(linked[2].source == .manual)
    }
}
