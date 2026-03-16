import CapabilityRegistry
import Executors
import Foundation
import RouterCore
import SkillRegistry

/// A DispatchProvider backed by a YAML skill manifest.
/// Each YAML skill registers as a single provider with all its actions as capabilities.
/// Execution goes through ShortcutsExecutor using the action's shortcut_arguments.
///
/// Confirmation behavior is per-action: each action in the YAML can specify
/// `confirmation: required | none | destructive_only`. The provider uses
/// `destructiveOnly` as its base behavior, and marks individual capabilities
/// as destructive based on the action's confirmation setting.
struct YAMLSkillProvider: DispatchProvider {
    let descriptor: ProviderDescriptor

    /// Base confirmation behavior — individual actions override via
    /// capability destructiveByDefault flags.
    let confirmationBehavior: ConfirmationBehavior = .destructiveOnly

    private let manifest: YAMLSkillManifest
    private let shortcutsExecutor: ShortcutsExecutor

    init(manifest: YAMLSkillManifest, urlHandler: any URLHandling) {
        self.manifest = manifest
        self.shortcutsExecutor = ShortcutsExecutor(urlHandler: urlHandler)
        self.descriptor = ProviderDescriptor(
            id: manifest.skillID,
            displayName: manifest.name,
            kind: .external,
            priority: 70,
            capabilities: manifest.actions.map { CapabilityID(rawValue: $0.id) }
        )
    }

    /// Returns capability definitions with destructiveByDefault set based on
    /// each action's confirmation field.
    var capabilityDefinitions: [CapabilityDefinition] {
        manifest.actions.map { action in
            let destructive: Bool
            switch action.confirmation {
            case .required:
                destructive = true
            case .some(.none):
                destructive = false
            case .destructiveOnly, nil:
                destructive = false
            }
            return CapabilityDefinition(
                id: CapabilityID(rawValue: action.id),
                title: action.title,
                summary: action.description ?? action.title,
                destructiveByDefault: destructive
            )
        }
    }

    func validate(plan: RouterPlan) throws {
        guard manifest.actions.contains(where: { $0.id == plan.capability.rawValue }) else {
            throw RouterError.providerValidationFailed(
                "\(descriptor.id) does not support \(plan.capability.rawValue)"
            )
        }
    }

    func execute(plan: RouterPlan, mode: ExecutionMode) async -> ExecutionResult {
        guard let action = manifest.actions.first(where: { $0.id == plan.capability.rawValue }) else {
            return .failure("No action found for \(plan.capability.rawValue)")
        }

        // Per-action confirmation: if action says "none", skip confirmation
        // even if the router asked for it. This is handled by the Router's
        // requiresConfirmation check against destructiveByDefault.
        // Actions with confirmation: required are marked destructiveByDefault=true,
        // so the Router's destructiveOnly check will trigger confirmation.

        guard let shortcutName = manifest.bridgeShortcut else {
            return .failure("No bridge shortcut configured for \(manifest.name)")
        }

        // Build payload from shortcut_arguments, substituting any {{placeholder}} values
        var payload = action.shortcutArguments ?? [:]
        for (key, value) in payload {
            if let template = value.stringValue, template.hasPrefix("{{"), template.hasSuffix("}}") {
                let paramName = String(template.dropFirst(2).dropLast(2))
                if let extracted = plan.parameters[paramName] {
                    payload[key] = extracted
                }
            }
        }

        return await shortcutsExecutor.execute(
            shortcutName: shortcutName,
            parameters: payload,
            mode: mode
        )
    }
}
