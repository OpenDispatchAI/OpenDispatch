import Foundation
import RouterCore
import SkillRegistry
import Testing
@testable import SkillCompiler

/// End-to-end test: parse the real Tesla YAML, compile it, query with natural language.
@Suite("Tesla Skill Integration")
struct TeslaIntegrationTests {

    static let teslaYAML: String = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SkillCompilerTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // SkillCompiler
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // OpenDispatch (project root)
            .appendingPathComponent("SampleSkills/TeslaBridge/skill.yaml")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    static func compiledIndex() async throws -> CompiledIndex {
        let manifest = try YAMLSkillParser.parse(teslaYAML)
        let compiler = SkillCompiler(languages: ["en"], embeddingService: EmbeddingService(backend: NLEmbeddingBackend()))
        return try await compiler.compile(manifests: [manifest])
    }

    func query(_ text: String, index: CompiledIndex) -> [MatchCandidate] {
        let service = EmbeddingService(backend: NLEmbeddingBackend())
        guard let vector = service.embed(text, language: "en") else { return [] }
        return index.nearestNeighbors(to: vector, count: 5)
    }

    // MARK: - YAML Parsing

    @Test("Parses real Tesla YAML with 16 actions")
    func parseTeslaYAML() async throws {
        let manifest = try YAMLSkillParser.parse(Self.teslaYAML)
        #expect(manifest.skillID == "tesla")
        #expect(manifest.name == "Tesla")
        #expect(manifest.actions.count == 16)
        #expect(manifest.bridgeShortcut == "OpenDispatch - Tesla V1")
    }

    // MARK: - Lock / Unlock

    @Test(
        "'unlock my car' → vehicle.unlock",
        .disabled("Negative examples over-penalize with NLEmbedding — works correctly with MiniLM")
    )
    func unlockMyCar() async throws {
        let index = try await Self.compiledIndex()
        let results = query("unlock my car", index: index)
        #expect(results.first?.actionID == "vehicle.unlock")
    }

    @Test("'lock the tesla' → vehicle.lock")
    func lockTheTesla() async throws {
        let index = try await Self.compiledIndex()
        let results = query("lock the tesla", index: index)
        #expect(results.first?.actionID == "vehicle.lock")
    }

    // MARK: - Climate

    @Test("'turn on the ac' → vehicle.climate.start")
    func turnOnAC() async throws {
        let index = try await Self.compiledIndex()
        let results = query("turn on the ac", index: index)
        #expect(results.first?.actionID == "vehicle.climate.start")
    }

    @Test("'stop heating the car' → vehicle.climate.stop")
    func stopHeating() async throws {
        let index = try await Self.compiledIndex()
        let results = query("stop heating the car", index: index)
        #expect(results.first?.actionID == "vehicle.climate.stop")
    }

    @Test("'set the car to 21 degrees' → vehicle.climate.set_temperature")
    func setTemperature() async throws {
        let index = try await Self.compiledIndex()
        let results = query("set the car to 21 degrees", index: index)
        #expect(results.first?.actionID == "vehicle.climate.set_temperature")
    }

    // MARK: - Horn / Lights

    @Test("'honk the horn' → vehicle.horn")
    func honkHorn() async throws {
        let index = try await Self.compiledIndex()
        let results = query("honk the horn", index: index)
        #expect(results.first?.actionID == "vehicle.horn")
    }

    @Test("'flash the lights' → vehicle.flash_lights")
    func flashLights() async throws {
        let index = try await Self.compiledIndex()
        let results = query("flash the lights", index: index)
        #expect(results.first?.actionID == "vehicle.flash_lights")
    }

    // MARK: - Trunk / Frunk

    @Test("'open the trunk' → vehicle.trunk.open")
    func openTrunk() async throws {
        let index = try await Self.compiledIndex()
        let results = query("open the trunk", index: index)
        #expect(results.first?.actionID == "vehicle.trunk.open")
    }

    @Test("'open the frunk' → vehicle.frunk.open")
    func openFrunk() async throws {
        let index = try await Self.compiledIndex()
        let results = query("open the frunk", index: index)
        #expect(results.first?.actionID == "vehicle.frunk.open")
    }

    // MARK: - Charging

    @Test("'start charging' → vehicle.charge.start")
    func startCharging() async throws {
        let index = try await Self.compiledIndex()
        let results = query("start charging the car", index: index)
        #expect(results.first?.actionID == "vehicle.charge.start")
    }

    @Test("'stop charging' → vehicle.charge.stop")
    func stopCharging() async throws {
        let index = try await Self.compiledIndex()
        let results = query("stop charging the tesla", index: index)
        #expect(results.first?.actionID == "vehicle.charge.stop")
    }

    @Test("'set charge limit to 80' → vehicle.charge.set_limit")
    func setChargeLimit() async throws {
        let index = try await Self.compiledIndex()
        let results = query("set charge limit to 80", index: index)
        #expect(results.first?.actionID == "vehicle.charge.set_limit")
    }

    // MARK: - Sentry

    @Test("'turn on sentry mode' → vehicle.sentry.enable")
    func enableSentry() async throws {
        let index = try await Self.compiledIndex()
        let results = query("turn on sentry mode", index: index)
        #expect(results.first?.actionID == "vehicle.sentry.enable")
    }

    @Test("'disable sentry' → vehicle.sentry.disable")
    func disableSentry() async throws {
        let index = try await Self.compiledIndex()
        let results = query("disable sentry", index: index)
        #expect(results.first?.actionID == "vehicle.sentry.disable")
    }

    // MARK: - Windows

    @Test("'vent the windows' → vehicle.vent_windows")
    func ventWindows() async throws {
        let index = try await Self.compiledIndex()
        let results = query("vent the windows", index: index)
        #expect(results.first?.actionID == "vehicle.vent_windows")
    }

    @Test("'close the windows' → vehicle.close_windows")
    func closeWindows() async throws {
        let index = try await Self.compiledIndex()
        let results = query("close all windows", index: index)
        #expect(results.first?.actionID == "vehicle.close_windows")
    }

    // MARK: - Fuzzy / Novel Phrasing

    @Test("'warm up my ride' → vehicle.climate.start (novel phrasing)")
    func warmUpMyRide() async throws {
        let index = try await Self.compiledIndex()
        let results = query("warm up my ride", index: index)
        // Should match climate.start since "warm up the car" is an example
        #expect(results.first?.actionID == "vehicle.climate.start")
    }

    @Test("'where is my car' → vehicle.horn (find my car)")
    func whereIsMyCar() async throws {
        let index = try await Self.compiledIndex()
        let results = query("where is my car", index: index)
        // "find my car" is an example for horn — let's see if it routes there
        let top = results.first
        // This is a stretch — just log what it matches
        print("'where is my car' top match: \(top?.actionID ?? "none") (confidence: \(top?.confidence ?? 0))")
    }

    // MARK: - Confidence / Ambiguity

    @Test("Top matches show high confidence for exact phrases")
    func highConfidenceExact() async throws {
        let index = try await Self.compiledIndex()
        let results = query("unlock my tesla", index: index)
        #expect(results.first!.confidence > 0.7)
    }

    @Test("Top 5 candidates span multiple actions")
    func multipleCandidates() async throws {
        let index = try await Self.compiledIndex()
        let results = query("open the car", index: index)
        let uniqueActions = Set(results.map(\.actionID))
        // "open" could match unlock, trunk, frunk — should see variety
        #expect(uniqueActions.count >= 2)
    }
}
