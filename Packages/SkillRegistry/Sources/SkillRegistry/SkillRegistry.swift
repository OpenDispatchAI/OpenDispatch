import CapabilityRegistry
import Foundation
import RouterCore

public enum SkillExecutorKind: String, Codable, CaseIterable, Hashable, Sendable {
    case localLog = "local_log"
    case shortcuts = "shortcuts"
    case urlScheme = "url_scheme"
}

public enum ConfirmationRequirement: String, Codable, CaseIterable, Hashable, Sendable {
    case none
    case required
}

public struct BridgeShortcutManifest: Codable, Hashable, Sendable {
    public let name: String
    public let version: String
    public let installURL: String?
    public let inputFormat: String?

    public init(
        name: String,
        version: String,
        installURL: String? = nil,
        inputFormat: String? = "json"
    ) {
        self.name = name
        self.version = version
        self.installURL = installURL
        self.inputFormat = inputFormat
    }

    enum CodingKeys: String, CodingKey {
        case name
        case version
        case installURL = "install_url"
        case inputFormat = "input_format"
    }
}

public struct SkillAction: Identifiable, Codable, Hashable, Sendable {
    public let action: String
    public let capability: CapabilityID
    public let paramsSchema: [String: String]
    public let keywords: [String]
    public let examples: [String]
    public let title: String?

    public var id: String {
        action
    }

    public init(
        action: String,
        capability: CapabilityID? = nil,
        paramsSchema: [String: String] = [:],
        keywords: [String] = [],
        examples: [String] = [],
        title: String? = nil
    ) {
        self.action = action.trimmingCharacters(in: .whitespacesAndNewlines)
        self.capability = capability ?? CapabilityID(rawValue: action)
        self.paramsSchema = paramsSchema
        self.keywords = keywords
        self.examples = examples
        self.title = title
    }

    enum CodingKeys: String, CodingKey {
        case action
        case capability
        case paramsSchema = "params_schema"
        case keywords
        case examples
        case title
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let action = try container.decode(String.self, forKey: .action)
        let capabilityRawValue = try container.decodeIfPresent(String.self, forKey: .capability)

        self.init(
            action: action,
            capability: capabilityRawValue.map(CapabilityID.init(rawValue:)),
            paramsSchema: try container.decodeIfPresent([String: String].self, forKey: .paramsSchema) ?? [:],
            keywords: try container.decodeIfPresent([String].self, forKey: .keywords) ?? [],
            examples: try container.decodeIfPresent([String].self, forKey: .examples) ?? [],
            title: try container.decodeIfPresent(String.self, forKey: .title)
        )
    }
}

public struct SkillManifest: Identifiable, Codable, Hashable, Sendable {
    public let name: String?
    public let capability: CapabilityID?
    public let executor: SkillExecutorKind?
    public let urlTemplate: String?
    public let shortcutName: String?
    public let confirmation: ConfirmationRequirement
    public let providerName: String?
    public let providerID: String?
    public let priority: Int
    public let keywords: [String]
    public let examples: [String]

    public let skillID: String?
    public let version: String?
    public let bridgeShortcutRequired: Bool
    public let bridgeShortcutName: String?
    public let bridgeShortcutVersion: String?
    public let bridgeInstallURL: String?
    public let bridgeSetupInstructions: [String]
    public let bridgeInputTemplate: [String: JSONValue]?
    public let upgradeNotes: [String]
    public let actions: [SkillAction]

    public var id: String {
        resolvedProviderID
    }

