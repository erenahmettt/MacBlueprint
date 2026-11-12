import BlueprintCore
import Foundation
import Observation

/// Runs the generated restore.sh and streams its output.
///
/// The app runs exactly the same script the CLI writes, so what the user can
/// read in PLAN.md and restore.sh is what actually happens.
@MainActor
@Observable
final class RestoreRunner {
    enum Phase: Equatable {
        case idle
        case running
        case finished(status: Int32)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var output = ""
    private(set) var isDryRun = false
    private var process: Process?

    var isPresented: Bool {
        get { phase != .idle }
        set { if !newValue { reset() } }
    }

    func start(_ plan: RestorePlan, source: RestoreSource, dryRun: Bool) {
        guard phase != .running else { return }
        output = ""
        isDryRun = dryRun

        do {
            let directory = FileManager.default.temporaryDirectory.appending(path: "MacBlueprint-\(UUID().uuidString)", directoryHint: .isDirectory)
            try RestoreFiles.write(plan, source: source, to: directory)

            let process = Process()
            process.executableURL = URL(filePath: "/bin/bash")
            process.arguments = [directory.appending(path: RestoreFiles.script).path, dryRun ? "--dry-run" : "--yes"]
            process.currentDirectoryURL = directory
            var environment = ProcessInfo.processInfo.environment
            // Apps don't inherit the shell's PATH; make Homebrew findable.
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
            environment["NONINTERACTIVE"] = "1"
            environment["HOMEBREW_NO_ENV_HINTS"] = "1"
            process.environment = environment
            process.standardInput = FileHandle.nullDevice

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let reader = pipe.fileHandleForReading
            reader.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let text = String(decoding: data, as: UTF8.self)
                Task { @MainActor in self?.output += text }
            }
            process.terminationHandler = { [weak self] finished in
                let status = finished.terminationStatus
                Task { @MainActor in
                    reader.readabilityHandler = nil
                    if let rest = try? reader.readToEnd(), !rest.isEmpty {
                        self?.output += String(decoding: rest, as: UTF8.self)
                    }
                    self?.phase = .finished(status: status)
                    self?.process = nil
                }
            }

            try process.run()
            self.process = process
            phase = .running
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func stop() {
        process?.terminate()
    }

    func reset() {
        guard phase != .running else { return }
        phase = .idle
        output = ""
    }
}
