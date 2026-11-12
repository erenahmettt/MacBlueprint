import Foundation

/// A source of facts about the Mac: apps, Homebrew, editors, ...
///
/// Scanners are read-only and must never throw: when something is missing or
/// fails they return an empty result and record a warning, so one broken tool
/// never prevents a snapshot from being written.
///
/// Adding a new scanner is the easiest way to contribute: implement this
/// protocol, add a field to ``Snapshot``, and call it from ``SnapshotBuilder``.
public protocol Scanner: Sendable {
    associatedtype Output: Sendable
    /// Short identifier used in warnings ("apps", "homebrew", ...).
    var id: String { get }
    func scan(_ context: ScanContext) async -> Output
}

/// Everything a scanner is allowed to touch.
public struct ScanContext: Sendable {
    public let fs: FileSystem
    public let runner: any CommandRunning
    public let environment: [String: String]
    public let warnings: WarningLog

    public init(fs: FileSystem, runner: any CommandRunning, environment: [String: String] = [:], warnings: WarningLog = WarningLog()) {
        self.fs = fs
        self.runner = runner
        self.environment = environment
        self.warnings = warnings
    }

    /// Context for scanning the Mac this process runs on.
    public static func live() -> ScanContext {
        let home = NSHomeDirectory()
        return ScanContext(
            fs: FileSystem(home: home),
            runner: ProcessRunner(home: home),
            environment: ProcessInfo.processInfo.environment
        )
    }

    public var home: String { fs.home }
}

/// Thread-safe collector for non-fatal scan problems.
public final class WarningLog: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []

    public init() {}

    public func add(_ scanner: String, _ message: String) {
        lock.withLock { messages.append("\(scanner): \(message)") }
    }

    public var all: [String] { lock.withLock { messages.sorted() } }
}

// MARK: - Small helpers shared by scanners

enum Text {
    /// First capture group of `pattern` in `text`, or the whole match when the pattern has no group.
    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        let group = match.numberOfRanges > 1 ? 1 : 0
        guard let swiftRange = Range(match.range(at: group), in: text) else { return nil }
        return String(text[swiftRange])
    }

    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension String {
    func appendingPath(_ component: String) -> String {
        (self as NSString).appendingPathComponent(component)
    }
}
