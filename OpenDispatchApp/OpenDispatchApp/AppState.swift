import CapabilityRegistry
import Combine
import ExternalProviders
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

struct ProviderOption: Identifiable, Hashable {
    let id: String
    let name: String
}

enum BackendSelection: String, CaseIterable, Identifiable {
    case ruleBased = "rule_based"
    case appleFoundation = "apple_foundation"
    case embeddingRouter = "embedding_router"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ruleBased:
            "Rule-Based"
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
    @Published var commandInput = AppState.defaultDispatchCommand
    @Published var lastPlanJSON = ""
    @Published var executionLogs: [String] = []
    @Published var lastError: String?
    @Published var validationMessages: [String] = []
    @Published var pendingConfirmation: PendingConfirmation?
    @Published var pendingDestinationChoice: PendingDestinationChoice?
    @Published var providerOptions: [String: [ProviderOption]] = [:]
    @Published var captureModeRequested = false
    @Published var backendSelection: BackendSelection
    @Published var escalationEnabled: Bool
    @Published var dryRunEnabled: Bool
    @Published var compileStatus: CompileStatus = .notCompiled
    @Published var compiledManifests: [YAMLSkillManifest] = []
    @Published var lastMatchCandidates: [MatchCandidate] = []

    let modelContainer: ModelContainer
    private(set) var compiledIndex: CompiledIndex?

    private let eventStore: SwiftDataDispatchEventStore
    private let localLogSink: SwiftDataLocalLogSink
    private let urlHandler = UIApplicationURLHandler()
    private let defaults = UserDefaults.standard
    private let settingsKey = "OpenDispatch.Settings"
    private let launchPayloadKey = "OpenDispatch.Launch.Payload"
    private let legacyLaunchCommandKey = "OpenDispatch.Launch.Command"
    private let legacyLaunchCaptureKey = "OpenDispatch.Launch.Capture"
    private var hasBootstrapped = false
    private var providerPreferences: [String: String]

    private static let defaultDispatchCommand = "Unlock my car"

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        eventStore = SwiftDataDispatchEventStore(modelContainer: modelContainer)
        localLogSink = SwiftDataLocalLogSink(modelContainer: modelContainer)

