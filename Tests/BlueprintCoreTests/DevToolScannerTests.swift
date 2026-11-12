import Testing
@testable import BlueprintCore

@Suite struct DevToolScannerTests {
    @Test func parsesVersionsAndInstallSources() async throws {
        let tree = try FixtureTree()
        let runner = MockRunner(installed: [
            "node": "/Users/tester/.nvm/versions/node/v24.13.1/bin/node",
            "swift": "/usr/bin/swift",
            "go": "/opt/homebrew/bin/go",
        ]) { exe, _ in
            switch exe {
            case "/usr/bin/xcode-select": CommandResult(exitCode: 0, stdout: "/Applications/Xcode.app/Contents/Developer\n")
            case let path where path.hasSuffix("/node"): CommandResult(exitCode: 0, stdout: "v24.13.1\n")
            case "/usr/bin/swift": CommandResult(exitCode: 0, stdout: "swift-driver version: 1.127.15 Apple Swift version 6.2.4 (swiftlang-6.2.4.1.4)\n")
            case "/opt/homebrew/bin/go": CommandResult(exitCode: 0, stdout: "go version go1.23.4 darwin/arm64\n")
            default: nil
            }
        }

        let env = await DevToolScanner().scan(tree.context(runner: runner))

        #expect(env.developerDirectory == "/Applications/Xcode.app/Contents/Developer")
        #expect(env.tools.map(\.name) == ["go", "node", "swift"])
        #expect(env.tools.map(\.version) == ["1.23.4", "24.13.1", "6.2.4"])
        #expect(env.tools.map(\.manager) == ["homebrew", "nvm", "system"])
    }

    @Test func neverRunsDeveloperToolStubsWithoutXcode() async throws {
        let tree = try FixtureTree()
        let runner = MockRunner(installed: [
            "git": "/usr/bin/git",
            "python3": "/usr/bin/python3",
            "java": "/usr/bin/java",
        ])

        let env = await DevToolScanner().scan(tree.context(runner: runner))

        #expect(env.developerDirectory == nil)
        #expect(env.tools.isEmpty)
        // Only the safe probes ran; the stubs that would pop up install dialogs did not.
        #expect(Set(runner.executedPaths) == ["/usr/bin/xcode-select", "/usr/libexec/java_home"])
    }

    @Test func listsVersionManagersAndTheirVersions() async throws {
        let tree = try FixtureTree()
        try tree.mkdir("/Users/tester/.nvm/versions/node/v24.13.1")
        try tree.mkdir("/Users/tester/.nvm/versions/node/v9.0.0")
        try tree.mkdir("/Users/tester/.asdf/installs/python/3.12.1")
        try tree.mkdir("/Users/tester/.asdf/installs/ruby/3.3.0")

        let env = await DevToolScanner().scan(tree.context())

        #expect(env.versionManagers == [
            VersionManager(name: "nvm", installedVersions: ["v9.0.0", "v24.13.1"]),
            VersionManager(name: "asdf", installedVersions: ["python@3.12.1", "ruby@3.3.0"]),
        ])
    }
}
