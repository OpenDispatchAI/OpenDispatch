import CapabilityRegistry
import Executors
import Foundation
import RouterCore
import SkillRegistry

public struct ManifestBackedProvider: DispatchProvider {
    public let descriptor: ProviderDescriptor
    public let confirmationBehavior: ConfirmationBehavior = .always

    private let skill: InstalledSkill
    private let urlSchemeExecutor: URLSchemeExecutor
    private let shortcutsExecutor: ShortcutsExecutor
    private let localLogExecutor: LocalLogExecutor

    public init(
        skill: InstalledSkill,
        urlHandler: any URLHandling,
        logSink: any LocalLogSink
    ) {
        self.skill = skill
        descriptor = ProviderDescriptor(
            id: skill.manifest.resolvedProviderID,
            displayName: skill.manifest.displayName,
            kind: .external,
            priority: skill.manifest.priority,
            capabilities: skill.manifest.capabilities
        )
        urlSchemeExecutor = URLSchemeExecutor(urlHandler: urlHandler)
        shortcutsExecutor = ShortcutsExecutor(urlHandler: urlHandler)
        localLogExecutor = LocalLogExecutor(sink: logSink)
    }

    public func validate(plan: RouterPlan) throws {
        guard let action = skill.manifest.action(for: plan.capability) else {
            throw RouterError.providerValidationFailed(descriptor.id)
        }

        switch executorKind {
        case .urlScheme:
            if skill.manifest.urlTemplate?.isEmpty != false {
                throw RouterError.providerValidationFailed(descriptor.id)
            }
        case .shortcuts:
            if skill.manifest.resolvedShortcutName?.isEmpty != false {
                throw RouterError.providerValidationFailed(descriptor.id)
            }
        case .localLog:
            break
        }

        for (parameter, expectedType) in action.paramsSchema {
            guard let value = plan.parameters[parameter] else {
                continue
            }
            if matches(expectedType: expectedType, value: value) == false {
                throw RouterError.providerValidationFailed(descriptor.id)
            }
        }
    }

    public func execute(plan: RouterPlan, mode: ExecutionMode) async -> ExecutionResult {
        switch executorKind {
        case .urlScheme:
            return await urlSchemeExecutor.execute(
                urlTemplate: skill.manifest.urlTemplate ?? "",
                parameters: plan.parameters,
                mode: mode
            )
        case .shortcuts:
            let parameters: [String: JSONValue]
            if let action = skill.manifest.action(for: plan.capability), skill.manifest.usesBridgeShortcut {
                parameters = skill.manifest.renderedBridgePayload(for: action, plan: plan)
            } else {
                parameters = plan.parameters
            }
            return await shortcutsExecutor.execute(
                shortcutName: skill.manifest.resolvedShortcutName ?? "",
                parameters: parameters,
                mode: mode
            )
        case .localLog:
            return await localLogExecutor.execute(
                rawInput: plan.parameters["text"]?.stringValue ?? skill.manifest.displayName,
                parameters: plan.parameters,
                mode: mode
            )
        }
    }

    private var executorKind: SkillExecutorKind {
        if skill.manifest.usesBridgeShortcut {
            return .shortcuts
        }
        return skill.manifest.executor ?? .localLog
    }

    private func matches(expectedType: String, value: JSONValue) -> Bool {
        switch expectedType.lowercased() {
        case "string":
            if case .string = value {
                return true
            }
            return false
        case "number":
            if case .number = value {
                return true
            }
            if case .integer = value {
                return true
            }
            return false
        case "integer", "int":
            if case .integer = value {
                return true
            }
            return false
        case "bool", "boolean":
            if case .bool = value {
                return true
            }
            return false
        case "object", "json":
            if case .object = value {
                return true
            }
            return false
        case "array":
            if case .array = value {
                return true
            }
            return false
        default:
            return true
        }
    }
}

public enum ExternalProviderFactory {
    public static func providers(
        from skills: [InstalledSkill],
        urlHandler: any URLHandling,
        logSink: any LocalLogSink
    ) -> [any DispatchProvider] {
        skills.map { skill in
            ManifestBackedProvider(
                skill: skill,
                urlHandler: urlHandler,
                logSink: logSink
            )
        }
    }

    public static func register(
        providers: [any DispatchProvider],
        into registry: inout CapabilityRegistry
    ) throws {
        for provider in providers {
            try registry.registerProvider(provider.descriptor)
        }
    }
}
