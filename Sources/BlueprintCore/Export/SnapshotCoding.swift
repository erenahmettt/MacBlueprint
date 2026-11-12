import Foundation

public enum SnapshotCodingError: Error, CustomStringConvertible {
    case unsupportedSchema(Int)

    public var description: String {
        switch self {
        case .unsupportedSchema(let version):
            "snapshot schema v\(version) is newer than this macblueprint supports (v\(Snapshot.currentSchemaVersion)); please update"
        }
    }
}

extension Snapshot {
    /// Pretty, key-sorted JSON so snapshots diff cleanly in git.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> Snapshot {
        struct Header: Decodable { var schemaVersion: Int }
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard header.schemaVersion <= Snapshot.currentSchemaVersion else {
            throw SnapshotCodingError.unsupportedSchema(header.schemaVersion)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Snapshot.self, from: data)
    }
}
