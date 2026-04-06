import CapabilityRegistry
import Combine
import Executors
import Foundation
import ModelRuntime
import RouterCore
import SkillCompiler
import SkillRegistry
import SwiftData
import SwiftUI
import SystemProviders
import UIKit

enum BackendSelection: String, CaseIterable, Identifiable {
    case appleFoundation = "apple_foundation"
    case embeddingRouter = "embedding_router"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleFoundation:
            "Apple Foundation"
        case .embeddingRouter:
            "Compiled Embedding"
        }
    }
}

enum CompileStatus: Equatable {
    case notCompiled
    case compiling(progress: String)
    case compiled(entryCount: Int, skillCount: Int, timestamp: Date)
    case failed(String)

    static func == (lhs: CompileStatus, rhs: CompileStatus) -> Bool {
        switch (lhs, rhs) {
        case (.notCompiled, .notCompiled): true
        case let (.compiling(a), .compiling(b)): a == b
        case let (.compiled(a1, a2, a3), .compiled(b1, b2, b3)): a1 == b1 && a2 == b2 && a3 == b3
        case let (.failed(a), .failed(b)): a == b
        default: false
        }
    }
}

struct PendingConfirmation: Identifiable {
    let id = UUID()
    let request: RouterRequest
    let plan: RouterPlan
    let providerID: String
    let providerName: String
}

struct PendingDestinationChoice: Identifiable {
    let id = UUID()
    let request: RouterRequest
    let plan: RouterPlan
    let options: [DestinationOption]
}

@MainActor
final class AppState: ObservableObject {
    static weak var shared: AppState?
    @Published var commandInput = AppState.defaultDispatchCommand
    @Published var lastPlanJSON = ""
    @Published var executionLogs: [String] = []
    @Published var lastError: String?
    @Published var pendingConfirmation: PendingConfirmation?
    @Published var pendingDestinationChoice: PendingDestinationChoice?
    @Published var captureModeRequested = false
    @Published var lastMatchCandidates: [MatchCandidate] = []
    @Published var wizardPromptSkill: YAMLSkillManifest?

    let modelContainer: ModelContainer
    let compiler: SkillCompilationManager
    let settings: SettingsStore
    let repositories: RepositoryManager

    private let eventStore: SwiftDataDispatchEventStore
    private let localLogSink: SwiftDataLocalLogSink
    private let urlHandler = UIApplicationURLHandler()
    private let launchPayloadKey = "OpenDispatch.Launch.Payload"
    private let legacyLaunchCommandKey = "OpenDispatch.Launch.Command"
    private let legacyLaunchCaptureKey = "OpenDispatch.Launch.Capture"
    private var hasBootstrapped = false

    private static let defaultDispatchCommand = "Unlock my car"

    init(
        modelContainer: ModelContainer,
        compiler: SkillCompilationManager,
        settings: SettingsStore,
        repositories: RepositoryManager
    ) {
        self.modelContainer = modelContainer
        self.compiler = compiler
        self.settings = settings
        self.repositories = repositories
        eventStore = SwiftDataDispatchEventStore(modelContainer: modelContainer)
        localLogSink = SwiftDataLocalLogSink(modelContainer: modelContainer)

        // Wire logging from services into execution logs
        compiler.log = { [weak self] in self?.appendLog($0) }
        repositories.log = { [weak self] in self?.appendLog($0) }

        AppState.shared = self
    }

    func bootstrap() async {
        guard hasBootstrapped == false else { return }
        hasBootstrapped = true
        await repositories.ensureDefaultRepository()
        await compiler.compileSkillIndex()
        if let runtime = try? await makeRuntime() {
            settings.refreshProviderOptions(using: runtime.capabilityRegistry)
        }
        await consumeLaunchRequestIfNeeded()
        if ProcessInfo.processInfo.arguments.contains("--start-listening-on-launch") {
            captureModeRequested = true
        }
    }

    func submitCurrentInput(source: RouterRequestSource = .text) async {
        await submit(commandInput, source: source)
    }

    func submit(_ rawInput: String, source: RouterRequestSource) async {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.isEmpty == false else { return }

        do {
            appendLog("Input: \"\(input)\"")
            appendLog("Using \(settings.backendSelection.title) planner")
            let runtime = try await makeRuntime()
            let request = RouterRequest(rawInput: input, source: source)
            let resolution = try await runtime.router.route(
                request: request,
                availableSkills: [],
                policy: runtime.policy
            )
            lastPlanJSON = try resolution.plan.prettyPrintedJSON()
            lastMatchCandidates = resolution.plan.matchCandidates ?? []
            appendLog("Planned \(resolution.plan.capability.rawValue) via \(resolution.providerDisplayName)")

            if resolution.confirmationRequired {
                pendingConfirmation = PendingConfirmation(
                    request: request,
                    plan: resolution.plan,
                    providerID: resolution.providerID,
                    providerName: resolution.providerDisplayName
                )
                pendingDestinationChoice = nil
                appendLog("Awaiting confirmation for \(resolution.providerDisplayName)")
            } else {
                pendingConfirmation = nil
                pendingDestinationChoice = nil
                appendLog(executionLogMessage(for: resolution.result))
            }

            lastError = nil
            settings.refreshProviderOptions(using: runtime.capabilityRegistry)
        } catch {
            if let routerError = error as? RouterError,
               case let .ambiguousProviders(options, plan) = routerError {
                pendingDestinationChoice = PendingDestinationChoice(
                    request: RouterRequest(rawInput: input, source: source),
                    plan: plan,
                    options: options
                )
                pendingConfirmation = nil
                lastPlanJSON = (try? plan.prettyPrintedJSON()) ?? ""
                appendLog("Awaiting destination selection for \(plan.capability.rawValue)")
                return
            }
            lastError = error.localizedDescription
            appendLog("Routing error: \(error.localizedDescription)")
        }
    }

