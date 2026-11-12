import Foundation

public enum FileSystemError: Error, Equatable, CustomStringConvertible {
    case excluded(String)

    public var description: String {
        switch self {
        case .excluded(let path): "refused to access excluded path: \(path)"
        }
    }
}

/// Read-only file access used by every scanner.
///
/// Paths are always written as they look on a real Mac ("/Applications",
/// "/Users/me/.vscode"). In tests, `root` points at a temporary directory so
/// the same paths resolve inside a fixture tree.
///
/// Every listing and read goes through ``Exclusions``: sensitive locations
/// cannot be touched even if a scanner asks for them.
public struct FileSystem: Sendable {
    public let root: URL
    public let home: String

    public init(root: URL = URL(fileURLWithPath: "/"), home: String = NSHomeDirectory()) {
        self.root = root
        self.home = home
    }

    /// Maps a real-world absolute path into the (possibly sandboxed) root.
    public func url(_ path: String) -> URL {
        if root.path == "/" { return URL(fileURLWithPath: path) }
        return root.appendingPathComponent(String(path.drop(while: { $0 == "/" })))
    }

    /// Joins a path relative to the home directory.
    public func homePath(_ relative: String) -> String {
        (home as NSString).appendingPathComponent(relative)
    }

    public func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url(path).path)
    }

    public func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url(path).path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Names of the entries in a directory, sorted. Returns `[]` when the directory is missing.
    public func list(_ path: String) throws -> [String] {
        try guardAccess(path)
        guard isDirectory(path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: url(path).path)
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }

    public func read(_ path: String) throws -> Data {
        try guardAccess(path)
        return try Data(contentsOf: url(path))
    }

    private func guardAccess(_ path: String) throws {
        if Exclusions.isExcluded(path, home: home) {
            throw FileSystemError.excluded(path)
        }
    }
}
