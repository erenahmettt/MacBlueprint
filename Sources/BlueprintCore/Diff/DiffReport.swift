import Foundation

/// Plain-text rendering of a ``SnapshotDiff`` for the terminal.
public enum DiffReport {
    public static func render(_ diff: SnapshotDiff, baseName: String, targetName: String) -> String {
        var out: [String] = []
        if diff.isEmpty {
            out.append("\(targetName) has everything from \(baseName).")
        } else {
            out.append("\(targetName) is missing \(diff.missingCount) item(s) from \(baseName):")
        }

        func section(_ title: String, _ items: [String]) {
            guard !items.isEmpty else { return }
            out.append("")
            out.append("  \(title) (\(items.count))")
            out += items.map { "    - \($0)" }
        }

        section("Apps", diff.missingApps.map { app in
            let source = switch app.source {
            case .appStore: "App Store"
            case .homebrew: "cask \(app.caskToken ?? "")"
            case .manual: "installed by hand"
            case .system: "built-in"
            }
            return "\(app.name) (\(source))"
        })
        section("Homebrew taps", diff.missingTaps)
        section("Homebrew formulae", diff.missingFormulae.map(\.name))
        section("Homebrew casks", diff.missingCasks.map(\.token))
        for editor in diff.missingExtensions {
            section("\(editor.editor.displayName) extensions", editor.extensions.map(\.id))
        }
        section("Developer tools", diff.missingDevTools.map { "\($0.name) \($0.version ?? "")" + ($0.manager.map { " via \($0)" } ?? "") })
        section("Version managers", diff.missingVersionManagers.map { manager in
            manager.installedVersions.isEmpty ? manager.name : "\(manager.name): \(manager.installedVersions.joined(separator: ", "))"
        })
        var shell = diff.missingShellFrameworks
        if let prompt = diff.missingPrompt { shell.append("\(prompt) prompt") }
        if diff.missingDeveloperTools { shell.append("Xcode Command Line Tools") }
        section("Shell and system", shell)

        if !diff.versionChanges.isEmpty {
            out.append("")
            out.append("  Different versions (\(diff.versionChanges.count))")
            out += diff.versionChanges.map { "    ~ \($0.name): \($0.from) → \($0.to)" }
        }
        if !diff.extraApps.isEmpty {
            out.append("")
            out.append("  Only on \(targetName): \(diff.extraApps.map(\.name).joined(separator: ", "))")
        }
        if let change = diff.architectureChange {
            out.append("")
            out.append("  Architecture changed: \(change.from) → \(change.to)")
        }
        return out.joined(separator: "\n")
    }
}