    func confirmPendingAction() async {
        guard let pendingConfirmation else { return }

        do {
            let runtime = try await makeRuntime()
            let resolution = try await runtime.router.executeResolvedPlan(
                request: pendingConfirmation.request,
                plan: pendingConfirmation.plan,
                providerID: pendingConfirmation.providerID,
                policy: runtime.policyWithConfirmation
            )
            lastPlanJSON = try resolution.plan.prettyPrintedJSON()
            appendLog(executionLogMessage(for: resolution.result, confirmed: true))
            self.pendingConfirmation = nil
        } catch {
            lastError = error.localizedDescription
            appendLog("Confirmation failed: \(error.localizedDescription)")
        }
    }

    func dismissPendingConfirmation() {
        pendingConfirmation = nil
    }

    func choosePendingDestination(_ option: DestinationOption) async {
        guard let pendingDestinationChoice else { return }

        do {
            let runtime = try await makeRuntime()
            let resolution = try await runtime.router.executeResolvedPlan(
                request: pendingDestinationChoice.request,
                plan: pendingDestinationChoice.plan,
                providerID: option.providerID,
                policy: runtime.policy
            )
            lastPlanJSON = try resolution.plan.prettyPrintedJSON()
            if resolution.confirmationRequired {
                pendingConfirmation = PendingConfirmation(
                    request: pendingDestinationChoice.request,
                    plan: pendingDestinationChoice.plan,
                    providerID: option.providerID,
                    providerName: option.providerDisplayName
                )
                appendLog("Destination selected: \(option.providerDisplayName)")
                appendLog("Awaiting confirmation for \(option.providerDisplayName)")
            } else {
                appendLog(executionLogMessage(for: resolution.result))
            }

            self.pendingDestinationChoice = nil
        } catch {
            lastError = error.localizedDescription
            appendLog("Destination selection failed: \(error.localizedDescription)")
        }
    }

    func dismissPendingDestinationChoice() {
        pendingDestinationChoice = nil
    }

    // MARK: - Logging

