import CapabilityRegistry
import Foundation

public enum JSONValue: Hashable, Codable, Sendable {
    case string(String)
    case number(Double)
    case integer(Int)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public var stringValue: String? {
        switch self {
        case let .string(value):
            value
        case let .integer(value):
            String(value)
        case let .number(value):
            String(value)
        case let .bool(value):
            String(value)
        default:
            nil
        }
    }
}

public enum RouterRequestSource: String, Codable, Hashable, Sendable {
    case text
    case speech
    case actionButton
    case appIntent
}

public struct RouterRequest: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let rawInput: String
    public let source: RouterRequestSource
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        rawInput: String,
        source: RouterRequestSource = .text,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.rawInput = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source
        self.timestamp = timestamp
    }
}

public struct PlannerSkillContext: Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let capability: CapabilityID
    public let providerID: String
    public let examples: [String]
    public let documentation: String

    public init(
        id: String,
        name: String,
        capability: CapabilityID,
        providerID: String,
        examples: [String] = [],
        documentation: String = ""
    ) {
        self.id = id
        self.name = name
        self.capability = capability
        self.providerID = providerID
        self.examples = examples
        self.documentation = documentation
    }
}

// MARK: - MatchCandidate

public struct MatchCandidate: Hashable, Codable, Sendable {
    public let skillID: String
    public let skillName: String
    public let actionID: String
    public let actionTitle: String
    public let capability: CapabilityID
    public let distance: Double
    public let confidence: Double

    public init(
        skillID: String,
        skillName: String,
        actionID: String,
        actionTitle: String,
        capability: CapabilityID,
        distance: Double,
        confidence: Double
    ) {
        self.skillID = skillID
        self.skillName = skillName
        self.actionID = actionID
        self.actionTitle = actionTitle
        self.capability = capability
        self.distance = distance
        self.confidence = confidence
    }
}

// MARK: - ParameterSchema

public struct ParameterSchema: Hashable, Codable, Sendable {
    public let name: String
    public let type: String
    public let description: String?
    public let required: Bool

    public init(
        name: String,
        type: String,
        description: String? = nil,
        required: Bool = true
    ) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
    }
}

// MARK: - EntrySource

public enum EntrySource: String, Hashable, Codable, Sendable {
    case builtin
    case user
}

// MARK: - CompiledEntry

public struct CompiledEntry: Hashable, Codable, Sendable {
    public let embedding: [Float]
    public let skillID: String
    public let skillName: String
    public let actionID: String
    public let actionTitle: String
    public let capability: CapabilityID
    public let parameters: [ParameterSchema]?
    public let shortcutArguments: [String: JSONValue]?
    public let originalExample: String
    public let language: String
    public let isNegative: Bool
    public let source: EntrySource

    public var requiresParameterExtraction: Bool {
        guard let parameters else { return false }
        return !parameters.isEmpty
    }

    public init(
        embedding: [Float],
        skillID: String,
        skillName: String,
        actionID: String,
        actionTitle: String,
        capability: CapabilityID,
        parameters: [ParameterSchema]?,
        shortcutArguments: [String: JSONValue]?,
        originalExample: String,
        language: String,
        isNegative: Bool = false,
        source: EntrySource = .builtin
    ) {
        self.embedding = embedding
        self.skillID = skillID
        self.skillName = skillName
        self.actionID = actionID
        self.actionTitle = actionTitle
        self.capability = capability
        self.parameters = parameters
        self.shortcutArguments = shortcutArguments
        self.originalExample = originalExample
        self.language = language
        self.isNegative = isNegative
        self.source = source
    }
}

// MARK: - CompiledIndex

public struct CompiledIndex: Hashable, Codable, Sendable {
    /// Bump this when the index format changes. Cached indexes with a
    /// different version are discarded and recompiled automatically.
    public static let schemaVersion = 2

    public let schemaVersion: Int
    public let entries: [CompiledEntry]
    public let compiledAt: Date

    public init(entries: [CompiledEntry], compiledAt: Date = Date()) {
        self.schemaVersion = Self.schemaVersion
        self.entries = entries
        self.compiledAt = compiledAt
    }