    public init(
        name: String,
        capability: CapabilityID,
        executor: SkillExecutorKind,
        urlTemplate: String? = nil,
        shortcutName: String? = nil,
        confirmation: ConfirmationRequirement = .required,
        providerName: String,
        providerID: String,
        priority: Int = 50,
        keywords: [String] = [],
        examples: [String] = []
    ) {
        self.name = name
        self.capability = capability
        self.executor = executor
        self.urlTemplate = urlTemplate
        self.shortcutName = shortcutName
        self.confirmation = confirmation
        self.providerName = providerName
        self.providerID = providerID
        self.priority = priority
        self.keywords = keywords
        self.examples = examples

        skillID = nil
        version = nil
        bridgeShortcutRequired = false
        bridgeShortcutName = nil
        bridgeShortcutVersion = nil
        bridgeInstallURL = nil
        bridgeSetupInstructions = []
        bridgeInputTemplate = nil
        upgradeNotes = []
        actions = []
    }

    public init(
        skillID: String,
        version: String,
        bridgeShortcutRequired: Bool = true,
        bridgeShortcutName: String,
        bridgeShortcutVersion: String,
        bridgeInstallURL: String? = nil,
        bridgeSetupInstructions: [String] = [],
        bridgeInputTemplate: [String: JSONValue]? = nil,
        upgradeNotes: [String] = [],
        actions: [SkillAction],
        name: String? = nil,
        providerName: String? = nil,
        providerID: String? = nil,
        priority: Int = 60
    ) {
        self.name = name
        capability = nil
        executor = nil
        urlTemplate = nil
        shortcutName = nil
        confirmation = .required
        self.providerName = providerName
        self.providerID = providerID
        self.priority = priority
        keywords = []
        examples = []

        self.skillID = skillID
        self.version = version
        self.bridgeShortcutRequired = bridgeShortcutRequired
        self.bridgeShortcutName = bridgeShortcutName
        self.bridgeShortcutVersion = bridgeShortcutVersion
        self.bridgeInstallURL = bridgeInstallURL
        self.bridgeSetupInstructions = bridgeSetupInstructions
        self.bridgeInputTemplate = bridgeInputTemplate
        self.upgradeNotes = upgradeNotes
        self.actions = actions
    }

    enum CodingKeys: String, CodingKey {
        case name
        case capability
        case executor
        case urlTemplate = "url_template"
        case shortcutName = "shortcut_name"
        case confirmation
        case providerName = "provider_name"
        case providerID = "provider_id"
        case priority
        case keywords
        case examples
        case skillID = "skill_id"
        case version
        case bridgeShortcut = "bridge_shortcut"
        case bridgeShortcutRequired = "bridge_shortcut_required"
        case bridgeShortcutName = "bridge_shortcut_name"
        case bridgeShortcutVersion = "bridge_shortcut_version"
        case bridgeInstallURL = "bridge_install_url"
        case bridgeSetupInstructions = "bridge_setup_instructions"
        case bridgeInputTemplate = "bridge_input_template"
        case upgradeNotes = "upgrade_notes"
        case actions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let nestedBridgeShortcut = try container.decodeIfPresent(BridgeShortcutManifest.self, forKey: .bridgeShortcut)

        name = try container.decodeIfPresent(String.self, forKey: .name)
        capability = try container.decodeIfPresent(CapabilityID.self, forKey: .capability)
        executor = try container.decodeIfPresent(SkillExecutorKind.self, forKey: .executor)
        urlTemplate = try container.decodeIfPresent(String.self, forKey: .urlTemplate)
        shortcutName = try container.decodeIfPresent(String.self, forKey: .shortcutName)
        confirmation = try container.decodeIfPresent(ConfirmationRequirement.self, forKey: .confirmation) ?? .required
        providerName = try container.decodeIfPresent(String.self, forKey: .providerName)
        providerID = try container.decodeIfPresent(String.self, forKey: .providerID)
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 60
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        examples = try container.decodeIfPresent([String].self, forKey: .examples) ?? []

