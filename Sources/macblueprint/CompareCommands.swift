import ArgumentParser
import BlueprintCore
import Foundation

/// Loads the snapshot to compare against: a file, a live scan of this Mac, or nothing.
enum Target {
    case file(String)
    case thisMac
    case empty

    static func from(path: String?, everything: Bool = false) -> Target {
        if everything { return .empty }
        return path.map(Target.file) ?? .thisMac
    }

    var displayName: String {
        switch self {
        case .file(let path): (path as NSString).lastPathComponent
        case .thisMac: "this Mac"
        case .empty: "an empty Mac"
        }
    }

    func load() async throws -> Snapshot {
        switch self {
        case .file(let path):
            return try loadSnapshot(path)
        case .thisMac:
            log("Scanning this Mac…")
            return await SnapshotBuilder().build()
        case .empty:
            return .empty(machine: MachineInfo.current())
        }
    }
}

func loadSnapshot(_ path: String) throws -> Snapshot {
    let url = URL(fileURLWithPath: path)
    do {
        return try Snapshot.decode(from: Data(contentsOf: url))
    } catch let error as SnapshotCodingError {
        throw ValidationError("\(path): \(error)")
    } catch {
        throw ValidationError("\(path) is not a MacBlueprint snapshot (\(error.localizedDescription))")
    }
}

struct Diff: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show what one Mac has that another is missing.",
        discussion: """
        Compares a snapshot of your old Mac with this Mac (or with a second snapshot).
        Examples:
          macblueprint diff old-mac.json
          macblueprint diff old-mac.json new-mac.json --json
        """
    )

    @Argument(help: "Snapshot of the Mac you want to reproduce.")
    var base: String

    @Argument(help: "Snapshot to compare with. Defaults to a live scan of this Mac.")
    var target: String?

    @Flag(name: .long, help: "Print the diff as JSON.")
    var json = false

    func run() async throws {
        let baseSnapshot = try loadSnapshot(base)
        let targetSource = Target.from(path: target)
        let targetSnapshot = try await targetSource.load()
        let diff = SnapshotDiff.compare(base: baseSnapshot, target: targetSnapshot)

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            FileHandle.standardOutput.write(try encoder.encode(diff))
            FileHandle.standardOutput.write(Data("\n".utf8))
        } else {
            let baseName = baseSnapshot.label.map { "\"\($0)\"" } ?? (base as NSString).lastPathComponent
            print(DiffReport.render(diff, baseName: baseName, targetName: targetSource.displayName))
            if !diff.isEmpty {
                print("\nNext: macblueprint restore \(base)\(target.map { " --against \($0)" } ?? "")")
            }
        }
    }
}

struct Restore: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Write a reviewable plan to install what this Mac is missing.",
        discussion: """
        Writes three files and runs nothing:
          Brewfile    Homebrew taps, formulae, casks and App Store apps
          restore.sh  installs the above and your editor extensions (supports --dry-run)
          PLAN.md     a checklist, including the steps that need you

        Examples:
          macblueprint restore old-mac.json
          macblueprint restore old-mac.json --match-casks -o ~/Desktop/restore
          macblueprint restore old-mac.json --everything
        """
    )

    @Argument(help: "Snapshot of the Mac you want to reproduce.")
    var snapshot: String

    @Option(name: .long, help: "Compare with this snapshot instead of scanning this Mac.")
    var against: String?

    @Flag(name: .long, help: "Plan everything in the snapshot, ignoring what this Mac already has.")
    var everything = false

    @Flag(name: .long, help: "Look up Homebrew casks for apps you installed by hand. Downloads Homebrew's public cask list (cached for a week).")
    var matchCasks = false

    @Flag(name: .long, help: "With --match-casks, download a fresh cask list even if the cached one is recent.")
    var refreshCasks = false

    @Option(name: .shortAndLong, help: "Directory to write the files to.")
    var output = "macblueprint-restore"

    func validate() throws {
        if everything && against != nil {
            throw ValidationError("Use either --against or --everything, not both.")
        }
    }

    func run() async throws {
        let base = try loadSnapshot(snapshot)
        let targetSource = Target.from(path: against, everything: everything)
        let target = try await targetSource.load()
        let diff = SnapshotDiff.compare(base: base, target: target)

        var catalog: CaskCatalog?
        if matchCasks {
            log("Loading the Homebrew cask list…")
            do {
                let result = try await CaskCatalogStore().load(forceRefresh: refreshCasks)
                catalog = result.catalog
                log(result.downloaded ? "  downloaded \(result.catalog.entries.count) casks" : "  using cached list (\(result.catalog.entries.count) casks)")
            } catch {
                log("  could not load the cask list (\(error.localizedDescription)); continuing without cask matching")
            }
        }

        let plan = RestorePlan.make(from: diff, catalog: catalog)
        let source = RestoreSource(snapshotLabel: base.label, snapshotDate: base.createdAt, comparedAgainst: targetSource.displayName)

        let directory = try RestoreFiles.write(plan, source: source, to: URL(fileURLWithPath: output, isDirectory: true))

        log("")
        if plan.isEmpty {
            log("Nothing to restore: \(targetSource.displayName) already has everything.")
            return
        }
        log("  Automated  \(plan.automatedCount)  (\(plan.formulae.count) formulae, \(plan.casks.count) casks, \(plan.appStoreApps.count) App Store apps, \(plan.extensionCount) extensions)")
        log("  Needs you  \(plan.manualApps.count + plan.manualSteps.count)")
        if !matchCasks && plan.manualApps.count > 0 {
            log("\n  Tip: --match-casks finds Homebrew casks for apps you installed by hand.")
        }
        log("""

        Wrote \(directory.path)/
          PLAN.md      read this first
          Brewfile
          restore.sh   then run: \(output)/restore.sh --dry-run
        """)
    }
}
