import Foundation
@testable import BlueprintCore

/// A command runner that returns canned output and records what was run.
final class MockRunner: CommandRunning, @unchecked Sendable {
    typealias Handler = @Sendable (_ executable: String, _ arguments: [String]) -> CommandResult?

    private let lock = NSLock()
    private var calls: [[String]] = []
    let installed: [String: String]
    let handler: Handler

    /// - Parameters:
    ///   - installed: tool name → absolute path returned by `locate`.
    ///   - handler: canned result per call; `nil` means "exit 1, no output".
    init(installed: [String: String] = [:], handler: @escaping Handler = { _, _ in nil }) {
        self.installed = installed
        self.handler = handler
    }

    func locate(_ name: String) -> String? { installed[name] }

    func run(_ executable: String, _ arguments: [String], environment: [String: String], timeout: TimeInterval) async throws -> CommandResult {
        lock.withLock { calls.append([executable] + arguments) }
        return handler(executable, arguments) ?? CommandResult(exitCode: 1, stdout: "")
    }

    var executedPaths: [String] { lock.withLock { calls.map { $0[0] } } }
}

/// A throw-away directory that stands in for "/" during a test.
final class FixtureTree {
    let root: URL
    let home = "/Users/tester"

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("macblueprint-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    var fs: FileSystem { FileSystem(root: root, home: home) }

    func context(runner: any CommandRunning = MockRunner(), environment: [String: String] = [:]) -> ScanContext {
        ScanContext(fs: fs, runner: runner, environment: environment)
    }

    func write(_ path: String, _ contents: String = "") throws {
        try write(path, Data(contents.utf8))
    }

    func write(_ path: String, _ data: Data) throws {
        let url = fs.url(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func mkdir(_ path: String) throws {
        try FileManager.default.createDirectory(at: fs.url(path), withIntermediateDirectories: true)
    }

    /// Creates a minimal `.app` bundle with an Info.plist.
    func makeApp(_ path: String, bundleId: String?, version: String? = "1.0", appStore: Bool = false) throws {
        var info: [String: Any] = [:]
        if let bundleId { info["CFBundleIdentifier"] = bundleId }
        if let version { info["CFBundleShortVersionString"] = version }
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try write(path + "/Contents/Info.plist", plist)
        if appStore { try write(path + "/Contents/_MASReceipt/receipt", "receipt") }
    }
}
