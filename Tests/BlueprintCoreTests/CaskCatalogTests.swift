import Foundation
import Testing
@testable import BlueprintCore

@Suite struct CaskCatalogTests {
    /// Shapes taken from formulae.brew.sh/api/cask.json.
    static let apiJSON = """
    [
      { "token": "spotify", "deprecated": false, "disabled": false,
        "artifacts": [
          { "uninstall": [{ "launchctl": ["com.spotify.webhelper"], "quit": "com.spotify.client" }] },
          { "app": ["Spotify.app"], "target": "/Applications/Spotify.app" }
        ] },
      { "token": "thorium", "artifacts": [{ "app": ["Thorium.app", { "target": "Thorium Browser.app" }] }] },
      { "token": "zoom",
        "artifacts": [
          { "uninstall": [{ "signal": ["KILL", "us.zoom.xos"], "delete": ["/Applications/zoom.us.app", "/Library/Internet Plug-Ins/ZoomUsPlugIn.plugin"] }] },
          { "pkg": ["zoomusInstallerFull.pkg"] }
        ] },
      { "token": "firefox", "artifacts": [{ "app": ["Firefox.app"] }, { "uninstall": [{ "quit": ["org.mozilla.firefox", "org.mozilla.*"] }] }] },
      { "token": "firefox@beta", "artifacts": [{ "app": ["Firefox.app"] }, { "uninstall": [{ "quit": "org.mozilla.firefox" }] }] },
      { "token": "old-thing", "disabled": true, "artifacts": [{ "app": ["Old.app"] }] },
      { "token": "cli-only", "artifacts": [{ "binary": ["tool"] }] }
    ]
    """

    static func catalog() throws -> CaskCatalog {
        try CaskCatalog.parse(apiResponse: Data(apiJSON.utf8), fetchedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func parsesEveryArtifactShape() throws {
        let entries = Dictionary(uniqueKeysWithValues: try Self.catalog().entries.map { ($0.token, $0) })

        #expect(entries["spotify"]?.apps == ["Spotify.app"])
        #expect(entries["spotify"]?.bundleIds == ["com.spotify.client"])
        #expect(entries["thorium"]?.apps == ["Thorium Browser.app"])
        #expect(entries["zoom"]?.apps == ["zoom.us.app"], "pkg casks are found through uninstall.delete")
        #expect(entries["firefox"]?.bundleIds == ["org.mozilla.firefox"], "wildcards are dropped")
        #expect(entries["old-thing"] == nil, "disabled casks are skipped")
        #expect(entries["cli-only"] == nil, "casks without an app are skipped")
    }

    @Test func prefersBundleIdEvidenceAndPlainTokens() throws {
        let catalog = try Self.catalog()

        let spotify = catalog.match(Fixtures.app("Spotify", "com.spotify.client", .manual))
        #expect(spotify == CaskCatalog.Match(token: "spotify", evidence: .bundleIdAndName))

        let firefox = catalog.match(Fixtures.app("Firefox", "org.mozilla.firefox", .manual))
        #expect(firefox?.token == "firefox", "the plain token beats firefox@beta")

        let renamed = catalog.match(Fixtures.app("Spotify Beta", "com.spotify.client", .manual))
        #expect(renamed == CaskCatalog.Match(token: "spotify", evidence: .bundleId))

        let zoom = catalog.match(AppItem(name: "zoom.us", bundleId: "us.zoom.xos", version: nil, path: "/Applications/zoom.us.app", source: .manual))
        #expect(zoom == CaskCatalog.Match(token: "zoom", evidence: .appName))

        #expect(catalog.match(Fixtures.app("Unknown", "dev.unknown", .manual)) == nil)
    }

    @Test func cachesTheCompactIndex() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("macblueprint-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cacheFile = directory.appendingPathComponent("cask-index.json")
        let fresh = CaskCatalog(fetchedAt: Date(), entries: [CaskCatalog.Entry(token: "spotify", apps: ["Spotify.app"], bundleIds: [])])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(fresh).write(to: cacheFile)

        // A fresh cache is used as-is: no network involved.
        let result = try await CaskCatalogStore(cacheFile: cacheFile).load()

        #expect(!result.downloaded)
        #expect(result.catalog.entries.map(\.token) == ["spotify"])
    }
}
