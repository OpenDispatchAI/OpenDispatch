import Foundation
import RouterCore

public enum CompiledIndexStoreError: Error, Sendable {
    case schemaVersionMismatch(cached: Int, current: Int)
}

public enum CompiledIndexStore {

    public static func save(_ index: CompiledIndex, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(index)
        try data.write(to: url, options: .atomic)
    }

    /// Load a cached index. Throws if the file doesn't exist or the
    /// schema version doesn't match the current `CompiledIndex.schemaVersion`.
    public static func load(from url: URL) throws -> CompiledIndex {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let index = try decoder.decode(CompiledIndex.self, from: data)

        guard index.schemaVersion == CompiledIndex.schemaVersion else {
            throw CompiledIndexStoreError.schemaVersionMismatch(
                cached: index.schemaVersion,
                current: CompiledIndex.schemaVersion
            )
        }

        return index
    }

    public static func defaultURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("OpenDispatch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("compiled_index.json")
    }
}
