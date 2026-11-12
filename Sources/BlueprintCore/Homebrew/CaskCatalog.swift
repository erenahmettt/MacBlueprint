import Foundation

/// A compact index of every Homebrew cask, used to find a cask for apps that
/// were installed by hand ("CapCut.app was dragged in → `cask "capcut"`").
///
/// Built from Homebrew's public API (`formulae.brew.sh/api/cask.json`, ~20 MB)
/// and cached as a small index. Downloading it is the only network request
/// MacBlueprint ever makes, and only when the user asks for cask matching.
public struct CaskCatalog: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var token: String
        public var apps: [String]
        public var bundleIds: [String]
        public var deprecated: Bool

        public init(token: String, apps: [String], bundleIds: [String], deprecated: Bool = false) {
            self.token = token
            self.apps = apps
            self.bundleIds = bundleIds
            self.deprecated = deprecated
        }
    }

    public var fetchedAt: Date
    public var entries: [Entry]

    public init(fetchedAt: Date, entries: [Entry]) {
        self.fetchedAt = fetchedAt
        self.entries = entries
    }

    /// Builds the index from the raw API response. Disabled casks are dropped.
    public static func parse(apiResponse data: Data, fetchedAt: Date = Date()) throws -> CaskCatalog {
        guard let casks = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        let entries: [Entry] = casks.compactMap { cask in
            guard let token = cask["token"] as? String, cask["disabled"] as? Bool != true else { return nil }
            let apps = CaskArtifacts.appNames(cask["artifacts"])
            let bundleIds = CaskArtifacts.bundleIds(cask["artifacts"])
            // Casks that install through a .pkg have no `app` artifact but can
            // still be recognised by the bundle ID they quit on uninstall (zoom).
            guard !apps.isEmpty || !bundleIds.isEmpty else { return nil }
            return Entry(token: token, apps: apps, bundleIds: bundleIds, deprecated: cask["deprecated"] as? Bool ?? false)
        }
        return CaskCatalog(fetchedAt: fetchedAt, entries: entries)
    }

    public struct Match: Codable, Sendable, Equatable {
        public enum Evidence: String, Codable, Sendable {
            /// Same bundle identifier and same .app name. Very reliable.
            case bundleIdAndName
            /// Same bundle identifier, different .app name.
            case bundleId
            /// Same .app name only.
            case appName
        }
        public var token: String
        public var evidence: Evidence
    }

    /// Finds the best cask for an app, or nil. Bundle-ID evidence wins over the
    /// name; ties prefer maintained casks and the plain token over variants
    /// such as `firefox@beta`.
    public func match(_ app: AppItem) -> Match? {
        let fileName = (app.path as NSString).lastPathComponent.lowercased()
        let bundleId = app.bundleId?.lowercased()

        var best: (score: Int, entry: Entry, evidence: Match.Evidence)?
        for entry in entries {
            let nameMatches = entry.apps.contains { $0.lowercased() == fileName }
            let idMatches = bundleId.map { id in entry.bundleIds.contains { $0.lowercased() == id } } ?? false
            let evidence: Match.Evidence
            switch (idMatches, nameMatches) {
            case (true, true): evidence = .bundleIdAndName
            case (true, false): evidence = .bundleId
            case (false, true): evidence = .appName
            case (false, false): continue
            }

            var score = [Match.Evidence.bundleIdAndName: 300, .bundleId: 200, .appName: 100][evidence]!
            if !entry.deprecated { score += 20 }
            if !entry.token.contains("@") { score += 10 }
            score -= min(entry.token.count, 9)

            if best == nil || score > best!.score {
                best = (score, entry, evidence)
            }
        }
        return best.map { Match(token: $0.entry.token, evidence: $0.evidence) }
    }
}

/// Downloads and caches the cask catalog.
public struct CaskCatalogStore: Sendable {
    public static let sourceURL = URL(string: "https://formulae.brew.sh/api/cask.json")!

    public var cacheFile: URL
    public var maxAge: TimeInterval

    public init(
        cacheFile: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacBlueprint/cask-index.json"),
        maxAge: TimeInterval = 7 * 24 * 60 * 60
    ) {
        self.cacheFile = cacheFile
        self.maxAge = maxAge
    }

    /// Returns the cached catalog when it is fresh, otherwise downloads a new one.
    public func load(forceRefresh: Bool = false) async throws -> (catalog: CaskCatalog, downloaded: Bool) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if !forceRefresh,
           let data = try? Data(contentsOf: cacheFile),
           let cached = try? decoder.decode(CaskCatalog.self, from: data),
           Date().timeIntervalSince(cached.fetchedAt) < maxAge {
            return (cached, false)
        }

        let (data, response) = try await URLSession(configuration: .ephemeral).data(from: Self.sourceURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        let catalog = try CaskCatalog.parse(apiResponse: data)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(catalog).write(to: cacheFile, options: .atomic)
        return (catalog, true)
    }
}
