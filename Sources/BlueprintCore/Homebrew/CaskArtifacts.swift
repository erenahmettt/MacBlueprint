import Foundation

/// Reads the loosely-typed `artifacts` array Homebrew uses for casks.
///
/// Two shapes exist for the `app` artifact:
/// - `{"app": ["Foo.app"], "target": "/Applications/Foo.app"}`: the API adds
///   the final install path next to the list.
/// - `{"app": ["Foo.app", {"target": "Bar.app"}]}`: the DSL form, where a
///   `target` dictionary renames the app right before it.
enum CaskArtifacts {
    /// Names of the `.app` bundles a cask installs, as they appear on disk.
    ///
    /// Casks that use a `.pkg` installer have no `app` artifact; their app is
    /// then found in `uninstall: delete: "/Applications/zoom.us.app"`.
    static func appNames(_ artifacts: Any?) -> [String] {
        guard let artifacts = artifacts as? [[String: Any]] else { return [] }
        let fromApp = appArtifactNames(artifacts)
        return fromApp.isEmpty ? pkgDeletedApps(artifacts) : fromApp
    }

    private static func pkgDeletedApps(_ artifacts: [[String: Any]]) -> [String] {
        var names: [String] = []
        for artifact in artifacts {
            guard let steps = artifact["uninstall"] as? [Any] else { continue }
            for case let step as [String: Any] in steps {
                let paths: [String] = switch step["delete"] {
                case let path as String: [path]
                case let list as [String]: list
                default: []
                }
                for path in paths where path.hasPrefix("/Applications/") && path.hasSuffix(".app") && !path.contains("*") {
                    // Only apps directly in /Applications, not helpers in sub-folders.
                    if (path as NSString).deletingLastPathComponent == "/Applications" {
                        names.append((path as NSString).lastPathComponent)
                    }
                }
            }
        }
        return names
    }

    private static func appArtifactNames(_ artifacts: [[String: Any]]) -> [String] {
        var names: [String] = []
        for artifact in artifacts {
            guard let entries = artifact["app"] as? [Any] else { continue }
            if let target = artifact["target"] as? String {
                names.append((target as NSString).lastPathComponent)
                continue
            }
            var current: String?
            for entry in entries {
                if let name = entry as? String {
                    if let current { names.append(current) }
                    current = name
                } else if let options = entry as? [String: Any], let target = options["target"] as? String {
                    current = target
                }
            }
            if let current { names.append(current) }
        }
        return names.map { ($0 as NSString).lastPathComponent }
    }

    /// Bundle identifiers listed under `uninstall: quit:`, which Homebrew uses
    /// to close the app before removing it. A reliable way to recognise an app.
    static func bundleIds(_ artifacts: Any?) -> [String] {
        guard let artifacts = artifacts as? [[String: Any]] else { return [] }
        var ids: [String] = []
        for artifact in artifacts {
            guard let steps = artifact["uninstall"] as? [Any] else { continue }
            for case let step as [String: Any] in steps {
                switch step["quit"] {
                case let id as String: ids.append(id)
                case let list as [String]: ids.append(contentsOf: list)
                default: break
                }
            }
        }
        return ids.filter { !$0.contains("*") }
    }
}
