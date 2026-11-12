import Foundation
import Testing
@testable import BlueprintCore

@Suite struct AppScannerTests {
    @Test func classifiesAppsBySource() async throws {
        let tree = try FixtureTree()
        try tree.makeApp("/Applications/Xcode.app", bundleId: "com.apple.dt.Xcode", version: "26.3", appStore: true)
        try tree.makeApp("/Applications/Safari.app", bundleId: "com.apple.Safari")
        try tree.makeApp("/Applications/Spotify.app", bundleId: "com.spotify.client", version: "1.2.3")

        let runner = MockRunner(installed: ["mdls": "/usr/bin/mdls"]) { exe, _ in
            exe == "/usr/bin/mdls" ? CommandResult(exitCode: 0, stdout: "497799835\n") : nil
        }
        let apps = await AppScanner().scan(tree.context(runner: runner))

        #expect(apps.map(\.name) == ["Safari", "Spotify", "Xcode"])
        let xcode = try #require(apps.first { $0.name == "Xcode" })
        #expect(xcode.source == .appStore)
        #expect(xcode.appStoreId == 497799835)
        #expect(xcode.version == "26.3")
        #expect(apps.first { $0.name == "Safari" }?.source == .system)
        #expect(apps.first { $0.name == "Spotify" }?.source == .manual)
    }

    @Test func findsAppsOneFolderDeepAndInHome() async throws {
        let tree = try FixtureTree()
        try tree.makeApp("/Applications/Utilities/Terminal Helper.app", bundleId: "dev.example.helper")
        try tree.makeApp("/Applications/DaVinci Resolve/DaVinci Resolve.app", bundleId: "com.blackmagic-design.DaVinciResolve")
        try tree.makeApp("/Users/tester/Applications/Personal.app", bundleId: "dev.example.personal")

        let apps = await AppScanner().scan(tree.context())

        #expect(Set(apps.map(\.name)) == ["Terminal Helper", "DaVinci Resolve", "Personal"])
    }

    @Test func readsWrappediOSAppsAsAppStoreApps() async throws {
        let tree = try FixtureTree()
        // Layout of an iPad app installed on Apple silicon.
        try tree.makeApp("/Applications/Notes Pro.app/Wrapper/Notes Pro.app", bundleId: "com.example.notespro", version: "3.1")
        let info = tree.fs.url("/Applications/Notes Pro.app/Wrapper/Notes Pro.app/Contents/Info.plist")
        try FileManager.default.moveItem(at: info, to: info.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist"))
        try FileManager.default.createSymbolicLink(
            atPath: tree.fs.url("/Applications/Notes Pro.app/WrappedBundle").path,
            withDestinationPath: "Wrapper/Notes Pro.app"
        )

        let apps = await AppScanner().scan(tree.context())

        #expect(apps == [AppItem(name: "Notes Pro", bundleId: "com.example.notespro", version: "3.1", path: "/Applications/Notes Pro.app", source: .appStore)])
    }

    @Test func treatsBlankVersionsAsMissing() async throws {
        let tree = try FixtureTree()
        try tree.makeApp("/Applications/Blank.app", bundleId: "dev.blank", version: "  ")
        #expect(await AppScanner().scan(tree.context()).first?.version == nil)
    }

    @Test func keepsAppsWithBrokenInfoPlistAndWarns() async throws {
        let tree = try FixtureTree()
        try tree.write("/Applications/Broken.app/Contents/Info.plist", "not a plist")
        let context = tree.context()

        let apps = await AppScanner().scan(context)

        #expect(apps.count == 1)
        #expect(apps[0].bundleId == nil)
        #expect(context.warnings.all.contains { $0.contains("Broken.app") })
    }
}