    public func nearestNeighbors(to query: [Float], count: Int) -> [MatchCandidate] {
        // Score all positive entries
        let positiveScored = entries.filter { $0.isNegative == false }
            .map { entry -> (entry: CompiledEntry, distance: Double) in
                (entry, cosineDistance(query, entry.embedding))
            }

        // Find closest negative example per action (if any)
        var negativePenalties: [String: Double] = [:]
        for entry in entries where entry.isNegative {
            let dist = cosineDistance(query, entry.embedding)
            let key = "\(entry.skillID)/\(entry.actionID)"
            // The closer the input is to a negative example, the bigger the penalty.
            // penalty = max(0, 1 - distance) means identical = 1.0 penalty, far away = 0
            let penalty = max(0.0, 1.0 - dist)
            if penalty > (negativePenalties[key] ?? 0) {
                negativePenalties[key] = penalty
            }
        }

        // Apply penalties: increase distance for actions with close negative matches
        let adjusted = positiveScored.map { item -> (entry: CompiledEntry, distance: Double) in
            let key = "\(item.entry.skillID)/\(item.entry.actionID)"
            if let penalty = negativePenalties[key] {
                return (item.entry, item.distance + penalty * 0.2)
            }
            return item
        }

        let sorted = adjusted.sorted { $0.distance < $1.distance }

        // Deduplicate: keep only the closest match per skill+action pair
        var seen = Set<String>()
        var candidates: [MatchCandidate] = []
        for item in sorted {
            let key = "\(item.entry.skillID)/\(item.entry.actionID)"
            guard seen.insert(key).inserted else { continue }
            let confidence = max(0.0, 1.0 - item.distance)
            candidates.append(MatchCandidate(
                skillID: item.entry.skillID,
                skillName: item.entry.skillName,
                actionID: item.entry.actionID,
                actionTitle: item.entry.actionTitle,
                capability: item.entry.capability,
                distance: item.distance,
                confidence: confidence
            ))
            if candidates.count >= count { break }
        }
        return candidates
    }

    public func entry(for candidate: MatchCandidate) -> CompiledEntry? {
        entries.first { $0.skillID == candidate.skillID && $0.actionID == candidate.actionID }
    }

    private func cosineDistance(_ a: [Float], _ b: [Float]) -> Double {
        let length = min(a.count, b.count)
        guard length > 0 else { return 1.0 }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<length {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 1.0 }

        let similarity = Double(dot / denominator)
        return 1.0 - similarity
    }
}

// MARK: - RouterPlan

public struct RouterPlan: Hashable, Codable, Sendable {
    public let capability: CapabilityID
    public let parameters: [String: JSONValue]
    public let confidence: Double
    public let title: String?
    public let suggestedProviderID: String?
    public let matchCandidates: [MatchCandidate]?

    public init(
        capability: CapabilityID,
        parameters: [String: JSONValue],
        confidence: Double,
        title: String? = nil,
        suggestedProviderID: String? = nil,
        matchCandidates: [MatchCandidate]? = nil
    ) {
        self.capability = capability
        self.parameters = parameters
        self.confidence = confidence
        self.title = title
        self.suggestedProviderID = suggestedProviderID
        self.matchCandidates = matchCandidates
    }

    public init(
        capability: CapabilityID,
        parameters: [String: JSONValue],
        confidence: Double,
        suggestedProviderID: String?
    ) {
        self.init(
            capability: capability,
            parameters: parameters,
            confidence: confidence,
            title: nil,
            suggestedProviderID: suggestedProviderID,
            matchCandidates: nil
        )
    }
}

public struct ToolCall: Hashable, Codable, Sendable {
    public let executorID: String
    public let payload: [String: JSONValue]

    public init(executorID: String, payload: [String: JSONValue]) {
        self.executorID = executorID
        self.payload = payload
    }
}

public enum ExecutionMode: String, Codable, Hashable, Sendable {
    case dryRun
    case live
}

public struct ExecutionResult: Hashable, Codable, Sendable {
    public let success: Bool
    public let failureReason: String?
    public let metadata: [String: JSONValue]
    public let toolCall: ToolCall?