        skillID = try container.decodeIfPresent(String.self, forKey: .skillID)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        bridgeShortcutRequired = try container.decodeIfPresent(Bool.self, forKey: .bridgeShortcutRequired)
            ?? (nestedBridgeShortcut != nil)
        bridgeShortcutName = try container.decodeIfPresent(String.self, forKey: .bridgeShortcutName)
            ?? nestedBridgeShortcut?.name
        bridgeShortcutVersion = try container.decodeIfPresent(String.self, forKey: .bridgeShortcutVersion)
            ?? nestedBridgeShortcut?.version
        bridgeInstallURL = try container.decodeIfPresent(String.self, forKey: .bridgeInstallURL)
            ?? nestedBridgeShortcut?.installURL
        bridgeSetupInstructions = try container.decodeIfPresent([String].self, forKey: .bridgeSetupInstructions) ?? []
        bridgeInputTemplate = try container.decodeIfPresent([String: JSONValue].self, forKey: .bridgeInputTemplate)
        upgradeNotes = try container.decodeIfPresent([String].self, forKey: .upgradeNotes) ?? []
        actions = try container.decodeIfPresent([SkillAction].self, forKey: .actions) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(capability, forKey: .capability)
        try container.encodeIfPresent(executor, forKey: .executor)
        try container.encodeIfPresent(urlTemplate, forKey: .urlTemplate)
        try container.encodeIfPresent(shortcutName, forKey: .shortcutName)
        try container.encode(confirmation, forKey: .confirmation)
        try container.encodeIfPresent(providerName, forKey: .providerName)
        try container.encodeIfPresent(providerID, forKey: .providerID)
        try container.encode(priority, forKey: .priority)
        if keywords.isEmpty == false {
            try container.encode(keywords, forKey: .keywords)
        }
        if examples.isEmpty == false {
            try container.encode(examples, forKey: .examples)
        }

        try container.encodeIfPresent(skillID, forKey: .skillID)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encode(bridgeShortcutRequired, forKey: .bridgeShortcutRequired)
        try container.encodeIfPresent(bridgeShortcutName, forKey: .bridgeShortcutName)
        try container.encodeIfPresent(bridgeShortcutVersion, forKey: .bridgeShortcutVersion)
        try container.encodeIfPresent(bridgeInstallURL, forKey: .bridgeInstallURL)
        if bridgeSetupInstructions.isEmpty == false {
            try container.encode(bridgeSetupInstructions, forKey: .bridgeSetupInstructions)
        }
        try container.encodeIfPresent(bridgeInputTemplate, forKey: .bridgeInputTemplate)
        if upgradeNotes.isEmpty == false {
            try container.encode(upgradeNotes, forKey: .upgradeNotes)
        }
        if actions.isEmpty == false {
            try container.encode(actions, forKey: .actions)
        }
    }
}

public extension SkillManifest {
    var displayName: String {
        if let providerName = Self.cleaned(providerName) {
            return providerName
        }
        if let name = Self.cleaned(name) {
            return name
        }
        if let skillID = Self.cleaned(skillID) {
            return Self.prettifiedIdentifier(skillID)
        }
        return "External Skill"
    }

    var resolvedProviderID: String {
        if let providerID = Self.cleaned(providerID) {
            return providerID
        }
        if let skillID = Self.cleaned(skillID) {
            return skillID
        }
        if let name = Self.cleaned(name) {
            return Self.slugified(name)
        }
        return "external_skill"
    }

    var supportedActions: [SkillAction] {
        if actions.isEmpty == false {
            return actions
        }

        guard let capability else {
            return []
        }

        return [
            SkillAction(
                action: capability.rawValue,
                capability: capability,
                paramsSchema: [:],
                keywords: keywords,
                examples: examples,
                title: name
            ),
        ]
    }

    var capabilities: [CapabilityID] {
        var seen: Set<CapabilityID> = []
        return supportedActions.compactMap { action in
            guard seen.insert(action.capability).inserted else {
                return nil
            }
            return action.capability
        }
    }

    var primaryCapability: CapabilityID? {
        capabilities.first
    }

    var usesBridgeShortcut: Bool {
        actions.isEmpty == false || bridgeShortcutRequired || bridgeShortcutName != nil
    }

    var resolvedShortcutName: String? {
        if usesBridgeShortcut {
            return Self.cleaned(bridgeShortcutName)
        }
        return Self.cleaned(shortcutName)
    }

