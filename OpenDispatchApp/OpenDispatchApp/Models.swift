import CapabilityRegistry
import Foundation
import SkillRegistry
import RouterCore
import SwiftData
import Executors

@Model
final class DispatchEventRecord {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var rawInput: String
    var capability: String
    var routerPlanJSON: String
    var providerID: String
    var parametersJSON: String
    var resultJSON: String
    var wasSuccessful: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date,
        rawInput: String,
        capability: String,
        routerPlanJSON: String,
        providerID: String,
        parametersJSON: String,
        resultJSON: String,
        wasSuccessful: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.rawInput = rawInput
        self.capability = capability
        self.routerPlanJSON = routerPlanJSON
        self.providerID = providerID
        self.parametersJSON = parametersJSON
        self.resultJSON = resultJSON
        self.wasSuccessful = wasSuccessful
    }
}

@Model
final class InstalledSkillRecord {
    @Attribute(.unique) var skillID: String
    var id: UUID
    var name: String
    var version: String
    var repositoryLocation: String
    var installedAt: Date
    var yamlFilePath: String

    init(
        id: UUID = UUID(),
        skillID: String,
        name: String,
        version: String,
        repositoryLocation: String,
        installedAt: Date = Date(),
        yamlFilePath: String
    ) {
        self.id = id
        self.skillID = skillID
        self.name = name
        self.version = version
        self.repositoryLocation = repositoryLocation
        self.installedAt = installedAt
        self.yamlFilePath = yamlFilePath
    }
}

@Model
final class RepositorySourceRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var kind: String
    var location: String
    var lastRefreshedAt: Date?
    var lastError: String?
    var discoveredSkillsCount: Int

    init(
        id: UUID = UUID(),
        name: String,
        kind: String,
        location: String,
        lastRefreshedAt: Date? = nil,
        lastError: String? = nil,
        discoveredSkillsCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.location = location
        self.lastRefreshedAt = lastRefreshedAt
        self.lastError = lastError
        self.discoveredSkillsCount = discoveredSkillsCount
    }
}

@Model
final class LocalLogRecord {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var rawInput: String
    var tagsJSON: String
    var normalizedIntent: String

    init(
        id: UUID = UUID(),
        timestamp: Date,
        rawInput: String,
        tagsJSON: String,
        normalizedIntent: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.rawInput = rawInput
        self.tagsJSON = tagsJSON
        self.normalizedIntent = normalizedIntent
    }
}

@Model
final class UserExampleRecord {
    @Attribute(.unique) var id: UUID
    var skillID: String
    var actionID: String
    var skillName: String
    var actionTitle: String
    var text: String
    var createdAt: Date
    var isNegative: Bool

    /// Uniqueness: (skillID, actionID, text) — enforced at the UI/service layer
    /// since SwiftData only supports single-attribute @Attribute(.unique).

    var isValid: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    init(
        id: UUID = UUID(),
        skillID: String,
        actionID: String,
        skillName: String,
        actionTitle: String,
        text: String,
        createdAt: Date = Date(),
        isNegative: Bool = false
    ) {
        self.id = id
        self.skillID = skillID
        self.actionID = actionID
        self.skillName = skillName
        self.actionTitle = actionTitle
        self.text = text
        self.createdAt = createdAt
        self.isNegative = isNegative
    }
}

@Model
final class SuppressedExampleRecord {
    @Attribute(.unique) var id: UUID
    var skillID: String
    var actionID: String
    var text: String

    init(
        id: UUID = UUID(),
        skillID: String,
        actionID: String,
        text: String
    ) {
        self.id = id
        self.skillID = skillID
        self.actionID = actionID
        self.text = text
    }
}

enum JSONCodec {
    nonisolated static func encodeString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(value)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated static func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(string.utf8))
    }
}

actor SwiftDataDispatchEventStore: DispatchEventStoring {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func store(_ event: DispatchEvent) async throws {
        let context = ModelContext(modelContainer)
        context.insert(
            DispatchEventRecord(
                id: event.id,
                timestamp: event.timestamp,
                rawInput: event.rawInput,
                capability: event.routerPlan.capability.rawValue,
                routerPlanJSON: JSONCodec.encodeString(event.routerPlan),
                providerID: event.providerID,
                parametersJSON: JSONCodec.encodeString(event.parameters),
                resultJSON: JSONCodec.encodeString(event.result),
                wasSuccessful: event.result.success
            )
        )
        try context.save()
    }
}

actor SwiftDataLocalLogSink: LocalLogSink {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func append(_ entry: LocalLogEntry) async throws {
        let context = ModelContext(modelContainer)
        context.insert(
            LocalLogRecord(
                timestamp: entry.timestamp,
                rawInput: entry.rawInput,
                tagsJSON: JSONCodec.encodeString(entry.tags),
                normalizedIntent: entry.normalizedIntent
            )
        )
        try context.save()
    }
}

extension RepositorySourceRecord {
    var repositorySource: RepositorySource? {
        guard let kind = RepositorySourceKind(rawValue: kind) else {
            return nil
        }
        return RepositorySource(
            id: id,
            name: name,
            kind: kind,
            location: location
        )
    }
}
