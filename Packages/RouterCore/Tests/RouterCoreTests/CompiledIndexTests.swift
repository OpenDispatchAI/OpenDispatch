import CapabilityRegistry
import Foundation
import RouterCore
import Testing

// MARK: - Test Helpers

private func makeCandidate(
    skillID: String = "s",
    skillName: String = "S",
    actionID: String = "a",
    actionTitle: String = "A",
    capability: CapabilityID = "c",
    distance: Double = 0.1,
    confidence: Double = 0.9
) -> MatchCandidate {
    MatchCandidate(
        skillID: skillID, skillName: skillName,
        actionID: actionID, actionTitle: actionTitle,
        capability: capability, distance: distance, confidence: confidence
    )
}

private func makeEntry(
    embedding: [Float],
    skillID: String = "s",
    skillName: String = "S",
    actionID: String = "a",
    actionTitle: String = "A",
    capability: CapabilityID = "c",
    parameters: [ParameterSchema]? = nil,
    shortcutArguments: [String: JSONValue]? = nil,
    originalExample: String = "test",
    language: String = "en"
) -> CompiledEntry {
    CompiledEntry(
        embedding: embedding, skillID: skillID, skillName: skillName,
        actionID: actionID, actionTitle: actionTitle, capability: capability,
        parameters: parameters, shortcutArguments: shortcutArguments,
        originalExample: originalExample, language: language
    )
}

// MARK: - MatchCandidate Tests

@Test func matchCandidateStoresMetadata() {
    let candidate = makeCandidate(
        skillID: "tesla", skillName: "Tesla",
        actionID: "vehicle.unlock", actionTitle: "Unlock",
        capability: "vehicle.unlock", distance: 0.15, confidence: 0.85
    )
    #expect(candidate.skillID == "tesla")
    #expect(candidate.skillName == "Tesla")
    #expect(candidate.actionID == "vehicle.unlock")
    #expect(candidate.actionTitle == "Unlock")
    #expect(candidate.capability == CapabilityID(rawValue: "vehicle.unlock"))
    #expect(candidate.distance == 0.15)
    #expect(candidate.confidence == 0.85)
}

@Test func matchCandidateConformsToHashable() {
    let a = makeCandidate()
    let b = makeCandidate()
    #expect(a == b)
    #expect(a.hashValue == b.hashValue)
}

@Test func matchCandidateConformsToCodable() throws {
    let original = makeCandidate()
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(MatchCandidate.self, from: data)
    #expect(original == decoded)
}

// MARK: - ParameterSchema Tests

@Test func parameterSchemaStoresFields() {
    let param = ParameterSchema(name: "duration", type: "Int", description: "seconds", required: true)
    #expect(param.name == "duration")
    #expect(param.type == "Int")
    #expect(param.description == "seconds")
    #expect(param.required == true)
}

@Test func parameterSchemaConformsToCodable() throws {
    let original = ParameterSchema(name: "title", type: "String", description: "Task title", required: false)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ParameterSchema.self, from: data)
    #expect(original == decoded)
}

// MARK: - CompiledEntry Tests

@Test func compiledEntryRequiresParameterExtractionWhenParametersExist() {
    let entry = makeEntry(
        embedding: [1, 0, 0],
        parameters: [ParameterSchema(name: "duration", type: "Int", description: "seconds")]
    )
    #expect(entry.requiresParameterExtraction == true)
}

@Test func compiledEntryDoesNotRequireParameterExtractionWhenNil() {
    let entry = makeEntry(embedding: [1, 0, 0], parameters: nil)
    #expect(entry.requiresParameterExtraction == false)
}

@Test func compiledEntryDoesNotRequireParameterExtractionWhenEmpty() {
    let entry = makeEntry(embedding: [1, 0, 0], parameters: [])
    #expect(entry.requiresParameterExtraction == false)
}