    var isLegacyManifest: Bool {
        actions.isEmpty
    }

    func action(for capability: CapabilityID) -> SkillAction? {
        supportedActions.first(where: { $0.capability == capability })
    }

    func capabilityDefinitions(knownCapabilities: Set<CapabilityID> = []) -> [CapabilityDefinition] {
        supportedActions.compactMap { action in
            guard knownCapabilities.contains(action.capability) == false else {
                return nil
            }
            return CapabilityDefinition(
                id: action.capability,
                title: action.title ?? Self.prettifiedIdentifier(action.capability.rawValue),
                summary: "Action exposed by \(displayName).",
                destructiveByDefault: action.action.contains("delete")
                    || action.action.contains("remove")
                    || action.action.contains("unlock")
                    || action.action.contains("open")
            )
        }
    }

    func renderedBridgePayload(
        for action: SkillAction,
        plan: RouterPlan
    ) -> [String: JSONValue] {
        let context: [String: JSONValue] = [
            "schema_version": .integer(1),
            "skill_id": .string(Self.cleaned(skillID) ?? resolvedProviderID),
            "skill_version": .string(Self.cleaned(version) ?? "1.0.0"),
            "action": .string(action.action),
            "capability": .string(action.capability.rawValue),
            "provider_id": .string(resolvedProviderID),
            "params": .object(plan.parameters),
        ]

        if let bridgeInputTemplate {
            let rendered = render(template: .object(bridgeInputTemplate), with: context)
            if case let .object(payload) = rendered {
                return payload
            }
        }

        return [
            "schema_version": .integer(1),
            "skill_id": .string(Self.cleaned(skillID) ?? resolvedProviderID),
            "skill_version": .string(Self.cleaned(version) ?? "1.0.0"),
            "action": .string(action.action),
            "params": .object(plan.parameters),
        ]
    }

    fileprivate static func cleaned(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }

    private static func slugified(_ value: String) -> String {
        let pieces = value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
        return pieces.joined(separator: "_")
    }

    private static func prettifiedIdentifier(_ value: String) -> String {
        value
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func render(
        template: JSONValue,
        with context: [String: JSONValue]
    ) -> JSONValue {
        switch template {
        case let .string(value):
            return renderStringTemplate(value, with: context)
        case let .object(object):
            return .object(object.mapValues { render(template: $0, with: context) })
        case let .array(values):
            return .array(values.map { render(template: $0, with: context) })
        default:
            return template
        }
    }

    private func renderStringTemplate(
        _ value: String,
        with context: [String: JSONValue]
    ) -> JSONValue {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{{"), trimmed.hasSuffix("}}") {
            let key = String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let replacement = context[key] {
                return replacement
            }
        }

        var rendered = value
        for (key, replacement) in context {
            rendered = rendered.replacingOccurrences(of: "{{\(key)}}", with: replacement.stringValue ?? "")
        }
        return .string(rendered)
    }
}

public struct InstalledSkill: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let manifest: SkillManifest
    public let documentation: String
    public let sourceLocation: String
    public let installedAt: Date

    public init(
        id: UUID = UUID(),
        manifest: SkillManifest,
        documentation: String,
        sourceLocation: String,
        installedAt: Date = Date()
    ) {
        self.id = id
        self.manifest = manifest
        self.documentation = documentation
        self.sourceLocation = sourceLocation
        self.installedAt = installedAt
    }
}

public struct LoadedSkillPack: Hashable, Sendable {
    public let directoryURL: URL
    public let documentation: String
    public let manifest: SkillManifest?
    public let validationErrors: [SkillValidationError]

    public init(
        directoryURL: URL,
        documentation: String,
        manifest: SkillManifest?,
        validationErrors: [SkillValidationError]
    ) {
        self.directoryURL = directoryURL
        self.documentation = documentation
        self.manifest = manifest
        self.validationErrors = validationErrors
    }

    public var isValid: Bool {
        manifest != nil && validationErrors.isEmpty
    }
}

