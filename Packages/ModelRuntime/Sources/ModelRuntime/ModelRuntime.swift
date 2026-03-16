import CapabilityRegistry
import Foundation
import RouterCore
#if canImport(FoundationModels)
import FoundationModels
#endif

public protocol ModelBackend: RouterPlanningBackend {}

public enum ModelBackendError: Error, Equatable, Sendable {
    case unavailable(String)
    case generationFailed(String)
}

extension ModelBackendError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unavailable(message):
            message
        case let .generationFailed(message):
            message
        }
    }
}

public struct RuleBasedBackend: ModelBackend {
    public let id = "rule_based"
    private let classifier = RuleBasedCapabilityClassifier()

    public init() {}

    public func plan(
        request: RouterRequest,
        availableSkills: [PlannerSkillContext]
    ) async throws -> RouterPlan {
        let raw = request.rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = raw.lowercased()

        if let skill = matchSkill(in: normalized, availableSkills: availableSkills) {
            return classifier.planForMatchedSkill(
                capability: skill.capability,
                rawInput: raw,
                normalizedInput: normalized,
                suggestedProviderID: skill.providerID
            )
        }

        if let plan = classifier.classify(rawInput: raw) {
            return plan
        }

        return classifier.fallbackPlan(rawInput: raw)
    }

    private func matchSkill(
        in normalizedInput: String,
        availableSkills: [PlannerSkillContext]
    ) -> PlannerSkillContext? {
        availableSkills.max { lhs, rhs in
            score(for: lhs, normalizedInput: normalizedInput) < score(for: rhs, normalizedInput: normalizedInput)
        }.flatMap { candidate in
            score(for: candidate, normalizedInput: normalizedInput) > 0 ? candidate : nil
        }
    }

    private func score(
        for skill: PlannerSkillContext,
        normalizedInput: String
    ) -> Int {
        var total = 0
        if normalizedInput.contains(skill.name.lowercased()) {
            total += 5
        }
        if normalizedInput.contains(skill.providerID.lowercased()) {
            total += 4
        }
        for keyword in skill.keywords where normalizedInput.contains(keyword.lowercased()) {
            total += 3
        }
        for example in skill.examples where normalizedInput.contains(example.lowercased()) {
            total += 2
        }
        return total
    }

}

public struct AppleFoundationBackend: ModelBackend {
    public let id = "apple_foundation"
    private let builder = AppleFoundationPlanBuilder()

    public init() {}

    public static var isAvailableOnCurrentDevice: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
        }
        #endif
        return false
    }

    public func plan(
        request: RouterRequest,
        availableSkills: [PlannerSkillContext]
    ) async throws -> RouterPlan {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await AppleFoundationPlanner.plan(
                request: request,
                availableSkills: availableSkills,
                builder: builder
            )
        }
        #endif

        throw ModelBackendError.unavailable(
            "Apple Foundation Models requires iOS 26 or newer on a device that supports Apple Intelligence."
        )
    }
}

public struct RemoteEscalationBackend: ModelBackend {
    public let id = "remote_escalation"

    public init() {}

    public func plan(
        request: RouterRequest,
        availableSkills: [PlannerSkillContext]
    ) async throws -> RouterPlan {
        throw ModelBackendError.unavailable("Remote escalation is disabled by default and not implemented in the MVP scaffold.")
    }
}
