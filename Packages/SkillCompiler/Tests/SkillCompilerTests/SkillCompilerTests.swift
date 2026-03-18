import Foundation
import RouterCore
import SkillRegistry
import Testing
@testable import SkillCompiler

// MARK: - EmbeddingService Tests

@Suite("EmbeddingService")
struct EmbeddingServiceTests {

    let service = EmbeddingService(backend: NLEmbeddingBackend())

    @Test("Embeds a string and returns a non-empty vector")
    func embedString() {
        guard let vector = service.embed("unlock my car", language: "en") else {
            Issue.record("NLEmbedding not available for en — skipping")
            return
        }
        #expect(vector.isEmpty == false)
        #expect(vector.count > 10)
    }

    @Test("Similar strings produce closer vectors than dissimilar ones")
    func similarityOrdering() {
        guard let v1 = service.embed("unlock my car", language: "en"),
              let v2 = service.embed("open my car", language: "en"),
              let v3 = service.embed("buy groceries tomorrow", language: "en") else {
            Issue.record("NLEmbedding not available — skipping")
            return
        }
        let distSimilar = service.cosineDistance(v1, v2)
        let distDissimilar = service.cosineDistance(v1, v3)
        #expect(distSimilar < distDissimilar)
    }

    @Test("Detects English text")
    func detectEnglish() {
        let lang = service.detectLanguage(of: "unlock my car please")
        #expect(lang == "en")
    }
}

// MARK: - SkillCompiler Tests

@Suite("SkillCompiler")
struct SkillCompilerTests {

    static let teslaManifest = YAMLSkillManifest(
        skillID: "tesla",
        name: "Tesla",
        version: "1.0.0",
        builtIn: false,
        bridgeShortcut: "OpenDispatch - Tesla v1",
        actions: [
            YAMLSkillAction(
                id: "vehicle.unlock",
                title: "Unlock",
                description: "Unlock your Tesla",
                shortcutArguments: ["action": .string("unlock")],
                examples: ["unlock my car", "unlock the tesla", "open my car"]
            ),
            YAMLSkillAction(
                id: "vehicle.lock",
                title: "Lock",
                description: "Lock your Tesla",
                shortcutArguments: ["action": .string("lock")],
                examples: ["lock my car", "lock the tesla"]
            ),
        ]
    )

    static let remindersManifest = YAMLSkillManifest(
        skillID: "apple_reminders",
        name: "Apple Reminders",
        version: "1.0.0",
        builtIn: true,
        actions: [
            YAMLSkillAction(
                id: "task.create",
                title: "Create Task",
                description: "Create a new reminder",
                parameters: [
                    ParameterSchema(name: "title", type: "string", required: true),
                ],
                examples: ["add milk", "remind me to call mom", "buy groceries tomorrow"]
            ),
        ]
    )

    @Test("Compiles manifests into index entries")
    func compileManifests() async throws {
        let compiler = SkillCompiler(languages: ["en"], embeddingService: EmbeddingService(backend: NLEmbeddingBackend()))
        let index = try await compiler.compile(manifests: [Self.teslaManifest])
        // 2 actions: (3 examples + 1 desc) + (2 examples + 1 desc) = 7 entries
        #expect(index.entries.count == 7)
        #expect(index.entries.allSatisfy { $0.embedding.isEmpty == false })
        #expect(index.entries.allSatisfy { $0.skillID == "tesla" })
    }

    @Test("Preserves shortcut arguments in compiled entries")
    func preservesShortcutArguments() async throws {
        let compiler = SkillCompiler(languages: ["en"], embeddingService: EmbeddingService(backend: NLEmbeddingBackend()))
        let index = try await compiler.compile(manifests: [Self.teslaManifest])
        let unlockEntries = index.entries.filter { $0.actionID == "vehicle.unlock" }
        #expect(unlockEntries.allSatisfy {
            $0.shortcutArguments?["action"]?.stringValue == "unlock"
        })
    }

    @Test("Parameterless actions have nil parameters")
    func parameterlessActions() async throws {
        let compiler = SkillCompiler(languages: ["en"], embeddingService: EmbeddingService(backend: NLEmbeddingBackend()))
        let index = try await compiler.compile(manifests: [Self.teslaManifest])
        #expect(index.entries.allSatisfy { $0.parameters == nil })
    }

    @Test("Actions with parameters preserve them")
    func actionsWithParameters() async throws {
        let compiler = SkillCompiler(languages: ["en"], embeddingService: EmbeddingService(backend: NLEmbeddingBackend()))
        let index = try await compiler.compile(manifests: [Self.remindersManifest])
        #expect(index.entries.allSatisfy { $0.parameters != nil })
        #expect(index.entries.allSatisfy { $0.requiresParameterExtraction })
    }

    @Test("Throws when no languages configured")
    func noLanguages() async {
        let compiler = SkillCompiler(languages: [], embeddingService: EmbeddingService(backend: NLEmbeddingBackend()))
        await #expect(throws: SkillCompilerError.self) {
            try await compiler.compile(manifests: [Self.teslaManifest])
        }
    }
}