public enum SkillValidationError: Error, Hashable, Codable, Sendable, CustomStringConvertible {
    case missingManifest
    case invalidManifest(String)
    case missingDocumentation
    case unknownCapability(String)
    case invalidCapabilityID(String)
    case unknownExecutor(String)
    case missingURLTemplate
    case missingShortcutName
    case missingSkillID
    case missingVersion
    case missingActions
    case missingBridgeShortcutName
    case missingBridgeShortcutVersion
    case missingBridgeInstallURL
    case missingBridgeSetupInstructions
    case missingBridgeInputTemplate
    case invalidConfirmation(String)

    public var description: String {
        switch self {
        case .missingManifest:
            "Missing skill.json."
        case let .invalidManifest(reason):
            "Invalid skill manifest: \(reason)"
        case .missingDocumentation:
            "Missing SKILL.md."
        case let .unknownCapability(capability):
            "Capability does not exist: \(capability)"
        case let .invalidCapabilityID(capability):
            "Capability format is invalid: \(capability)"
        case let .unknownExecutor(executor):
            "Executor is not supported: \(executor)"
        case .missingURLTemplate:
            "URL scheme skills require url_template."
        case .missingShortcutName:
            "Shortcuts skills require shortcut_name."
        case .missingSkillID:
            "PRD skill packs require skill_id."
        case .missingVersion:
            "PRD skill packs require version."
        case .missingActions:
            "PRD skill packs require at least one action."
        case .missingBridgeShortcutName:
            "Shortcut-backed PRD skills require bridge_shortcut_name."
        case .missingBridgeShortcutVersion:
            "Shortcut-backed PRD skills require bridge_shortcut_version."
        case .missingBridgeInstallURL:
            "Shortcut-backed PRD skills require bridge_install_url."
        case .missingBridgeSetupInstructions:
            "Shortcut-backed PRD skills require bridge_setup_instructions."
        case .missingBridgeInputTemplate:
            "Shortcut-backed PRD skills require bridge_input_template."
        case let .invalidConfirmation(value):
            "Confirmation must be one of `none` or `required`: \(value)"
        }
    }
}

public struct SkillRepositoryIndex: Codable, Hashable, Sendable {
    public let repository: String
    public let skills: [SkillRepositoryEntry]

    public init(repository: String, skills: [SkillRepositoryEntry]) {
        self.repository = repository
        self.skills = skills
    }
}

public struct SkillRepositoryEntry: Codable, Hashable, Sendable {
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public enum RepositorySourceKind: String, Codable, CaseIterable, Hashable, Sendable {
    case httpIndex
    case gitHub
    case localFolder
}

public struct RepositorySource: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let kind: RepositorySourceKind
    public let location: String

    public init(
        id: UUID = UUID(),
        name: String,
        kind: RepositorySourceKind,
        location: String
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.location = location
    }
}

public enum SkillRegistryError: Error, Sendable {
    case invalidRepositoryLocation(String)
}

public struct SkillRegistryService: Sendable {
    private let capabilityRegistry: CapabilityRegistry

    public init(capabilityRegistry: CapabilityRegistry) {
        self.capabilityRegistry = capabilityRegistry
    }

    public func loadSkillPack(at directoryURL: URL) async -> LoadedSkillPack {
        let manifestURL = directoryURL.appending(path: "skill.json")
        let documentationURL = directoryURL.appending(path: "SKILL.md")
        let documentation = (try? String(contentsOf: documentationURL, encoding: .utf8)) ?? ""
        let fileManager = FileManager.default

        var errors: [SkillValidationError] = []
        if fileManager.fileExists(atPath: documentationURL.path) == false {
            errors.append(.missingDocumentation)
        }

        guard fileManager.fileExists(atPath: manifestURL.path) else {
            errors.append(.missingManifest)
            return LoadedSkillPack(
                directoryURL: directoryURL,
                documentation: documentation,
                manifest: nil,
                validationErrors: errors
            )
        }

        do {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(SkillManifest.self, from: data)
            errors.append(contentsOf: validate(manifest: manifest))
            return LoadedSkillPack(
                directoryURL: directoryURL,
                documentation: documentation,
                manifest: manifest,
                validationErrors: errors
            )
        } catch {
            errors.append(.invalidManifest(error.localizedDescription))
            return LoadedSkillPack(
                directoryURL: directoryURL,
                documentation: documentation,
                manifest: nil,
                validationErrors: errors
            )
        }
    }

