import Foundation

public struct CapabilityID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public var description: String {
        rawValue
    }

    public init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public var isValid: Bool {
        Self.isValid(rawValue)
    }

    public static func isValid(_ value: String) -> Bool {
        let pattern = #"^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}

public struct CapabilityDefinition: Hashable, Codable, Sendable {
    public let id: CapabilityID
    public let title: String
    public let summary: String
    public let destructiveByDefault: Bool

    public init(
        id: CapabilityID,
        title: String,
        summary: String,
        destructiveByDefault: Bool = false
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.destructiveByDefault = destructiveByDefault
    }
}

public enum ProviderKind: String, Codable, CaseIterable, Hashable, Sendable {
    case system
    case external
}

public struct ProviderDescriptor: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let displayName: String
    public let kind: ProviderKind
    public let priority: Int
    public let capabilities: [CapabilityID]

    public init(
        id: String,
        displayName: String,
        kind: ProviderKind,
        priority: Int,
        capabilities: [CapabilityID]
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.priority = priority
        self.capabilities = capabilities
    }
}

public enum CapabilityRegistryError: Error, Equatable, Sendable, LocalizedError {
    case invalidCapabilityID(String)
    case duplicateCapability(CapabilityID)
    case unknownCapability(CapabilityID)
    case duplicateProvider(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidCapabilityID(id):
            "Invalid capability ID: \(id)"
        case let .duplicateCapability(id):
            "Duplicate capability: \(id.rawValue)"
        case let .unknownCapability(id):
            "Unknown capability: \(id.rawValue)"
        case let .duplicateProvider(id):
            "Duplicate provider: \(id)"
        }
    }
}

public struct CanonicalCapabilities: Sendable {
    public let logEvent: CapabilityDefinition
    public let taskCreate: CapabilityDefinition
    public let taskComplete: CapabilityDefinition
    public let noteCreate: CapabilityDefinition
    public let calendarEventCreate: CapabilityDefinition
    public let shortcutRun: CapabilityDefinition
    public let urlOpen: CapabilityDefinition

    public static let `default` = CanonicalCapabilities()

    public init() {
        logEvent = CapabilityDefinition(
            id: "log.event",
            title: "Log Event",
            summary: "Capture a structured local event."
        )
        taskCreate = CapabilityDefinition(
            id: "task.create",
            title: "Create Task",
            summary: "Create a task in a supported task provider."
        )
        taskComplete = CapabilityDefinition(
            id: "task.complete",
            title: "Complete Task",
            summary: "Mark an existing task as complete.",
            destructiveByDefault: true
        )
        noteCreate = CapabilityDefinition(
            id: "note.create",
            title: "Create Note",
            summary: "Create a note in a supported note provider."
        )
        calendarEventCreate = CapabilityDefinition(
            id: "calendar.event.create",
            title: "Create Calendar Event",
            summary: "Create a calendar event."
        )
        shortcutRun = CapabilityDefinition(
            id: "shortcut.run",
            title: "Run Shortcut",
            summary: "Run an Apple Shortcut."
        )
        urlOpen = CapabilityDefinition(
            id: "url.open",
            title: "Open URL",
            summary: "Open a deep link or URL.",
            destructiveByDefault: true
        )
    }

    public var all: [CapabilityDefinition] {
        [
            logEvent,
            taskCreate,
            taskComplete,
            noteCreate,
            calendarEventCreate,
            shortcutRun,
            urlOpen,
        ]
    }
}

public struct CapabilityRegistry: Sendable {
    private var definitionsByID: [CapabilityID: CapabilityDefinition]
    private var providersByID: [String: ProviderDescriptor]
    private var providersByCapability: [CapabilityID: [ProviderDescriptor]]

    public init(definitions: [CapabilityDefinition] = CanonicalCapabilities.default.all) throws {
        var builtDefinitions: [CapabilityID: CapabilityDefinition] = [:]
        for definition in definitions {
            guard definition.id.isValid else {
                throw CapabilityRegistryError.invalidCapabilityID(definition.id.rawValue)
            }
            guard builtDefinitions[definition.id] == nil else {
                throw CapabilityRegistryError.duplicateCapability(definition.id)
            }
            builtDefinitions[definition.id] = definition
        }
        definitionsByID = builtDefinitions
        providersByID = [:]
        providersByCapability = [:]
    }

    public var definitions: [CapabilityDefinition] {
        definitionsByID.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    public var providers: [ProviderDescriptor] {
        providersByID.values.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.displayName < rhs.displayName
        }
    }

    public func contains(_ capability: CapabilityID) -> Bool {
        definitionsByID[capability] != nil
    }

    public func definition(for capability: CapabilityID) -> CapabilityDefinition? {
        definitionsByID[capability]
    }

    public func providers(for capability: CapabilityID) -> [ProviderDescriptor] {
        (providersByCapability[capability] ?? []).sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.displayName < rhs.displayName
        }
    }

    public mutating func registerProvider(_ provider: ProviderDescriptor) throws {
        guard providersByID[provider.id] == nil else {
            throw CapabilityRegistryError.duplicateProvider(provider.id)
        }

        for capability in provider.capabilities {
            guard contains(capability) else {
                throw CapabilityRegistryError.unknownCapability(capability)
            }
        }

        providersByID[provider.id] = provider

        for capability in provider.capabilities {
            var providers = providersByCapability[capability] ?? []
            providers.append(provider)
            providersByCapability[capability] = providers
        }
    }
}
