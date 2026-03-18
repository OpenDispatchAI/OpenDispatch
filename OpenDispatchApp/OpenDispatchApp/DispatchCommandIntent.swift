import AppIntents

struct DispatchCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Listening"
    static let description = IntentDescription("Open OpenDispatch and start listening for a voice command.")
    static let openAppWhenRun = true

    @Parameter(title: "Start Listening", default: true)
    var startListening: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared?.captureModeRequested = startListening
        return .result()
    }
}

struct OpenDispatchShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: DispatchCommandIntent(),
            phrases: [
                "Start listening with \(.applicationName)",
                "Open \(.applicationName)",
                "Dispatch with \(.applicationName)",
            ],
            shortTitle: "Start Listening",
            systemImageName: "mic.circle"
        )
    }
}
