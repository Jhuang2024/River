import Foundation

/// Versioned envelope so future schema migrations know what they are reading.
public struct SaveEnvelope<Payload: Codable>: Codable {
    public let schemaVersion: Int
    public let payload: Payload

    public init(schemaVersion: Int, payload: Payload) {
        self.schemaVersion = schemaVersion
        self.payload = payload
    }
}

/// Local JSON persistence. Everything stays on device; there is no backend.
///
/// Files live in Application Support/River. The directory is injectable so
/// tests write to a temporary location.
public final class PersistenceStore {
    public static let currentSchemaVersion = 1

    public let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) {
        self.directory = directory
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The default on-device store.
    public static func standard() -> PersistenceStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return PersistenceStore(directory: base.appendingPathComponent("River", isDirectory: true))
    }

    private func url(_ name: String) -> URL {
        return directory.appendingPathComponent(name + ".json")
    }

    public func save<T: Codable>(_ value: T, as name: String) throws {
        let envelope = SaveEnvelope(schemaVersion: PersistenceStore.currentSchemaVersion, payload: value)
        let data = try encoder.encode(envelope)
        try data.write(to: url(name), options: .atomic)
    }

    public func load<T: Codable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        // Migration hook: today only schema version 1 exists. When version 2
        // arrives, decode the old payload here and transform it.
        guard let envelope = try? decoder.decode(SaveEnvelope<T>.self, from: data) else { return nil }
        guard envelope.schemaVersion <= PersistenceStore.currentSchemaVersion else { return nil }
        return envelope.payload
    }

    public func delete(_ name: String) {
        try? FileManager.default.removeItem(at: url(name))
    }

    public func exists(_ name: String) -> Bool {
        return FileManager.default.fileExists(atPath: url(name).path)
    }

    // MARK: - Well-known files

    public enum FileName {
        public static let settings = "settings"
        public static let session = "current-session"
        public static let histories = "hand-histories"
    }

    /// Hand histories are stored as a bounded ring (most recent last).
    public func appendHistory(_ history: HandHistory, limit: Int = 300) {
        var all = load([HandHistory].self, from: FileName.histories) ?? []
        all.append(history)
        if all.count > limit {
            all.removeFirst(all.count - limit)
        }
        try? save(all, as: FileName.histories)
    }

    public func loadHistories() -> [HandHistory] {
        return load([HandHistory].self, from: FileName.histories) ?? []
    }
}