        let stored = defaults.dictionary(forKey: settingsKey) ?? [:]
        let defaultBackend: BackendSelection = AppleFoundationBackend.isAvailableOnCurrentDevice
            ? .appleFoundation
            : .ruleBased
        backendSelection = BackendSelection(rawValue: stored["backendSelection"] as? String ?? "") ?? defaultBackend
        escalationEnabled = stored["escalationEnabled"] as? Bool ?? false
        dryRunEnabled = stored["dryRunEnabled"] as? Bool ?? false
        providerPreferences = stored["providerPreferences"] as? [String: String] ?? [:]
    }

    func bootstrap() async {
        guard hasBootstrapped == false else { return }
        hasBootstrapped = true
        await ensureDefaultRepository()
        await compileSkillIndex()
        await refreshProviderOptions()
        await consumeLaunchRequestIfNeeded()
        if ProcessInfo.processInfo.arguments.contains("--start-listening-on-launch") {
            captureModeRequested = true
        }
    }

    func compileSkillIndex() async {
        // Try loading cached index first
        if let cached = try? CompiledIndexStore.load(from: CompiledIndexStore.defaultURL()) {
            compiledIndex = cached
            compiledManifests = loadYAMLManifests()
            let skillCount = Set(cached.entries.map(\.skillID)).count
            compileStatus = .compiled(
                entryCount: cached.entries.count,
                skillCount: skillCount,
                timestamp: cached.compiledAt
            )
            appendLog("Loaded cached index: \(cached.entries.count) embeddings from \(skillCount) skills")

            if backendSelection != .embeddingRouter {
                backendSelection = .embeddingRouter
                persistSettings()
            }
            return
        }

        // No cache — compile fresh
        await recompileSkillIndex()
    }

    func recompileSkillIndex() async {
        compileStatus = .compiling(progress: "Loading YAML skills...")
        appendLog("Starting skill compilation...")

        do {
            let manifests = loadYAMLManifests()

            guard manifests.isEmpty == false else {
                compileStatus = .failed("No YAML skills found")
                appendLog("No YAML skills found to compile")
                return
            }

            compiledManifests = manifests
            let totalExamples = manifests.flatMap(\.actions).flatMap(\.examples).count
            compileStatus = .compiling(progress: "Embedding \(totalExamples) examples...")

            let compiler = SkillCompiler(languages: ["en"])
            let index = try compiler.compile(manifests: manifests)

            // Cache to disk
            try CompiledIndexStore.save(index, to: CompiledIndexStore.defaultURL())
            appendLog("Cached compiled index to disk")

            compiledIndex = index
            let skillCount = Set(index.entries.map(\.skillID)).count
            compileStatus = .compiled(
                entryCount: index.entries.count,
                skillCount: skillCount,
                timestamp: index.compiledAt
            )
            appendLog("Compiled \(index.entries.count) embeddings from \(skillCount) skills")

            if backendSelection != .embeddingRouter {
                backendSelection = .embeddingRouter
                persistSettings()
                appendLog("Switched to Compiled Embedding backend")
            }
        } catch {
            compileStatus = .failed(error.localizedDescription)
            appendLog("Compilation failed: \(error.localizedDescription)")
        }
    }

    private func loadYAMLManifests() -> [YAMLSkillManifest] {
        var manifests: [YAMLSkillManifest] = []

        if let yamlURLs = Bundle.main.urls(forResourcesWithExtension: "yaml", subdirectory: nil) {
            appendLog("Found \(yamlURLs.count) YAML files in bundle")
            for url in yamlURLs {
                if let manifest = try? YAMLSkillParser.parse(contentsOf: url) {
                    if manifests.contains(where: { $0.skillID == manifest.skillID }) == false {
                        manifests.append(manifest)
                        appendLog("Loaded skill: \(manifest.name) (\(manifest.actions.count) actions)")
                    }
                }
            }
        } else {
            appendLog("No .yaml files found in app bundle")
        }

        return manifests
    }

    func submitCurrentInput(source: RouterRequestSource = .text) async {
        await submit(commandInput, source: source)
    }

    func submit(_ rawInput: String, source: RouterRequestSource) async {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.isEmpty == false else { return }

        do {
            appendLog("Using \(backendSelection.title) planner")
            let runtime = try await makeRuntime()
            let request = RouterRequest(rawInput: input, source: source)
            let resolution = try await runtime.router.route(
                request: request,
                availableSkills: runtime.plannerContexts,
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

            commandInput = source == .speech ? commandInput : ""
            lastError = nil
            validationMessages = runtime.validationMessages
            await refreshProviderOptions(using: runtime.capabilityRegistry)
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

            learnPreferenceIfNeeded(providerID: option.providerID, for: pendingDestinationChoice.plan)
            self.pendingDestinationChoice = nil
        } catch {
            lastError = error.localizedDescription
            appendLog("Destination selection failed: \(error.localizedDescription)")
        }
    }

    func dismissPendingDestinationChoice() {
        pendingDestinationChoice = nil
    }

    func importSkillDirectories(_ urls: [URL]) async {
        do {
            let skillService = try makeSkillService()
            let context = ModelContext(modelContainer)
            var messages: [String] = []

            for originalURL in urls {
                let accessed = originalURL.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        originalURL.stopAccessingSecurityScopedResource()
                    }
                }

                let loaded = await skillService.loadSkillPack(at: originalURL)
                if let installed = skillService.installableSkill(from: loaded) {
                    let descriptor = FetchDescriptor<InstalledSkillRecord>(
                        predicate: #Predicate { $0.id == installed.id }
                    )
                    if let existing = (try? context.fetch(descriptor))?.first {
                        existing.name = installed.manifest.displayName
                        existing.providerName = installed.manifest.displayName
                        existing.providerID = installed.manifest.resolvedProviderID
                        existing.capability = installed.manifest.primaryCapability?.rawValue ?? ""
                        existing.manifestJSON = JSONCodec.encodeString(installed.manifest)
                        existing.documentation = installed.documentation
                        existing.sourceLocation = installed.sourceLocation
                        existing.installedAt = installed.installedAt
                        existing.validationErrorsJSON = nil
                    } else {
                        context.insert(InstalledSkillRecord(skill: installed))
                    }
                    messages.append("Imported \(installed.manifest.displayName)")
                } else {
                    messages.append(contentsOf: loaded.validationErrors.map(\.description))
                }
            }

            try context.save()
            validationMessages = messages
            await refreshProviderOptions()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func addRepository(name: String, kind: RepositorySourceKind, location: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false, trimmedLocation.isEmpty == false else { return }

        let context = ModelContext(modelContainer)
        context.insert(
            RepositorySourceRecord(
                name: trimmedName,
                kind: kind.rawValue,
                location: trimmedLocation
            )
        )
        try? context.save()
    }

    func refreshRepositories() async {
        do {
            let skillService = try makeSkillService()
            let context = ModelContext(modelContainer)
            let repositories = try context.fetch(FetchDescriptor<RepositorySourceRecord>())

            for repository in repositories {
                guard let source = repository.repositorySource else { continue }
                do {
                    let index = try await skillService.repositoryIndex(for: source)
                    repository.lastRefreshedAt = Date()
                    repository.lastError = nil
                    repository.discoveredSkillsCount = index.skills.count
                } catch {
                    repository.lastRefreshedAt = Date()
                    repository.lastError = error.localizedDescription
                }
            }
            try context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func selectedProvider(for capability: String) -> String {
        providerPreferences[capability] ?? ""
    }

    func destinationPreferenceKeys() -> [String] {
        providerPreferences.keys
            .filter { preferenceKey in
                providerOptions.keys.contains { capability in
                    preferenceKey.hasPrefix("\(capability).")
                }
            }
            .sorted()
    }

    func displayTitle(for preferenceKey: String) -> String {
        for capability in providerOptions.keys.sorted(by: { $0.count > $1.count }) where preferenceKey.hasPrefix("\(capability).") {
            let suffix = preferenceKey.dropFirst(capability.count + 1)
            return "\(capability) (\(suffix))"
        }
        return preferenceKey
    }

    func availableProviderOptions(for preferenceKey: String) -> [ProviderOption] {
        for capability in providerOptions.keys.sorted(by: { $0.count > $1.count }) where preferenceKey.hasPrefix("\(capability).") {
            return providerOptions[capability] ?? []
        }
        return []
    }

    func setPreferredProvider(_ providerID: String, for capability: String) {
        if providerID.isEmpty {
            providerPreferences.removeValue(forKey: capability)
        } else {
            providerPreferences[capability] = providerID
        }
        persistSettings()
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

    private func ensureDefaultRepository() async {
        let context = ModelContext(modelContainer)
        let existing = (try? context.fetch(FetchDescriptor<RepositorySourceRecord>())) ?? []
        guard existing.isEmpty else { return }

        context.insert(
            RepositorySourceRecord(
                name: "OpenDispatch Official",
                kind: RepositorySourceKind.httpIndex.rawValue,
                location: "https://skills.opendispatch.ai/index.json"
            )
        )
        try? context.save()
    }

    private func consumeLaunchRequestIfNeeded() async {
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

    private func refreshProviderOptions(using registry: CapabilityRegistry? = nil) async {
        do {
            let resolvedRegistry: CapabilityRegistry
            if let registry {
                resolvedRegistry = registry
            } else {
                let runtime = try await makeRuntime()
                resolvedRegistry = runtime.capabilityRegistry
            }
            var grouped: [String: [ProviderOption]] = [:]
            for definition in resolvedRegistry.definitions {
                grouped[definition.id.rawValue] = resolvedRegistry.providers(for: definition.id).map {
                    ProviderOption(id: $0.id, name: $0.displayName)
                }
            }
            providerOptions = grouped
        } catch {
            lastError = error.localizedDescription
        }
    }

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

    private func persistSettings() {
        defaults.set(
            [
                "backendSelection": backendSelection.rawValue,
                "escalationEnabled": escalationEnabled,
                "dryRunEnabled": dryRunEnabled,
                "providerPreferences": providerPreferences,
            ],
            forKey: settingsKey
        )
    }

    private func learnPreferenceIfNeeded(providerID: String, for plan: RouterPlan) {
        guard let domain = plan.routing?.domain else {
            return
        }
        providerPreferences["\(plan.capability.rawValue).\(domain)"] = providerID
        persistSettings()
    }

    private func makeRuntime() async throws -> RuntimeSnapshot {
        let installedSkills = try loadInstalledSkills()
        let baseRegistry = try CapabilityRegistry()
        let bootstrapSkillService = SkillRegistryService(capabilityRegistry: baseRegistry)
        let dynamicDefinitions = bootstrapSkillService.capabilityDefinitions(from: installedSkills.map(\.manifest))
        // Create providers from compiled YAML manifests
        let yamlProviders: [YAMLSkillProvider] = compiledManifests.map { manifest in
            YAMLSkillProvider(manifest: manifest, urlHandler: urlHandler)
        }

        // Register capabilities from YAML providers (with per-action destructive flags)
        let yamlDefinitions = yamlProviders.flatMap(\.capabilityDefinitions)

        let allDefinitions = baseRegistry.definitions + dynamicDefinitions + yamlDefinitions
        var seen = Set<String>()
        let uniqueDefinitions = allDefinitions.filter { seen.insert($0.id.rawValue).inserted }

        var registry = try CapabilityRegistry(definitions: uniqueDefinitions)
        let skillService = SkillRegistryService(capabilityRegistry: registry)
        let validSkills = installedSkills.filter { skillService.validate(manifest: $0.manifest).isEmpty }
        let validationMessages = installedSkills.flatMap { skill in
            skillService.validate(manifest: skill.manifest).map(\.description)
        }

        let systemProviders = SystemProviderFactory.defaultProviders(
            urlHandler: urlHandler,
            logSink: localLogSink
        )
        let externalProviders = ExternalProviderFactory.providers(
            from: validSkills,
            urlHandler: urlHandler,
            logSink: localLogSink
        )

        try SystemProviderFactory.register(providers: systemProviders, into: &registry)
        try ExternalProviderFactory.register(providers: externalProviders, into: &registry)
        for provider in yamlProviders {
            do {
                try registry.registerProvider(provider.descriptor)
            } catch CapabilityRegistryError.duplicateProvider {
                // YAML provider overlaps with an existing provider — skip
                appendLog("Skipped duplicate provider: \(provider.descriptor.id)")
            }
        }

        let backend: any RouterPlanningBackend
        switch backendSelection {
        case .ruleBased:
            backend = RuleBasedBackend()
        case .appleFoundation:
            backend = AppleFoundationBackend()
        case .embeddingRouter:
            if let index = compiledIndex {
                backend = EmbeddingRouterBackend(compiledIndex: index)
            } else {
                appendLog("No compiled index available, falling back to rule-based")
                backend = RuleBasedBackend()
            }
        }

        let router = Router(
            capabilityRegistry: registry,
            primaryBackend: backend,
            escalationBackend: escalationEnabled ? RemoteEscalationBackend() : nil,
            providers: systemProviders + externalProviders + yamlProviders,
            eventStore: eventStore
        )

        return RuntimeSnapshot(
            router: router,
            capabilityRegistry: registry,
            skillService: skillService,
            plannerContexts: skillService.planningContexts(from: validSkills),
            validationMessages: validationMessages,
            basePolicy: RoutingPolicy(
                localConfidenceThreshold: 0.55,
                allowRemoteEscalation: escalationEnabled,
                dryRun: dryRunEnabled,
                confirmationGranted: false,
                requireConfirmationForExternal: true,
                preferredProviders: Dictionary(
                    uniqueKeysWithValues: providerPreferences.map { key, value in
                        (key, [value])
                    }
                )
            )
        )
    }

    private func loadInstalledSkills() throws -> [InstalledSkill] {
        let context = ModelContext(modelContainer)
        return try context
            .fetch(FetchDescriptor<InstalledSkillRecord>(sortBy: [SortDescriptor(\.installedAt, order: .reverse)]))
            .compactMap(\.installedSkill)
    }

    private func makeSkillService() throws -> SkillRegistryService {
        SkillRegistryService(capabilityRegistry: try CapabilityRegistry())
    }

    private struct RuntimeSnapshot {
        let router: Router
        let capabilityRegistry: CapabilityRegistry
        let skillService: SkillRegistryService
        let plannerContexts: [PlannerSkillContext]
        let validationMessages: [String]
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
