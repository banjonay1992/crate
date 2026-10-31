import Foundation

/// Minimal persistence: named blobs of data. Crate's stores are small enough
/// (thousands of records, not millions) that Codable JSON files are simpler and
/// easier to inspect than a database, and they keep CrateCore dependency-free.
public protocol KeyValueStore: Sendable {
    func data(forKey key: String) throws -> Data?
    func set(_ data: Data?, forKey key: String) throws
}

/// Stores each key as a JSON file in a directory, written atomically.
public final class FileStore: KeyValueStore, @unchecked Sendable {
    public let directory: URL
    private let lock = NSLock()

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// `Application Support/<name>` in the app's container. Not backed up to
    /// iCloud: everything in it can be re-synced from Discogs, apart from the
    /// dig log, which lives in a separate store that is backed up.
    public static func applicationSupport(named name: String, excludeFromBackup: Bool) throws -> FileStore {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let url = base.appendingPathComponent(name, isDirectory: true)
        let store = try FileStore(directory: url)
        #if canImport(Darwin)
        if excludeFromBackup {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = url
            try? mutableURL.setResourceValues(values)
        }
        #endif
        return store
    }

    private func url(for key: String) -> URL {
        let safe = key.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" ? String($0) : "_" }.joined()
        return directory.appendingPathComponent(safe).appendingPathExtension("json")
    }

    public func data(forKey key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        let url = url(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func set(_ data: Data?, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        let url = url(for: key)
        if let data {
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: url, options: [.atomic])
            #endif
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

/// In-memory store for tests and previews.
public final class InMemoryStore: KeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    public init() {}

    public func data(forKey key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    public func set(_ data: Data?, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = data
    }

    public var keys: [String] {
        lock.lock(); defer { lock.unlock() }
        return storage.keys.sorted()
    }
}

/// Wraps stored values with a schema version so that an incompatible file left
/// behind by an older build is discarded rather than crashing the app.
struct Envelope<Value: Codable>: Codable {
    var version: Int
    var savedAt: Date
    var value: Value
}

/// Reads and writes Codable values through a KeyValueStore.
struct CodableStorage: Sendable {
    let store: KeyValueStore
    let schemaVersion: Int

    init(store: KeyValueStore, schemaVersion: Int = 1) {
        self.store = store
        self.schemaVersion = schemaVersion
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Returns nil when nothing is stored, the data is unreadable, or the schema version differs.
    func load<Value: Codable>(_ type: Value.Type, key: String) -> Value? {
        guard let data = try? store.data(forKey: key),
              let envelope = try? Self.makeDecoder().decode(Envelope<Value>.self, from: data),
              envelope.version == schemaVersion
        else { return nil }
        return envelope.value
    }

    func save<Value: Codable>(_ value: Value, key: String, now: Date = Date()) throws {
        let data = try Self.makeEncoder().encode(Envelope(version: schemaVersion, savedAt: now, value: value))
        try store.set(data, forKey: key)
    }

    func remove(key: String) throws {
        try store.set(nil, forKey: key)
    }
}
