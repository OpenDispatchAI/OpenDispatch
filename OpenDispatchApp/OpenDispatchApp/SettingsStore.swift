import CapabilityRegistry
import Foundation

@MainActor @Observable final class SettingsStore {

    var backendSelection: BackendSelection
    var escalationEnabled: Bool
    var dryRunEnabled: Bool
    var confidenceGapThreshold: Double
    var providerOptions: [String: [ProviderOption]] = [:]
    private(set) var providerPreferences: [String: String]

    private let defaults = UserDefaults.standard
    private let settingsKey = "OpenDispatch.Settings"

    init() {
        let stored = defaults.dictionary(forKey: settingsKey) ?? [:]
        let defaultBackend: BackendSelection = AppleFoundationBackend.isAvailableOnCurrentDevice
            ? .appleFoundation
            : .embeddingRouter
        backendSelection = BackendSelection(rawValue: stored["backendSelection"] as? String ?? "") ?? defaultBackend
        escalationEnabled = stored["escalationEnabled"] as? Bool ?? false
        dryRunEnabled = stored["dryRunEnabled"] as? Bool ?? false
        confidenceGapThreshold = stored["confidenceGapThreshold"] as? Double ?? 0.15
        providerPreferences = stored["providerPreferences"] as? [String: String] ?? [:]
    }

    func updateBackendSelection(_ selection: BackendSelection) {
        backendSelection = selection
        persistSettings()
    }

    func updateEscalation(_ enabled: Bool) {
        escalationEnabled = enabled
        persistSettings()
    }

    func updateDryRun(_ enabled: Bool) {
        dryRunEnabled = enabled
        persistSettings()
    }

    func updateConfidenceGapThreshold(_ value: Double) {
        confidenceGapThreshold = value
        persistSettings()
    }

    func selectedProvider(for capability: String) -> String {
        providerPreferences[capability] ?? ""
    }

    func setPreferredProvider(_ providerID: String, for capability: String) {
        if providerID.isEmpty {
            providerPreferences.removeValue(forKey: capability)
        } else {
            providerPreferences[capability] = providerID
        }
        persistSettings()
    }

    func refreshProviderOptions(using registry: CapabilityRegistry) {
        var grouped: [String: [ProviderOption]] = [:]
        for definition in registry.definitions {
            grouped[definition.id.rawValue] = registry.providers(for: definition.id).map {
                ProviderOption(id: $0.id, name: $0.displayName)
            }
        }
        providerOptions = grouped
    }

    func persistSettings() {
        defaults.set(
            [
                "backendSelection": backendSelection.rawValue,
                "escalationEnabled": escalationEnabled,
                "dryRunEnabled": dryRunEnabled,
                "confidenceGapThreshold": confidenceGapThreshold,
                "providerPreferences": providerPreferences,
            ],
            forKey: settingsKey
        )
    }
}
