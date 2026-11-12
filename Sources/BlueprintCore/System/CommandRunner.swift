import Foundation

public struct CommandResult: Sendable, Equatable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var timedOut: Bool

    public init(exitCode: Int32, stdout: String, stderr: String = "", timedOut: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }

    public var succeeded: Bool { exitCode == 0 && !timedOut }
    /// stdout followed by stderr; some tools (java) print their version to stderr.
    public var combinedOutput: String { stdout + stderr }
}

/// Runs external programs. Abstracted so scanners can be tested with canned output.
public protocol CommandRunning: Sendable {
    /// Absolute path of an executable, or nil when it is not installed.
    func locate(_ name: String) -> String?
    func run(_ executable: String, _ arguments: [String], environment: [String: String], timeout: TimeInterval) async throws -> CommandResult
}

extension CommandRunning {
    public func run(_ executable: String, _ arguments: [String] = [], timeout: TimeInterval = 10) async throws -> CommandResult {
        try await run(executable, arguments, environment: [:], timeout: timeout)
    }
}

/// Real implementation backed by `Process`.
public struct ProcessRunner: CommandRunning {
    /// Directories searched before `$PATH`. GUI apps do not inherit the user's
    /// shell PATH, so common install locations are listed explicitly.
    public let searchDirectories: [String]

    public init(home: String = NSHomeDirectory(), environmentPath: String? = ProcessInfo.processInfo.environment["PATH"]) {
        let preferred = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "\(home)/.volta/bin",
            "\(home)/.cargo/bin",
            "\(home)/.bun/bin",
            "\(home)/.deno/bin",
            "\(home)/.local/bin",
        ]
        let fromEnvironment = (environmentPath ?? "")
            .split(separator: ":")
            .map(String.init)
            .map { $0.replacingOccurrences(of: "~", with: home) }
        let fallback = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]

        var seen = Set<String>()
        self.searchDirectories = (preferred + fromEnvironment + fallback).filter { seen.insert($0).inserted }
    }

    public func locate(_ name: String) -> String? {
        if name.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }
        for directory in searchDirectories {
            let candidate = (directory as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    public func run(_ executable: String, _ arguments: [String], environment: [String: String], timeout: TimeInterval) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try Self.runBlocking(executable, arguments, environment: environment, timeout: timeout))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runBlocking(_ executable: String, _ arguments: [String], environment: [String: String], timeout: TimeInterval) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Drain both pipes while the process runs; large outputs (brew JSON)
        // would otherwise fill the pipe buffer and deadlock.
        let output = OutputBuffer()
        let readers = DispatchGroup()
        for (pipe, isStdout) in [(stdoutPipe, true), (stderrPipe, false)] {
            readers.enter()
            DispatchQueue.global().async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                output.set(data, stdout: isStdout)
                readers.leave()
            }
        }

        let watchdog = DispatchWorkItem {
            if process.isRunning {
                output.markTimedOut()
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        process.waitUntilExit()
        watchdog.cancel()
        _ = readers.wait(timeout: .now() + 5)

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: output.stdoutString,
            stderr: output.stderrString,
            timedOut: output.timedOut
        )
    }
}

/// Collects pipe output from background readers.
private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var didTimeOut = false

    func set(_ data: Data, stdout isStdout: Bool) {
        lock.withLock {
            if isStdout { stdout = data } else { stderr = data }
        }
    }

    func markTimedOut() { lock.withLock { didTimeOut = true } }

    var stdoutString: String { lock.withLock { String(decoding: stdout, as: UTF8.self) } }
    var stderrString: String { lock.withLock { String(decoding: stderr, as: UTF8.self) } }
    var timedOut: Bool { lock.withLock { didTimeOut } }
}
