import Foundation
import ModelRuntime
import SkillCompiler
import SkillRegistry
import SwiftData

@MainActor @Observable final class SkillCompilationManager {

    var compiledIndex: CompiledIndex?
    var compiledManifests: [YAMLSkillManifest] = []
    var compileStatus: CompileStatus = .notCompiled
    var configuredLanguages: [String] = ["en"]
    var orphanedUserExamples: [UserExample] = []

    var log: (String) -> Void = { message in print("[OpenDispatch] \(message)") }

    private let modelContainer: ModelContainer
    private let settings: SettingsStore
    private var recompileTask: Task<Void, Never>?

    init(modelContainer: ModelContainer, settings: SettingsStore) {
        self.modelContainer = modelContainer
        self.settings = settings
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
            log("Loaded cached index: \(cached.entries.count) embeddings from \(skillCount) skills")

            if settings.backendSelection != .embeddingRouter {
                settings.updateBackendSelection(.embeddingRouter)
            }
            return
        }

        // No cache — compile fresh
        await recompileSkillIndex()
    }

    func recompileSkillIndex() async {
        compileStatus = .compiling(progress: "Loading YAML skills...")
        orphanedUserExamples = []
        log("Starting skill compilation...")

        do {
            let manifests = loadYAMLManifests()

            guard manifests.isEmpty == false else {
                compileStatus = .failed("No YAML skills found")
                log("No YAML skills found to compile")
                return
            }

            compiledManifests = manifests
            let totalExamples = manifests.flatMap(\.actions).flatMap(\.examples).count
            compileStatus = .compiling(progress: "Embedding \(totalExamples) examples...")

            guard let backend = ParaphraseBackend() else {
                compileStatus = .failed("Embedding model failed to load")
                log("ParaphraseBackend failed to initialize — check that the model is in the bundle")
                return
            }
            let embeddingService = EmbeddingService(backend: backend)
            let compiler = SkillCompiler(languages: configuredLanguages, embeddingService: embeddingService)
            let userExamples = fetchUserExamples()
            let suppressedExamples = fetchSuppressedExamples()
            let result = try await compiler.compile(manifests: manifests, userExamples: userExamples, suppressedExamples: suppressedExamples)
            let index = result.index

            if result.orphanedExamples.isEmpty == false {
                let orphanSkills = Set(result.orphanedExamples.map(\.skillID))
                log("Warning: \(result.orphanedExamples.count) user examples reference removed skills: \(orphanSkills.joined(separator: ", "))")
                orphanedUserExamples = result.orphanedExamples
            }

            try CompiledIndexStore.save(index, to: CompiledIndexStore.defaultURL())
            log("Cached compiled index to disk")

            compiledIndex = index
            let skillCount = Set(index.entries.map(\.skillID)).count
            compileStatus = .compiled(
                entryCount: index.entries.count,
                skillCount: skillCount,
                timestamp: index.compiledAt
            )
            log("Compiled \(index.entries.count) embeddings from \(skillCount) skills")

            if settings.backendSelection != .embeddingRouter {
                settings.updateBackendSelection(.embeddingRouter)
                log("Switched to Compiled Embedding backend")
            }
        } catch {
            compileStatus = .failed(error.localizedDescription)
            log("Compilation failed: \(error.localizedDescription)")
        }
    }

    func scheduleRecompile() {
        recompileTask?.cancel()
        recompileTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await recompileSkillIndex()
        }
    }

    func loadYAMLManifests() -> [YAMLSkillManifest] {
        var manifests: [YAMLSkillManifest] = []

        // Load bundled skills (native execution eligible)
        if let bundledURL = Bundle.main.url(forResource: "BundledSkills", withExtension: nil) {
            log("Found BundledSkills folder in bundle")
            if let skillDirs = try? FileManager.default.contentsOfDirectory(
                at: bundledURL, includingPropertiesForKeys: nil
            ) {
                for dir in skillDirs {
                    let yamlURL = dir.appendingPathComponent("skill.yaml")
                    if var manifest = try? YAMLSkillParser.parse(contentsOf: yamlURL) {
                        manifest = manifest.withSource(.bundle)
                        if manifests.contains(where: { $0.skillID == manifest.skillID }) == false {
                            manifests.append(manifest)
                            log("Loaded bundled skill: \(manifest.name) (\(manifest.actions.count) actions)")
                        }
                    }
                }
            }
        }

        // Load from SampleSkills folder reference (blue folder in Xcode)
        if let sampleSkillsURL = Bundle.main.url(forResource: "SampleSkills", withExtension: nil) {
            log("Found SampleSkills folder in bundle")
            if let skillDirs = try? FileManager.default.contentsOfDirectory(
                at: sampleSkillsURL, includingPropertiesForKeys: nil
            ) {
                for dir in skillDirs {
                    let yamlURL = dir.appendingPathComponent("skill.yaml")
                    if let manifest = try? YAMLSkillParser.parse(contentsOf: yamlURL) {
                        if manifests.contains(where: { $0.skillID == manifest.skillID }) == false {
                            manifests.append(manifest)
                            log("Loaded skill: \(manifest.name) (\(manifest.actions.count) actions)")
                        }
                    }
                }
            }
        }

        // Load store-installed skills from App Support
        let storeService = SkillStoreService()
        if let installedDir = try? storeService.installedSkillsDirectory(),
           let skillDirs = try? FileManager.default.contentsOfDirectory(
               at: installedDir, includingPropertiesForKeys: nil
           ) {
            for dir in skillDirs {
                let yamlURL = dir.appendingPathComponent("skill.yaml")
                if var manifest = try? YAMLSkillParser.parse(contentsOf: yamlURL) {
                    manifest = manifest.withSource(.installed)
                    if manifests.contains(where: { $0.skillID == manifest.skillID }) == false {
                        manifests.append(manifest)
                        log("Loaded installed skill: \(manifest.name) (\(manifest.actions.count) actions)")
                    }
                }
            }
        }

        // Also pick up any loose .yaml files in bundle root (for future use)
        if let yamlURLs = Bundle.main.urls(forResourcesWithExtension: "yaml", subdirectory: nil) {
            for url in yamlURLs {
                if let manifest = try? YAMLSkillParser.parse(contentsOf: url) {
                    if manifests.contains(where: { $0.skillID == manifest.skillID }) == false {
                        manifests.append(manifest)
                        log("Loaded skill: \(manifest.name) (\(manifest.actions.count) actions)")
                    }
                }
            }
        }

        if manifests.isEmpty {
            log("No YAML skills found in app bundle")
        }

        return manifests
    }

    private func fetchUserExamples() -> [UserExample] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<UserExampleRecord>()
        guard let records = try? context.fetch(descriptor) else { return [] }
        return records.map { record in
            UserExample(
                skillID: record.skillID,
                actionID: record.actionID,
                skillName: record.skillName,
                actionTitle: record.actionTitle,
                text: record.text,
                isNegative: record.isNegative
            )
        }
    }

    private func fetchSuppressedExamples() -> [SuppressedExample] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<SuppressedExampleRecord>()
        guard let records = try? context.fetch(descriptor) else { return [] }
        return records.map { record in
            SuppressedExample(
                skillID: record.skillID,
                actionID: record.actionID,
                text: record.text
            )
        }
    }
}
