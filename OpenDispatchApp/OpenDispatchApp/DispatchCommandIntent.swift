import AppIntents
import ModelRuntime
import RouterCore

struct DispatchCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Dispatch Command"
    static let description = IntentDescription("Launch OpenDispatch in capture mode.")
    static let openAppWhenRun = true

    @Parameter(title: "Command")
    var command: String?

    @Parameter(title: "Start Listening", default: true)
    var startListening: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults.standard
        let request = RouterRequest(
            rawInput: command ?? "",
            source: .actionButton
        )
        let initialPlanJSON: String?
        if request.rawInput.isEmpty {
            initialPlanJSON = nil
        } else {
            let stored = defaults.dictionary(forKey: "OpenDispatch.Settings") ?? [:]
            let defaultBackend: BackendSelection = AppleFoundationBackend.isAvailableOnCurrentDevice
                ? .appleFoundation
                : .ruleBased
            let backendSelection = BackendSelection(
                rawValue: stored["backendSelection"] as? String ?? ""
            ) ?? defaultBackend
            let backend: any ModelBackend
            switch backendSelection {
            case .ruleBased:
                backend = RuleBasedBackend()
            case .appleFoundation:
                backend = AppleFoundationBackend()
            case .embeddingRouter:
                // Intent doesn't have access to compiled index — fall back to rule-based
                backend = RuleBasedBackend()
            }

            if let plan = try? await backend.plan(request: request, availableSkills: []) {
                initialPlanJSON = try? plan.prettyPrintedJSON()
            } else {
                initialPlanJSON = nil
            }
        }
        let payload = AppLaunchPayload(
            request: request,
            startListening: startListening,
            initialPlanJSON: initialPlanJSON
        )
        let data = try JSONEncoder().encode(payload)
        defaults.set(data, forKey: "OpenDispatch.Launch.Payload")
        return .result()
    }
}

struct OpenDispatchShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: DispatchCommandIntent(),
            phrases: [
                "Dispatch with \(.applicationName)",
                "Open \(.applicationName) capture",
            ],
            shortTitle: "Dispatch",
            systemImageName: "bolt.circle"
        )
    }
}