    public init(
        success: Bool,
        failureReason: String? = nil,
        metadata: [String: JSONValue] = [:],
        toolCall: ToolCall? = nil
    ) {
        self.success = success
        self.failureReason = failureReason
        self.metadata = metadata
        self.toolCall = toolCall
    }

    public static func success(
        metadata: [String: JSONValue] = [:],
        toolCall: ToolCall? = nil
    ) -> ExecutionResult {
        ExecutionResult(success: true, metadata: metadata, toolCall: toolCall)
    }

    public static func failure(
        _ reason: String,
        metadata: [String: JSONValue] = [:],
        toolCall: ToolCall? = nil
    ) -> ExecutionResult {
        ExecutionResult(success: false, failureReason: reason, metadata: metadata, toolCall: toolCall)
    }
}

// MARK: - SkillExecutor

public protocol SkillExecutor: Sendable {
    func execute(plan: RouterPlan, mode: ExecutionMode) async -> ExecutionResult
}

public struct DispatchEvent: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let rawInput: String
    public let routerPlan: RouterPlan
    public let providerID: String
    public let parameters: [String: JSONValue]
    public let result: ExecutionResult

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        rawInput: String,
        routerPlan: RouterPlan,
        providerID: String,
        parameters: [String: JSONValue],
        result: ExecutionResult
    ) {
        self.id = id
        self.timestamp = timestamp
        self.rawInput = rawInput
        self.routerPlan = routerPlan
        self.providerID = providerID
        self.parameters = parameters
        self.result = result
    }
}

public struct RoutingPolicy: Hashable, Codable, Sendable {
    public var localConfidenceThreshold: Double
    public var allowRemoteEscalation: Bool
    public var dryRun: Bool
    public var confirmationGranted: Bool
    public var requireConfirmationForExternal: Bool
    public var preferredProviders: [String: [String]]

    public init(
        localConfidenceThreshold: Double = 0.74,
        allowRemoteEscalation: Bool = false,
        dryRun: Bool = false,
        confirmationGranted: Bool = false,
        requireConfirmationForExternal: Bool = true,
        preferredProviders: [String: [String]] = [:]
    ) {
        self.localConfidenceThreshold = localConfidenceThreshold
        self.allowRemoteEscalation = allowRemoteEscalation
        self.dryRun = dryRun
        self.confirmationGranted = confirmationGranted
        self.requireConfirmationForExternal = requireConfirmationForExternal
        self.preferredProviders = preferredProviders
    }

    public func preferredProviderOrder(for capability: CapabilityID) -> [String] {
        var order: [String] = []
        for key in preferenceKeys(for: capability) {
            for providerID in preferredProviders[key] ?? [] {
                if !order.contains(providerID) {
                    order.append(providerID)
                }
            }
        }
        return order
    }

    public func preferenceKeys(for capability: CapabilityID) -> [String] {
        [capability.rawValue]
    }
}

public enum ConfirmationBehavior: Hashable, Codable, Sendable {
    case never
    case always
    case destructiveOnly
}

public protocol DispatchProvider: Sendable {
    var descriptor: ProviderDescriptor { get }
    var confirmationBehavior: ConfirmationBehavior { get }

    func validate(plan: RouterPlan) throws
    func execute(plan: RouterPlan, mode: ExecutionMode) async -> ExecutionResult
}

public protocol DispatchEventStoring: Sendable {
    func store(_ event: DispatchEvent) async throws
}

public protocol RouterPlanningBackend: Sendable {
    var id: String { get }
    func plan(
        request: RouterRequest,
        availableSkills: [PlannerSkillContext]
    ) async throws -> RouterPlan
}

public enum RouterError: Error, Equatable, Sendable, LocalizedError {
    case invalidConfidence(Double)
    case emptyInput
    case unsupportedCapability(CapabilityID)
    case noProviderFound(CapabilityID)
    case suggestedProviderUnavailable(String)
    case providerValidationFailed(String)
    case ambiguousProviders([DestinationOption], RouterPlan)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfidence(value):
            "Invalid confidence value: \(value) (must be 0-1)"
        case .emptyInput:
            "Empty input"
        case let .unsupportedCapability(id):
            "Unsupported capability: \(id.rawValue)"
        case let .noProviderFound(id):
            "No provider found for capability: \(id.rawValue)"
        case let .suggestedProviderUnavailable(id):
            "Suggested provider unavailable: \(id)"
        case let .providerValidationFailed(reason):
            "Provider validation failed: \(reason)"
        case let .ambiguousProviders(options, plan):
            "Ambiguous providers for \(plan.capability.rawValue): \(options.map(\.providerDisplayName).joined(separator: ", "))"
        }
    }
}

