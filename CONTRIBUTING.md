# Contributing to MacBlueprint

Thanks for helping! Bug reports, scanner ideas and pull requests are all welcome.

## Getting started

```bash
git clone https://github.com/erenahmettt/MacBlueprint.git
cd MacBlueprint
swift build
swift test
swift run macblueprint scan --markdown -o /tmp/me.json
```

You need macOS 14+ and Swift 6 (Xcode 16+). There's nothing else to install.

## Project layout

```
Sources/BlueprintCore/
  Model/       Snapshot and its item types (the JSON schema)
  Scanning/    One file per scanner + SnapshotBuilder
  Diff/        SnapshotDiff (what one Mac has that another lacks) and its text report
  Restore/     RestorePlan and the Brewfile / restore.sh / PLAN.md exporters
  Homebrew/    Cask artifact parsing and the cask catalog used by --match-casks
  System/      FileSystem (sandboxable, enforces exclusions) and CommandRunner
  Privacy/     Paths that must never be read
  Export/      JSON coding and the Markdown report
Sources/macblueprint/   CLI (swift-argument-parser)
Tests/BlueprintCoreTests/
App/
  MacBlueprint.xcodeproj  The SwiftUI app; uses BlueprintCore as a local package
  MacBlueprint/
    Model/     AppModel (app state), SnapshotLibrary (saved snapshots), RestoreRunner
    Views/     Overview, Compare, Restore and shared components
```

The app project uses folder references, so new files in `App/MacBlueprint/` are picked up without editing the project. Keep logic in `BlueprintCore`, where it can be tested, and keep the app to presentation and state.

Build the app from the command line the same way CI does:

```bash
xcodebuild -project App/MacBlueprint.xcodeproj -scheme MacBlueprint CODE_SIGNING_ALLOWED=NO build
```

## Adding a scanner

Scanners are the easiest way to contribute.

1. Create `Sources/BlueprintCore/Scanning/<Name>Scanner.swift` and implement `Scanner`:
   ```swift
   public struct NpmGlobalScanner: Scanner {
       public let id = "npm"
       public func scan(_ context: ScanContext) async -> [NpmPackage] { … }
   }
   ```
2. **Only use `context.fs` and `context.runner`**, never `FileManager` or `Process` directly. That's what keeps scanners testable and the privacy exclusions in force.
3. **Never throw and never crash.** If a tool is missing, return an empty result and call `context.warnings.add(id, "…")`.
4. Add the result to `Snapshot` as an optional or defaulted field, so older snapshots keep decoding.
5. Call the scanner from `SnapshotBuilder.build()` and add a section to `MarkdownExporter`.
6. Add tests using `FixtureTree` (a fake `/`) and `MockRunner` (canned command output). See `DevToolScannerTests` for an example.

### Rules for scanners

- **Read only.** A scanner never installs, writes or changes anything.
- **No secrets.** If a source could hold credentials, leave it out, or add it to `Exclusions` and talk to us in an issue first.
- **No network.** (The only exception is the opt-in cask catalog in `Homebrew/`.)
- **No surprise dialogs.** Some `/usr/bin` tools are stubs that open install prompts. See how `DevToolScanner` guards against this.
- **Deterministic output.** Sort lists so snapshots diff cleanly.

## Changing restore.sh

`ScriptExporter` generates bash that must run on the bash 3.2 that ships with macOS. Keep these rules:

- Every command goes through `run`, so `--dry-run` covers it.
- Quote values with `shellQuote`, never with plain string interpolation.
- A failed step is recorded and the script continues.
- `RestoreExporterTests` runs the generated script with `bash -n` and `--dry-run`. Extend it when you add a section.

## Pull requests

- Keep PRs focused, one scanner or one fix at a time.
- `swift build` must produce no warnings, and `swift test` must pass.
- Use [Conventional Commits](https://www.conventionalcommits.org/) for messages (`feat: add npm global scanner`, `fix: …`).
