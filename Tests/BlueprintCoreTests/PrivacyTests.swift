import Foundation
import Testing
@testable import BlueprintCore

@Suite struct PrivacyTests {
    @Test(arguments: [
        "/Users/tester/.ssh",
        "/Users/tester/.ssh/id_ed25519",
        "/Users/tester/Library/Keychains/login.keychain-db",
        "/Users/tester/.aws/credentials",
        "/Users/tester/.config/gh/hosts.yml",
        "/Users/tester/.netrc",
        "/Users/tester/projects/app/.env",
        "/Users/tester/projects/app/.env.local",
        "/Users/tester/projects/app/.envrc",
        "/Users/tester/./.ssh/../.ssh/config",
        "/Applications/Some iPad App.app/Wrapper/iTunesMetadata.plist",
    ])
    func sensitivePathsAreExcluded(_ path: String) {
        #expect(Exclusions.isExcluded(path, home: "/Users/tester"))
    }

    @Test(arguments: [
        "/Applications/Xcode.app",
        "/Users/tester/.vscode/extensions/extensions.json",
        "/Users/tester/.sshfs-mounts",
        "/Users/tester/.nvm/versions/node",
    ])
    func ordinaryPathsAreAllowed(_ path: String) {
        #expect(!Exclusions.isExcluded(path, home: "/Users/tester"))
    }

    @Test func fileSystemRefusesToReadOrListExcludedPaths() throws {
        let tree = try FixtureTree()
        try tree.write("/Users/tester/.ssh/id_ed25519", "PRIVATE KEY")

        #expect(throws: FileSystemError.excluded("/Users/tester/.ssh/id_ed25519")) {
            try tree.fs.read("/Users/tester/.ssh/id_ed25519")
        }
        #expect(throws: FileSystemError.self) {
            try tree.fs.list("/Users/tester/.ssh")
        }
    }

    @Test func snapshotContainsNoUserOrHostName() async throws {
        let tree = try FixtureTree()
        try tree.makeApp("/Applications/Tool.app", bundleId: "dev.tool")
        let builder = SnapshotBuilder(
            context: tree.context(environment: ["SHELL": "/bin/zsh", "USER": "secretuser"]),
            label: nil,
            machine: MachineInfo(model: "Mac15,6", architecture: "arm64", osVersion: "26.1.0")
        )

        let json = String(decoding: try await builder.build().jsonData(), as: UTF8.self)

        #expect(!json.contains("secretuser"))
        #expect(!json.contains(ProcessInfo.processInfo.hostName))
    }
}
