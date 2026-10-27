import Foundation

public struct Profile: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var color: ProfileColor
    /// Absolute path passed to Claude as `--user-data-dir`.
    public var dataPath: String
    public var createdAt: Date
    /// Folder the profile's last terminal session started in. Absent in files written before 1.1.
    public var lastWorkingDirectory: String?

    public init(
        id: UUID,
        name: String,
        color: ProfileColor,
        dataPath: String,
        createdAt: Date,
        lastWorkingDirectory: String? = nil
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.dataPath = dataPath
        self.createdAt = createdAt
        self.lastWorkingDirectory = lastWorkingDirectory
    }

    public var dataURL: URL { URL(fileURLWithPath: dataPath, isDirectory: true) }

    public var initial: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "?"
    }

    /// "…/ClaudeProfiles/data/7F3A91C2-…" style path for the row subtitle.
    public var shortDataPath: String {
        let components = dataURL.pathComponents.filter { $0 != "/" }
        guard components.count > 3 else { return AppPaths.abbreviated(dataPath) }
        return "…/" + components.suffix(3).joined(separator: "/")
    }
}

public enum ProfileColor: String, Codable, CaseIterable, Identifiable {
    case blue, green, purple, slate, rust, plum

    public var id: String { rawValue }
    public var name: String { rawValue.capitalized }
}

/// Reads and writes profiles.json. Fields added later are optional, so older files keep loading.
public enum ProfileArchive {
    public static func decode(_ data: Data) throws -> [Profile] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Profile].self, from: data)
    }

    public static func encode(_ profiles: [Profile]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(profiles)
    }
}