public struct DestinationOption: Identifiable, Hashable, Codable, Sendable {
    public let providerID: String
    public let providerDisplayName: String
    public let reason: String?

    public var id: String {
        providerID
    }

    public init(
        providerID: String,
        providerDisplayName: String,
        reason: String? = nil
    ) {
        self.providerID = providerID
        self.providerDisplayName = providerDisplayName
        self.reason = reason
    }
}

public enum DestinationResolution: Hashable, Codable, Sendable {
    case resolved(providerID: String)
    case ambiguous([DestinationOption])
}

public struct DestinationResolver: Sendable {
    public init() {}

    public func resolve(
        plan: RouterPlan,
        descriptors: [ProviderDescriptor],
        policy: RoutingPolicy,
        confidenceGapThreshold: Double = 0.15
    ) -> DestinationResolution {
        guard descriptors.isEmpty == false else {
            return .ambiguous([])
        }

        let preferredOrder = policy.preferredProviderOrder(for: plan.capability)
        let sortedDescriptors = descriptors.sorted {
            compare(
                lhs: $0,
                rhs: $1,
                preferredOrder: preferredOrder,
                suggestedProviderID: plan.suggestedProviderID
            )
        }

        if shouldPromptForAmbiguity(
            plan: plan,
            providers: sortedDescriptors,
            confidenceGapThreshold: confidenceGapThreshold,
            policy: policy
        ) {
            return .ambiguous(sortedDescriptors.map { descriptor in
                DestinationOption(
                    providerID: descriptor.id,
                    providerDisplayName: descriptor.displayName,
                    reason: reason(
                        for: descriptor,
                        preferredOrder: preferredOrder,
                        suggestedProviderID: plan.suggestedProviderID
                    )
                )
            })
        }

        guard let first = sortedDescriptors.first else {
            return .ambiguous([])
        }
        return .resolved(providerID: first.id)
    }

    private func shouldPromptForAmbiguity(
        plan: RouterPlan,
        providers: [ProviderDescriptor],
        confidenceGapThreshold: Double,
        policy: RoutingPolicy
    ) -> Bool {
        guard providers.count > 1 else { return false }

        if plan.suggestedProviderID != nil {
            if let candidates = plan.matchCandidates, candidates.count >= 2 {
                let gap = candidates[0].confidence - candidates[1].confidence
                if gap >= confidenceGapThreshold {
                    return false
                }
                return true
            }
            return false
        }

        let preferred = policy.preferredProviderOrder(for: plan.capability)
        if preferred.isEmpty == false { return false }

        return true
    }

    private func compare(
        lhs: ProviderDescriptor,
        rhs: ProviderDescriptor,
        preferredOrder: [String],
        suggestedProviderID: String?
    ) -> Bool {
        if lhs.id == suggestedProviderID {
            return true
        }
        if rhs.id == suggestedProviderID {
            return false
        }

        let leftIndex = preferredOrder.firstIndex(of: lhs.id) ?? Int.max
        let rightIndex = preferredOrder.firstIndex(of: rhs.id) ?? Int.max
        if leftIndex != rightIndex {
            return leftIndex < rightIndex
        }

        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }
        return lhs.displayName < rhs.displayName
    }

    private func reason(
        for descriptor: ProviderDescriptor,
        preferredOrder: [String],
        suggestedProviderID: String?
    ) -> String? {
        if descriptor.id == suggestedProviderID {
            return "Suggested by planner"
        }
        if preferredOrder.first == descriptor.id {
            return "Matched saved preference"
        }
        return nil
    }
}

