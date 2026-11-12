import Foundation

/// Reads installed Homebrew formulae, casks and taps.
///
/// Uses `brew info --json=v2 --installed`, which is fast and works offline.
/// Auto-update and analytics are switched off for every call.
public struct BrewScanner: Scanner {
    public let id = "homebrew"

    static let environment = [
        "HOMEBREW_NO_AUTO_UPDATE": "1",
        "HOMEBREW_NO_ANALYTICS": "1",
        "HOMEBREW_NO_ENV_HINTS": "1",
    ]

    public init() {}

    public func scan(_ context: ScanContext) async -> BrewInventory {
        guard let brew = context.runner.locate("brew") else {
            context.warnings.add(id, "not installed")
            return .notInstalled
        }

        async let infoResult = context.runner.run(brew, ["info", "--json=v2", "--installed"], environment: Self.environment, timeout: 120)
        async let tapResult = context.runner.run(brew, ["tap"], environment: Self.environment, timeout: 30)

        var inventory = BrewInventory(installed: true, prefix: Self.prefix(forBrewAt: brew))

        do {
            let info = try await infoResult
            guard info.succeeded else {
                context.warnings.add(id, "`brew info` failed: \(Text.trimmed(info.stderr))")
                return inventory
            }
            let parsed = try Self.parseInfo(Data(info.stdout.utf8))
            inventory.formulae = parsed.formulae
            inventory.casks = parsed.casks
        } catch {
            context.warnings.add(id, "could not read `brew info`: \(error)")
        }

        if let taps = try? await tapResult, taps.succeeded {
            inventory.taps = taps.stdout
                .split(separator: "\n")
                .map { Text.trimmed(String($0)) }
                .filter { !$0.isEmpty }
                .sorted()
        }

        return inventory
    }

    static func prefix(forBrewAt path: String) -> String {
        // <prefix>/bin/brew
        ((path as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
    }

    /// Parses `brew info --json=v2` output. Uses loose JSON handling on purpose:
    /// Homebrew adds fields over time and casks' `artifacts` mix many shapes.
    static func parseInfo(_ data: Data) throws -> (formulae: [BrewFormula], casks: [BrewCask]) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }

        let formulae: [BrewFormula] = (root["formulae"] as? [[String: Any]] ?? []).compactMap { formula in
            guard let name = (formula["full_name"] as? String) ?? (formula["name"] as? String) else { return nil }
            let installed = (formula["installed"] as? [[String: Any]])?.last
            return BrewFormula(
                name: name,
                version: installed?["version"] as? String,
                onRequest: installed?["installed_on_request"] as? Bool ?? true
            )
        }

        let casks: [BrewCask] = (root["casks"] as? [[String: Any]] ?? []).compactMap { cask in
            guard let token = (cask["full_token"] as? String) ?? (cask["token"] as? String) else { return nil }
            return BrewCask(
                token: token,
                version: cask["installed"] as? String,
                apps: CaskArtifacts.appNames(cask["artifacts"])
            )
        }

        return (formulae.sorted { $0.name < $1.name }, casks.sorted { $0.token < $1.token })
    }
}
