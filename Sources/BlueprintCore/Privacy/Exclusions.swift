import Foundation

/// Paths MacBlueprint must never list or read, no matter which scanner asks.
///
/// This is enforced in ``FileSystem``, so a scanner cannot opt out of it by
/// mistake. The list is intentionally conservative: if a location *might*
/// hold credentials, it belongs here.
public enum Exclusions {
    /// Locations relative to the home directory.
    public static let homeRelativePaths: [String] = [
        ".ssh",
        ".gnupg",
        "Library/Keychains",
        ".aws",
        ".azure",
        ".config/gcloud",
        ".config/gh",
        ".kube",
        ".docker",
        ".netrc",
        ".npmrc",
        ".pypirc",
        ".git-credentials",
    ]

    /// File names that are excluded wherever they appear: ".env", ".env.local",
    /// ".envrc", and App Store metadata that embeds the Apple ID of the buyer.
    public static func isSensitiveFileName(_ name: String) -> Bool {
        name.hasPrefix(".env") || name == "iTunesMetadata.plist"
    }

    public static func isExcluded(_ path: String, home: String) -> Bool {
        let path = (path as NSString).standardizingPath
        let home = (home as NSString).standardizingPath
        for relative in homeRelativePaths {
            let blocked = home + "/" + relative
            if path == blocked || path.hasPrefix(blocked + "/") {
                return true
            }
        }
        return isSensitiveFileName((path as NSString).lastPathComponent)
    }
}