@Test func compiledEntryConformsToCodable() throws {
    let original = makeEntry(
        embedding: [0.5, 0.5],
        parameters: [ParameterSchema(name: "x", type: "String", description: "desc")],
        shortcutArguments: ["key": .string("value")]
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(CompiledEntry.self, from: data)
    #expect(original == decoded)
}

// MARK: - CompiledIndex Tests

@Test func nearestNeighborsReturnsSortedByDistanceAscending() {
    let entryX = makeEntry(embedding: [1, 0, 0], actionID: "x", capability: "cx")
    let entryY = makeEntry(embedding: [0, 1, 0], actionID: "y", capability: "cy")
    let entryZ = makeEntry(embedding: [0, 0, 1], actionID: "z", capability: "cz")

    let index = CompiledIndex(entries: [entryX, entryY, entryZ])
    let results = index.nearestNeighbors(to: [0.9, 0.1, 0.0], count: 3)

    #expect(results.count == 3)
    #expect(results[0].actionID == "x")
    #expect(results[1].actionID == "y")
    #expect(results[2].actionID == "z")
    #expect(results[0].distance <= results[1].distance)
    #expect(results[1].distance <= results[2].distance)
}

@Test func nearestNeighborsRespectsCount() {
    let entries = [
        makeEntry(embedding: [1, 0], actionID: "a1"),
        makeEntry(embedding: [0, 1], actionID: "a2"),
        makeEntry(embedding: [0.7, 0.7], actionID: "a3"),
    ]
    let index = CompiledIndex(entries: entries)
    let results = index.nearestNeighbors(to: [1, 0], count: 2)
    #expect(results.count == 2)
}

@Test func nearestNeighborsCountExceedingEntriesReturnsAll() {
    let index = CompiledIndex(entries: [makeEntry(embedding: [1, 0])])
    let results = index.nearestNeighbors(to: [1, 0], count: 10)
    #expect(results.count == 1)
}

@Test func nearestNeighborsConfidenceIsOneMinusDistance() {
    let index = CompiledIndex(entries: [makeEntry(embedding: [1, 0, 0])])
    let results = index.nearestNeighbors(to: [1, 0, 0], count: 1)
    #expect(results.count == 1)
    #expect(results[0].distance < 0.001)
    #expect(results[0].confidence > 0.999)
}

@Test func nearestNeighborsConfidenceClampedToZero() {
    let index = CompiledIndex(entries: [makeEntry(embedding: [-1, 0])])
    let results = index.nearestNeighbors(to: [1, 0], count: 1)
    #expect(results.count == 1)
    #expect(results[0].confidence == 0.0)
    #expect(results[0].distance >= 1.0)
}

@Test func nearestNeighborsPopulatesSkillNameAndActionTitle() {
    let entry = makeEntry(
        embedding: [1, 0], skillID: "tesla", skillName: "Tesla",
        actionID: "vehicle.unlock", actionTitle: "Unlock"
    )
    let index = CompiledIndex(entries: [entry])
    let results = index.nearestNeighbors(to: [1, 0], count: 1)
    #expect(results[0].skillName == "Tesla")
    #expect(results[0].actionTitle == "Unlock")
}

@Test func entryForMatchCandidateReturnsCorrectEntry() {
    let entry1 = makeEntry(embedding: [1, 0], skillID: "s1", actionID: "a1")
    let entry2 = makeEntry(
        embedding: [0, 1], skillID: "s2", actionID: "a2",
        parameters: [ParameterSchema(name: "p", type: "String")]
    )
    let index = CompiledIndex(entries: [entry1, entry2])
    let candidates = index.nearestNeighbors(to: [0, 1], count: 1)
    let found = index.entry(for: candidates[0])
    #expect(found?.skillID == "s2")
    #expect(found?.actionID == "a2")
}

@Test func entryForUnknownCandidateReturnsNil() {
    let index = CompiledIndex(entries: [makeEntry(embedding: [1, 0])])
    let unknown = makeCandidate(skillID: "unknown", actionID: "unknown.action")
    #expect(index.entry(for: unknown) == nil)
}

@Test func compiledIndexWithEmptyEntries() {
    let index = CompiledIndex(entries: [])
    let results = index.nearestNeighbors(to: [1, 0, 0], count: 5)
    #expect(results.isEmpty)
}

@Test func compiledIndexStoresCompiledAt() {
    let now = Date()
    let index = CompiledIndex(entries: [], compiledAt: now)
    #expect(index.compiledAt == now)
}

@Test func compiledIndexConformsToCodable() throws {
    let entry = makeEntry(embedding: [0.5, 0.5])
    let original = CompiledIndex(entries: [entry])
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(original)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(CompiledIndex.self, from: data)
    #expect(decoded.entries.count == original.entries.count)
    #expect(decoded.entries[0].skillID == original.entries[0].skillID)
}

// MARK: - RouterPlan matchCandidates Tests

@Test func routerPlanDefaultMatchCandidatesIsNil() {
    let plan = RouterPlan(capability: "task.create", parameters: [:], confidence: 0.9)
    #expect(plan.matchCandidates == nil)
}

@Test func routerPlanAcceptsMatchCandidates() {
    let candidates = [makeCandidate()]
    let plan = RouterPlan(
        capability: "task.create", parameters: [:],
        confidence: 0.9, matchCandidates: candidates
    )
    #expect(plan.matchCandidates?.count == 1)
    #expect(plan.matchCandidates?.first?.skillID == "s")
}

@Test func routerPlanShortInitDefaultMatchCandidatesIsNil() {
    let plan = RouterPlan(
        capability: "task.create", parameters: [:],
        confidence: 0.9, suggestedProviderID: "p"
    )
    #expect(plan.matchCandidates == nil)
}

@Test func routerPlanWithMatchCandidatesCodable() throws {
    let candidates = [makeCandidate()]
    let original = RouterPlan(
        capability: "task.create", parameters: ["title": .string("test")],
        confidence: 0.85, matchCandidates: candidates
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(RouterPlan.self, from: data)
    #expect(original == decoded)
}