public struct RouteResolution: Hashable, Codable, Sendable {
    public let request: RouterRequest
    public let plan: RouterPlan
    public let providerID: String
    public let providerDisplayName: String
    public let usedEscalation: Bool
    public let confirmationRequired: Bool
    public let executionMode: ExecutionMode
    public let result: ExecutionResult

    public init(
        request: RouterRequest,
        plan: RouterPlan,
        providerID: String,
        providerDisplayName: String,
        usedEscalation: Bool,
        confirmationRequired: Bool,
        executionMode: ExecutionMode,
        result: ExecutionResult
    ) {
        self.request = request
        self.plan = plan
        self.providerID = providerID
        self.providerDisplayName = providerDisplayName
        self.usedEscalation = usedEscalation
        self.confirmationRequired = confirmationRequired
        self.executionMode = executionMode
        self.result = result
    }
}

public actor InMemoryDispatchEventStore: DispatchEventStoring {
    private(set) var events: [DispatchEvent] = []

    public init() {}

    public func store(_ event: DispatchEvent) async throws {
        events.append(event)
    }
}

public actor Router {
    private let capabilityRegistry: CapabilityRegistry
    private let primaryBackend: any RouterPlanningBackend
    private let escalationBackend: (any RouterPlanningBackend)?
    private let eventStore: any DispatchEventStoring
    private let providersByID: [String: any DispatchProvider]
    private let destinationResolver: DestinationResolver

    public init(
        capabilityRegistry: CapabilityRegistry,
        primaryBackend: any RouterPlanningBackend,
        escalationBackend: (any RouterPlanningBackend)? = nil,
        providers: [any DispatchProvider],
        eventStore: any DispatchEventStoring,
        destinationResolver: DestinationResolver = DestinationResolver()
    ) {
        self.capabilityRegistry = capabilityRegistry
        self.primaryBackend = primaryBackend
        self.escalationBackend = escalationBackend
        self.eventStore = eventStore
        self.destinationResolver = destinationResolver
        var index: [String: any DispatchProvider] = [:]
        for provider in providers {
            index[provider.descriptor.id] = provider
        }
        providersByID = index
    }

    public func route(
        request: RouterRequest,
        availableSkills: [PlannerSkillContext] = [],
        policy: RoutingPolicy = RoutingPolicy()
    ) async throws -> RouteResolution {
        guard request.rawInput.isEmpty == false else {
            throw RouterError.emptyInput
        }

        let primaryPlan = try await primaryBackend.plan(request: request, availableSkills: availableSkills)
        let resolved = try await resolve(
            request: request,
            initialPlan: primaryPlan,
            availableSkills: availableSkills,
            policy: policy
        )
        try await persist(resolution: resolved)
        return resolved
    }

    public func executeResolvedPlan(
        request: RouterRequest,
        plan: RouterPlan,
        providerID: String,
        policy: RoutingPolicy = RoutingPolicy(confirmationGranted: true)
    ) async throws -> RouteResolution {
        let validatedPlan = try validate(plan)
        guard let provider = providersByID[providerID] else {
            throw RouterError.suggestedProviderUnavailable(providerID)
        }
        let resolution = await execute(
            request: request,
            plan: validatedPlan,
            provider: provider,
            usedEscalation: false,
            policy: policy
        )
        try await persist(resolution: resolution)
        return resolution
    }

    private func resolve(
        request: RouterRequest,
        initialPlan: RouterPlan,
        availableSkills: [PlannerSkillContext],
        policy: RoutingPolicy
    ) async throws -> RouteResolution {
        var plan = try validate(initialPlan)
        var usedEscalation = false

        if plan.confidence < policy.localConfidenceThreshold,
           policy.allowRemoteEscalation,
           let escalationBackend {
            let escalatedPlan = try await escalationBackend.plan(request: request, availableSkills: availableSkills)
            let validatedEscalation = try validate(escalatedPlan)
            if validatedEscalation.confidence > plan.confidence {
                // Preserve the primary plan's match candidates for debug visibility
                let primaryCandidates = plan.matchCandidates
                plan = RouterPlan(
                    capability: validatedEscalation.capability,
                    parameters: validatedEscalation.parameters,
                    confidence: validatedEscalation.confidence,
                    title: validatedEscalation.title,
                    suggestedProviderID: validatedEscalation.suggestedProviderID,
                    matchCandidates: validatedEscalation.matchCandidates ?? primaryCandidates
                )
                usedEscalation = true
            }
        }

        let provider = try selectProvider(for: plan, policy: policy)
        return await execute(
            request: request,
            plan: plan,
            provider: provider,
            usedEscalation: usedEscalation,
            policy: policy
        )
    }

    private func validate(_ plan: RouterPlan) throws -> RouterPlan {
        // Allow small float precision overshoot (e.g., 1.0000001)
        guard (-0.001 ... 1.001).contains(plan.confidence) else {
            throw RouterError.invalidConfidence(plan.confidence)
        }
        guard capabilityRegistry.contains(plan.capability) else {
            throw RouterError.unsupportedCapability(plan.capability)
        }
        return plan
    }

    private func selectProvider(
        for plan: RouterPlan,
        policy: RoutingPolicy
    ) throws -> any DispatchProvider {
        let descriptors = capabilityRegistry.providers(for: plan.capability)
        guard descriptors.isEmpty == false else {
            throw RouterError.noProviderFound(plan.capability)
        }

        let validDescriptors = descriptors.compactMap { descriptor -> ProviderDescriptor? in
            guard let provider = providersByID[descriptor.id] else {
                return nil
            }
            do {
                try provider.validate(plan: plan)
                return descriptor
            } catch {
                return nil
            }
        }

        guard validDescriptors.isEmpty == false else {
            throw RouterError.providerValidationFailed(plan.capability.rawValue)
        }

        switch destinationResolver.resolve(plan: plan, descriptors: validDescriptors, policy: policy) {
        case let .resolved(providerID):
            guard let provider = providersByID[providerID] else {
                throw RouterError.suggestedProviderUnavailable(providerID)
            }
            return provider
        case let .ambiguous(options):
            throw RouterError.ambiguousProviders(options, plan)
        }
    }

    private func execute(
        request: RouterRequest,
        plan: RouterPlan,
        provider: any DispatchProvider,
        usedEscalation: Bool,
        policy: RoutingPolicy
    ) async -> RouteResolution {
        let confirmationRequired = requiresConfirmation(
            provider: provider,
            capability: plan.capability,
            policy: policy
        )

        let mode: ExecutionMode = policy.dryRun ? .dryRun : .live
        let result: ExecutionResult
        if policy.dryRun {
            result = .success(
                metadata: [
                    "status": .string("dry_run"),
                    "provider": .string(provider.descriptor.id),
                ]
            )
        } else if confirmationRequired && policy.confirmationGranted == false {
            result = .success(
                metadata: [
                    "status": .string("awaiting_confirmation"),
                    "provider": .string(provider.descriptor.id),
                ]
            )
        } else {
            result = await provider.execute(plan: plan, mode: mode)
        }

        return RouteResolution(
            request: request,
            plan: plan,
            providerID: provider.descriptor.id,
            providerDisplayName: provider.descriptor.displayName,
            usedEscalation: usedEscalation,
            confirmationRequired: confirmationRequired && policy.confirmationGranted == false && policy.dryRun == false,
            executionMode: mode,
            result: result
        )
    }

    private func requiresConfirmation(
        provider: any DispatchProvider,
        capability: CapabilityID,
        policy: RoutingPolicy
    ) -> Bool {
        switch provider.confirmationBehavior {
        case .never:
            return false
        case .always:
            return true
        case .destructiveOnly:
            guard let definition = capabilityRegistry.definition(for: capability) else {
                return false
            }
            return definition.destructiveByDefault || (provider.descriptor.kind == .external && policy.requireConfirmationForExternal)
        }
    }

    private func persist(resolution: RouteResolution) async throws {
        let event = DispatchEvent(
            rawInput: resolution.request.rawInput,
            routerPlan: resolution.plan,
            providerID: resolution.providerID,
            parameters: resolution.plan.parameters,
            result: resolution.result
        )
        try await eventStore.store(event)
    }
}

public extension RouterPlan {
    func prettyPrintedJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}
