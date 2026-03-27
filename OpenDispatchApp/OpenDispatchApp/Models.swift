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
    @Attribute(.unique) var id: UUID
    var name: String
    var providerName: String
    var providerID: String
    var capability: String
    var manifestJSON: String
    var documentation: String
    var sourceLocation: String
    var installedAt: Date
    var validationErrorsJSON: String?

    init(
        id: UUID = UUID(),
        name: String,
        providerName: String,
        providerID: String,
        capability: String,
        manifestJSON: String,
        documentation: String,
        sourceLocation: String,
        installedAt: Date,
        validationErrorsJSON: String? = nil
    ) {
        self.id = id
        self.name = name
        self.providerName = providerName
        self.providerID = providerID
        self.capability = capability
        self.manifestJSON = manifestJSON
        self.documentation = documentation
        self.sourceLocation = sourceLocation
        self.installedAt = installedAt
        self.validationErrorsJSON = validationErrorsJSON
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

extension InstalledSkillRecord {
    convenience init(skill: InstalledSkill, validationErrors: [String] = []) {
        self.init(
            id: skill.id,
            name: skill.manifest.displayName,
            providerName: skill.manifest.displayName,
            providerID: skill.manifest.resolvedProviderID,
            capability: skill.manifest.primaryCapability?.rawValue ?? "",
            manifestJSON: JSONCodec.encodeString(skill.manifest),
            documentation: skill.documentation,
            sourceLocation: skill.sourceLocation,
            installedAt: skill.installedAt,
            validationErrorsJSON: validationErrors.isEmpty ? nil : JSONCodec.encodeString(validationErrors)
        )
    }

    var installedSkill: InstalledSkill? {
        guard let manifest = try? JSONCodec.decode(SkillManifest.self, from: manifestJSON) else {
            return nil
        }
        return InstalledSkill(
            id: id,
            manifest: manifest,
            documentation: documentation,
            sourceLocation: sourceLocation,
            installedAt: installedAt
        )
    }

    var validationErrors: [String] {
        guard let validationErrorsJSON,
              let errors = try? JSONCodec.decode([String].self, from: validationErrorsJSON) else {
            return []
        }
        return errors
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
