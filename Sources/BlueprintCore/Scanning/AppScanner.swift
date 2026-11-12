import Foundation

/// Finds application bundles in `/Applications` and `~/Applications`.
///
/// Apps are read from their `Info.plist`. Apps in sub-folders one level deep
/// (`/Applications/Utilities`, `/Applications/DaVinci Resolve/`) are included.
/// Whether an app comes from Homebrew is decided later by ``SnapshotBuilder``,
/// which links apps to the casks that installed them.
public struct AppScanner: Scanner {
    public let id = "apps"

    public init() {}

    public func scan(_ context: ScanContext) async -> [AppItem] {
        let locations = ["/Applications", context.fs.homePath("Applications")]
        var bundles: [String] = []

        for location in locations {
            for entry in list(location, context) {
                let path = location.appendingPath(entry)
                if entry.hasSuffix(".app") {
                    bundles.append(path)
                } else if context.fs.isDirectory(path) {
                    bundles += list(path, context)
                        .filter { $0.hasSuffix(".app") }
                        .map { path.appendingPath($0) }
                }
            }
        }

        var apps: [AppItem] = []
        for bundle in bundles {
            apps.append(await readApp(at: bundle, context))
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func list(_ path: String, _ context: ScanContext) -> [String] {
        do {
            return try context.fs.list(path)
        } catch {
            context.warnings.add(id, "could not list \(path): \(error)")
            return []
        }
    }

    private func readApp(at path: String, _ context: ScanContext) async -> AppItem {
        let fileName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        // iPhone/iPad apps on Apple silicon keep their Info.plist inside a wrapper
        // and can only come from the App Store.
        let isWrappediOSApp = context.fs.exists(path.appendingPath("WrappedBundle"))
        let info = readInfoPlist(path.appendingPath(isWrappediOSApp ? "WrappedBundle/Info.plist" : "Contents/Info.plist"), context)
        let bundleId = info["CFBundleIdentifier"] as? String
        let version = [info["CFBundleShortVersionString"], info["CFBundleVersion"]]
            .compactMap { ($0 as? String).map(Text.trimmed) }
            .first { !$0.isEmpty }

        let source: AppItem.Source
        var appStoreId: Int?
        if isWrappediOSApp || context.fs.exists(path.appendingPath("Contents/_MASReceipt/receipt")) {
            source = .appStore
            appStoreId = await lookUpAppStoreId(path, context)
        } else if bundleId?.hasPrefix("com.apple.") == true {
            source = .system
        } else {
            source = .manual
        }

        return AppItem(
            name: fileName,
            bundleId: bundleId,
            version: version,
            path: path,
            source: source,
            appStoreId: appStoreId
        )
    }

    private func readInfoPlist(_ plistPath: String, _ context: ScanContext) -> [String: Any] {
        guard
            let data = try? context.fs.read(plistPath),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            context.warnings.add(id, "unreadable \(plistPath)")
            return [:]
        }
        return plist
    }

    /// Reads the App Store ID from Spotlight metadata; no network involved.
    private func lookUpAppStoreId(_ appPath: String, _ context: ScanContext) async -> Int? {
        guard let mdls = context.runner.locate("mdls") else { return nil }
        let result = try? await context.runner.run(
            mdls,
            ["-name", "kMDItemAppStoreAdamID", "-raw", context.fs.url(appPath).path],
            timeout: 5
        )
        guard let result, result.succeeded else { return nil }
        return Int(Text.trimmed(result.stdout))
    }
}