    public func loadSkillPacks(at directoryURLs: [URL]) async -> [LoadedSkillPack] {
        var loaded: [LoadedSkillPack] = []
        for url in directoryURLs {
            loaded.append(await loadSkillPack(at: url))
        }
        return loaded
    }

    public func validate(manifest: SkillManifest) -> [SkillValidationError] {
        var errors: [SkillValidationError] = []

        if manifest.isLegacyManifest {
            guard let capability = manifest.capability else {
                return [.invalidManifest("Legacy skills require capability.")]
            }

            if capability.isValid == false {
                errors.append(.invalidCapabilityID(capability.rawValue))
            } else if capabilityRegistry.contains(capability) == false {
                errors.append(.unknownCapability(capability.rawValue))
            }

            guard let executor = manifest.executor else {
                errors.append(.invalidManifest("Legacy skills require executor."))
                return errors
            }

            switch executor {
            case .urlScheme:
                if manifest.urlTemplate?.isEmpty != false {
                    errors.append(.missingURLTemplate)
                }
            case .shortcuts:
                if manifest.shortcutName?.isEmpty != false {
                    errors.append(.missingShortcutName)
                }
            case .localLog:
                break
            }

            return errors
        }

        if SkillManifest.cleaned(manifest.skillID) == nil {
            errors.append(.missingSkillID)
        }
        if SkillManifest.cleaned(manifest.version) == nil {
            errors.append(.missingVersion)
        }
        if manifest.actions.isEmpty {
            errors.append(.missingActions)
        }

        var seenCapabilities: Set<CapabilityID> = []
        for action in manifest.supportedActions {
            if action.capability.isValid == false {
                errors.append(.invalidCapabilityID(action.capability.rawValue))
            }
            if seenCapabilities.insert(action.capability).inserted == false {
                errors.append(.invalidManifest("Duplicate action capability: \(action.capability.rawValue)"))
            }
        }

        if manifest.usesBridgeShortcut {
            if SkillManifest.cleaned(manifest.bridgeShortcutName) == nil {
                errors.append(.missingBridgeShortcutName)
            }
            if SkillManifest.cleaned(manifest.bridgeShortcutVersion) == nil {
                errors.append(.missingBridgeShortcutVersion)
            }
            if SkillManifest.cleaned(manifest.bridgeInstallURL) == nil {
                errors.append(.missingBridgeInstallURL)
            }
            if manifest.bridgeSetupInstructions.isEmpty {
                errors.append(.missingBridgeSetupInstructions)
            }
            if manifest.bridgeInputTemplate == nil {
                errors.append(.missingBridgeInputTemplate)
            }
        }

        return errors
    }

    public func installableSkill(from loadedPack: LoadedSkillPack) -> InstalledSkill? {
        guard let manifest = loadedPack.manifest, loadedPack.validationErrors.isEmpty else {
            return nil
        }

        return InstalledSkill(
            manifest: manifest,
            documentation: loadedPack.documentation,
            sourceLocation: loadedPack.directoryURL.path
        )
    }

    public func planningContexts(from skills: [InstalledSkill]) -> [PlannerSkillContext] {
        skills.flatMap { skill in
            skill.manifest.supportedActions.map { action in
                PlannerSkillContext(
                    id: "\(skill.id.uuidString):\(action.action)",
                    name: skill.manifest.displayName,
                    capability: action.capability,
                    providerID: skill.manifest.resolvedProviderID,
                    examples: action.examples,
                    documentation: planningDocumentation(for: action, in: skill)
                )
            }
        }
    }

