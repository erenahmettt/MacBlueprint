import ArgumentParser
import BlueprintCore
import Foundation

@main
struct MacBlueprintCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "macblueprint",
        abstract: "Capture how your Mac is set up, so the next one takes minutes.",
        version: MacBlueprint.version,
        subcommands: [Scan.self, Diff.self, Restore.self, Export.self],
        defaultSubcommand: Scan.self
    )
}

struct Scan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Scan this Mac and write a snapshot.",
        discussion: """
        Reads installed apps, Homebrew packages, editor extensions and developer tools.
        Nothing is installed or changed, nothing leaves your Mac, and credentials
        (~/.ssh, Keychain, .env files, ...) are never read.
        """
    )

    @Option(name: .shortAndLong, help: "Where to write the JSON snapshot. Use '-' for stdout.")
    var output: String?

    @Option(name: .long, help: "A label for this Mac, e.g. \"Work MacBook\".")
    var label: String?

    @Flag(name: .long, help: "Also write a Markdown report next to the JSON file.")
    var markdown = false

    func run() async throws {
        let toStdout = output == "-"
        if !toStdout { log("Scanning this Mac…") }

        let snapshot = await SnapshotBuilder(label: label).build()
        let json = try snapshot.jsonData()

        if toStdout {
            FileHandle.standardOutput.write(json)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        let jsonURL = URL(fileURLWithPath: output ?? Self.defaultFileName(for: snapshot.createdAt))
        try json.write(to: jsonURL, options: .atomic)

        printSummary(snapshot)
        log("\nSnapshot: \(jsonURL.path)")

        if markdown {
            let markdownURL = jsonURL.deletingPathExtension().appendingPathExtension("md")
            try Data(MarkdownExporter.render(snapshot).utf8).write(to: markdownURL, options: .atomic)
            log("Report:   \(markdownURL.path)")
        }
    }

    static func defaultFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "macblueprint-\(formatter.string(from: date)).json"
    }

    private func printSummary(_ s: Snapshot) {
        let apps = s.apps.filter { $0.source != .system }
        let extensions = s.editors.reduce(0) { $0 + $1.extensions.count }
        log("")
        log("  Apps               \(apps.count)  (App Store \(apps.filter { $0.source == .appStore }.count), Homebrew \(apps.filter { $0.source == .homebrew }.count), manual \(apps.filter { $0.source == .manual }.count))")
        if s.homebrew.installed {
            log("  Homebrew           \(s.homebrew.formulae.filter(\.onRequest).count) formulae, \(s.homebrew.casks.count) casks, \(s.homebrew.taps.count) taps")
        } else {
            log("  Homebrew           not installed")
        }
        log("  Editor extensions  \(extensions)  (\(s.editors.map(\.editor.displayName).joined(separator: ", ")))")
        log("  Developer tools    \(s.devEnvironment.tools.map { "\($0.name) \($0.version ?? "?")" }.joined(separator: ", "))")
        if !s.devEnvironment.versionManagers.isEmpty {
            log("  Version managers   \(s.devEnvironment.versionManagers.map(\.name).joined(separator: ", "))")
        }
        if !s.warnings.isEmpty {
            log("\n  \(s.warnings.count) warning(s):")
            s.warnings.forEach { log("    - \($0)") }
        }
    }
}

struct Export: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Render an existing snapshot as a Markdown report.")

    @Argument(help: "Path to a snapshot JSON file.")
    var snapshot: String

    @Option(name: .shortAndLong, help: "Where to write the report. Defaults to stdout.")
    var output: String?

    func run() async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: snapshot))
        let markdown = MarkdownExporter.render(try Snapshot.decode(from: data))
        if let output {
            try Data(markdown.utf8).write(to: URL(fileURLWithPath: output), options: .atomic)
        } else {
            print(markdown)
        }
    }
}

func log(_ message: String) {
    print(message)
}
