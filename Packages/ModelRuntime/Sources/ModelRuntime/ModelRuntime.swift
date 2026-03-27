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