    public func capabilityDefinitions(from manifests: [SkillManifest]) -> [CapabilityDefinition] {
        let knownCapabilities = Set(capabilityRegistry.definitions.map(\.id))
        var emitted: Set<CapabilityID> = []

        return manifests.flatMap { manifest in
            manifest.capabilityDefinitions(knownCapabilities: knownCapabilities).compactMap { definition in
                guard emitted.insert(definition.id).inserted else {
                    return nil
                }
                return definition
            }
        }
    }

    public func repositoryIndex(for source: RepositorySource) async throws -> SkillRepositoryIndex {
        let indexURL = try resolvedIndexURL(for: source)
        switch source.kind {
        case .httpIndex, .gitHub:
            let (data, _) = try await URLSession.shared.data(from: indexURL)
            return try JSONDecoder().decode(SkillRepositoryIndex.self, from: data)
        case .localFolder:
            let data = try Data(contentsOf: indexURL)
            return try JSONDecoder().decode(SkillRepositoryIndex.self, from: data)
        }
    }

    public func resolvedIndexURL(for source: RepositorySource) throws -> URL {
        switch source.kind {
        case .httpIndex:
            guard let url = URL(string: source.location) else {
                throw SkillRegistryError.invalidRepositoryLocation(source.location)
            }
            return url
        case .gitHub:
            if let url = URL(string: source.location), source.location.contains("github.com") {
                let pathComponents = url.pathComponents.filter { $0 != "/" }
                guard pathComponents.count >= 2 else {
                    throw SkillRegistryError.invalidRepositoryLocation(source.location)
                }
                let owner = pathComponents[0]
                let repo = pathComponents[1]
                let branch = pathComponents.count >= 4 && pathComponents[2] == "tree" ? pathComponents[3] : "main"
                let suffix = pathComponents.count > 4 ? pathComponents.dropFirst(4).joined(separator: "/") : ""
                let indexPath = suffix.isEmpty ? "index.json" : "\(suffix)/index.json"
                guard let rawURL = URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/\(indexPath)") else {
                    throw SkillRegistryError.invalidRepositoryLocation(source.location)
                }
                return rawURL
            }

            let parts = source.location.split(separator: "/").map(String.init)
            guard parts.count >= 2 else {
                throw SkillRegistryError.invalidRepositoryLocation(source.location)
            }
            let owner = parts[0]
            let repo = parts[1]
            let branch = parts.count >= 3 ? parts[2] : "main"
            guard let url = URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/index.json") else {
                throw SkillRegistryError.invalidRepositoryLocation(source.location)
            }
            return url
        case .localFolder:
            let url = URL(fileURLWithPath: source.location, isDirectory: true)
            return url.appending(path: "index.json")
        }
    }

    public func skillDirectoryURL(
        for entry: SkillRepositoryEntry,
        in source: RepositorySource
    ) throws -> URL {
        switch source.kind {
        case .httpIndex:
            guard let base = URL(string: source.location)?.deletingLastPathComponent() else {
                throw SkillRegistryError.invalidRepositoryLocation(source.location)
            }
            return base.appending(path: entry.path, directoryHint: .isDirectory)
        case .gitHub:
            let indexURL = try resolvedIndexURL(for: source)
            return indexURL.deletingLastPathComponent().appending(path: entry.path, directoryHint: .isDirectory)
        case .localFolder:
            return URL(fileURLWithPath: source.location, isDirectory: true)
                .appending(path: entry.path, directoryHint: .isDirectory)
        }
    }

    private func planningDocumentation(
        for action: SkillAction,
        in skill: InstalledSkill
    ) -> String {
        let lines = skill.documentation
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        guard lines.isEmpty == false else {
            return ""
        }

        let header = "Action: \(action.action)"
        let cappedLines = Array(lines.prefix(16))
        return ([header] + cappedLines).joined(separator: "\n")
    }
}