// MARK: - End-to-End Routing Tests (the interesting ones)

@Suite("End-to-End Routing")
struct EndToEndRoutingTests {

    /// Compile both skills and query with real NLEmbedding
    static func compileTestIndex() async throws -> CompiledIndex {
        let compiler = SkillCompiler(languages: ["en"], embeddingService: EmbeddingService(backend: NLEmbeddingBackend()))
        return try await compiler.compile(manifests: [
            SkillCompilerTests.teslaManifest,
            SkillCompilerTests.remindersManifest,
        ])
    }

    @Test("'unlock my tesla' routes to vehicle.unlock")
    func unlockTesla() async throws {
        let index = try await Self.compileTestIndex()
        let service = EmbeddingService()
        guard let query = service.embed("unlock my tesla", language: "en") else {
            Issue.record("NLEmbedding unavailable"); return
        }
        let results = index.nearestNeighbors(to: query, count: 5)
        #expect(results.first?.actionID == "vehicle.unlock")
        #expect(results.first?.skillName == "Tesla")
    }

    @Test("'add milk' routes to task.create")
    func addMilk() async throws {
        let index = try await Self.compileTestIndex()
        let service = EmbeddingService()
        guard let query = service.embed("add milk", language: "en") else {
            Issue.record("NLEmbedding unavailable"); return
        }
        let results = index.nearestNeighbors(to: query, count: 5)
        #expect(results.first?.actionID == "task.create")
        #expect(results.first?.skillName == "Apple Reminders")
    }

    @Test("'lock the car' routes to vehicle.lock not vehicle.unlock")
    func lockVsUnlock() async throws {
        let index = try await Self.compileTestIndex()
        let service = EmbeddingService()
        guard let query = service.embed("lock the car", language: "en") else {
            Issue.record("NLEmbedding unavailable"); return
        }
        let results = index.nearestNeighbors(to: query, count: 5)
        #expect(results.first?.actionID == "vehicle.lock")
    }

    @Test("'remind me to buy eggs' routes to task.create")
    func remindBuyEggs() async throws {
        let index = try await Self.compileTestIndex()
        let service = EmbeddingService()
        guard let query = service.embed("remind me to buy eggs", language: "en") else {
            Issue.record("NLEmbedding unavailable"); return
        }
        let results = index.nearestNeighbors(to: query, count: 5)
        #expect(results.first?.actionID == "task.create")
    }

    @Test("Top match for 'unlock my tesla' has high confidence")
    func highConfidence() async throws {
        let index = try await Self.compileTestIndex()
        let service = EmbeddingService()
        guard let query = service.embed("unlock my tesla", language: "en") else {
            Issue.record("NLEmbedding unavailable"); return
        }
        let results = index.nearestNeighbors(to: query, count: 5)
        #expect(results.first!.confidence > 0.7)
    }

    @Test("Returns multiple candidates with decreasing confidence")
    func multipleCandidates() async throws {
        let index = try await Self.compileTestIndex()
        let service = EmbeddingService()
        guard let query = service.embed("open my car", language: "en") else {
            Issue.record("NLEmbedding unavailable"); return
        }
        let results = index.nearestNeighbors(to: query, count: 5)
        #expect(results.count >= 3)
        // Confidences should be descending
        for i in 0..<(results.count - 1) {
            #expect(results[i].confidence >= results[i + 1].confidence)
        }
    }
}

// MARK: - CompiledIndexStore Tests

@Suite("CompiledIndexStore")
struct CompiledIndexStoreTests {

    @Test("Round-trips index through save and load")
    func saveAndLoad() async throws {
        let compiler = SkillCompiler(languages: ["en"], embeddingService: EmbeddingService(backend: NLEmbeddingBackend()))
        let index = try await compiler.compile(manifests: [SkillCompilerTests.teslaManifest])

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_index_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try CompiledIndexStore.save(index, to: tempURL)
        let loaded = try CompiledIndexStore.load(from: tempURL)

        #expect(loaded.entries.count == index.entries.count)
        #expect(loaded.entries[0].skillID == index.entries[0].skillID)
        #expect(loaded.entries[0].embedding == index.entries[0].embedding)
    }
}