    private func appendLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let entry = "[\(timestamp)] \(message)"
        executionLogs.insert(entry, at: 0)
        print("[OpenDispatch] \(message)")
        if executionLogs.count > 50 {
            executionLogs = Array(executionLogs.prefix(50))
        }
    }

    private func executionLogMessage(
        for result: ExecutionResult,
        confirmed: Bool = false
    ) -> String {
        let prefix = confirmed ? "Confirmed execution" : "Execution"
        if result.success == false {
            return "\(prefix) failed: \(result.failureReason ?? "Unknown error")"
        }

        if result.metadata["status"] == .string("dry_run") {
            let payloadSuffix = dryRunPayloadSuffix(for: result)
            if let shortcutName = result.metadata["shortcut_name"]?.stringValue {
                return "\(prefix) dry run only: would open shortcut \(shortcutName)\(payloadSuffix)"
            }
            if let url = result.metadata["url"]?.stringValue {
                return "\(prefix) dry run only: would open \(url)\(payloadSuffix)"
            }
            return "\(prefix) dry run only\(payloadSuffix)"
        }

        if let shortcutName = result.metadata["shortcut_name"]?.stringValue {
            return "\(prefix) opened shortcut \(shortcutName)"
        }

        if let url = result.metadata["url"]?.stringValue {
            return "\(prefix) opened \(url)"
        }

        return "\(prefix) succeeded"
    }

    private func dryRunPayloadSuffix(for result: ExecutionResult) -> String {
        guard let payload = result.toolCall?.payload,
              payload.isEmpty == false,
              let payloadJSON = compactJSONString(for: payload) else {
            return ""
        }

        return " with payload \(payloadJSON)"
    }

    private func compactJSONString(for payload: [String: JSONValue]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let data = try? encoder.encode(payload) else {
            return nil
        }

        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Launch

    private func consumeLaunchRequestIfNeeded() async {
        let defaults = UserDefaults.standard
        if let payloadData = defaults.data(forKey: launchPayloadKey),
           let payload = try? JSONDecoder().decode(AppLaunchPayload.self, from: payloadData) {
            if payload.request.rawInput.isEmpty == false {
                commandInput = payload.request.rawInput
            }
            if let initialPlanJSON = payload.initialPlanJSON, initialPlanJSON.isEmpty == false {
                lastPlanJSON = initialPlanJSON
            }
            captureModeRequested = payload.startListening
            defaults.removeObject(forKey: launchPayloadKey)
            return
        }

        if let command = defaults.string(forKey: legacyLaunchCommandKey), command.isEmpty == false {
            commandInput = command
            defaults.removeObject(forKey: legacyLaunchCommandKey)
        }
        if defaults.bool(forKey: legacyLaunchCaptureKey) {
            captureModeRequested = true
            defaults.removeObject(forKey: legacyLaunchCaptureKey)
        }
    }

    // MARK: - Runtime

    private func makeRuntime() async throws -> RuntimeSnapshot {
        let nativeExecutors = NativeExecutorRegistry(executors: [
            "apple_reminders": RemindersNativeExecutor(store: EventKitReminderStore()),
            "apple_calendar": CalendarNativeExecutor(store: EventKitCalendarStore()),
            "apple_notes": NotesNativeExecutor(clipboard: SystemClipboard(), urlHandler: urlHandler),
            "apple_shortcuts": ShortcutsRunNativeExecutor(urlHandler: urlHandler),
        ])

        let yamlProviders: [YAMLSkillProvider] = compiler.compiledManifests.map { manifest in
            let executor: any SkillExecutor
            if manifest.source == .bundle,
               let native = nativeExecutors.executor(for: manifest.skillID) {
                executor = native
            } else {
                let actionArguments = Dictionary(
                    uniqueKeysWithValues: manifest.actions.compactMap { action in
                        action.shortcutArguments.map { (action.id, $0) }
                    }
                )
                executor = ShortcutsBridgeExecutor(
                    bridgeShortcut: manifest.bridgeShortcut,
                    actionArguments: actionArguments,
                    urlHandler: urlHandler
                )
            }
            return YAMLSkillProvider(manifest: manifest, executor: executor)
        }

        let yamlDefinitions = yamlProviders.flatMap(\.capabilityDefinitions)
        let baseRegistry = try CapabilityRegistry()
        let allDefinitions = baseRegistry.definitions + yamlDefinitions
        var seen = Set<String>()
        let uniqueDefinitions = allDefinitions.filter { seen.insert($0.id.rawValue).inserted }

        var registry = try CapabilityRegistry(definitions: uniqueDefinitions)

        let systemProviders: [any DispatchProvider] = [
            LocalLogProvider(sink: localLogSink),
        ]

        try SystemProviderFactory.register(providers: systemProviders, into: &registry)
        for provider in yamlProviders {
            do {
                try registry.registerProvider(provider.descriptor)
            } catch CapabilityRegistryError.duplicateProvider {
                appendLog("Skipped duplicate provider: \(provider.descriptor.id)")
            }
        }

        let backend: any RouterPlanningBackend
        switch settings.backendSelection {
        case .appleFoundation:
            backend = AppleFoundationBackend()
        case .embeddingRouter:
            if let index = compiler.compiledIndex, let paraphrase = ParaphraseBackend() {
                backend = EmbeddingRouterBackend(
                    compiledIndex: index,
                    embeddingService: EmbeddingService(backend: paraphrase)
                )
            } else {
                compiler.compileStatus = .failed("No compiled index available. Please compile skills first.")
                appendLog("No compiled index or embedding model available — compile skills to continue")
                throw NSError(
                    domain: "OpenDispatch",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No compiled index available. Please compile skills first."]
                )
            }
        }

        let router = Router(
            capabilityRegistry: registry,
            primaryBackend: backend,
            escalationBackend: settings.escalationEnabled ? RemoteEscalationBackend() : nil,
            providers: systemProviders + yamlProviders,
            eventStore: eventStore
        )

        return RuntimeSnapshot(
            router: router,
            capabilityRegistry: registry,
            basePolicy: RoutingPolicy(
                localConfidenceThreshold: 0.55,
                allowRemoteEscalation: settings.escalationEnabled,
                dryRun: settings.dryRunEnabled,
                confirmationGranted: false,
                requireConfirmationForExternal: true,
                preferredProviders: Dictionary(
                    uniqueKeysWithValues: settings.providerPreferences.map { key, value in
                        (key, [value])
                    }
                )
            )
        )
    }

    private struct RuntimeSnapshot {
        let router: Router
        let capabilityRegistry: CapabilityRegistry
        let basePolicy: RoutingPolicy

        var policy: RoutingPolicy {
            basePolicy
        }

        var policyWithConfirmation: RoutingPolicy {
            var confirmed = basePolicy
            confirmed.confirmationGranted = true
            return confirmed
        }
    }
}

struct AppLaunchPayload: Codable {
    let request: RouterRequest
    let startListening: Bool
    let initialPlanJSON: String?
}

private struct UIApplicationURLHandler: URLHandling {
    func canOpen(_ url: URL) async -> Bool {
        await MainActor.run {
            UIApplication.shared.canOpenURL(url)
        }
    }

    func open(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                UIApplication.shared.open(url, options: [:]) { success in
                    continuation.resume(returning: success)
                }
            }
        }
    }
}
