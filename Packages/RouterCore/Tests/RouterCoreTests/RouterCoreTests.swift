import CapabilityRegistry
import RouterCore
import Testing

private struct TestBackend: RouterPlanningBackend {
    let id = "test"
    let planToReturn: RouterPlan

    func plan(request: RouterRequest, availableSkills: [PlannerSkillContext]) async throws -> RouterPlan {
        planToReturn
    }
}

private struct TestProvider: DispatchProvider {
    let descriptor: ProviderDescriptor
    let confirmationBehavior: ConfirmationBehavior
    let result: ExecutionResult

    init(
        id: String,
        kind: ProviderKind = .system,
        priority: Int = 100,
        capabilities: [CapabilityID],
        confirmationBehavior: ConfirmationBehavior = .never,
        result: ExecutionResult = .success()
    ) {
        descriptor = ProviderDescriptor(
            id: id,
            displayName: id,
            kind: kind,
            priority: priority,
            capabilities: capabilities
        )
        self.confirmationBehavior = confirmationBehavior
        self.result = result
    }

    func validate(plan: RouterPlan) throws {}

    func execute(plan: RouterPlan, mode: ExecutionMode) async -> ExecutionResult {
        result
    }
}

@Test func routerUsesPreferredProviderOrdering() async throws {
    var registry = try CapabilityRegistry()
    let reminders = TestProvider(id: "reminders", capabilities: ["task.create"])
    let tickTick = TestProvider(id: "ticktick", kind: .external, priority: 10, capabilities: ["task.create"])
    try registry.registerProvider(reminders.descriptor)
    try registry.registerProvider(tickTick.descriptor)

    let router = Router(
        capabilityRegistry: registry,
        primaryBackend: TestBackend(
            planToReturn: RouterPlan(
                capability: "task.create",
                parameters: ["title": .string("Buy milk")],
                confidence: 0.91
            )
        ),
        providers: [reminders, tickTick],
        eventStore: InMemoryDispatchEventStore()
    )

    let resolution = try await router.route(
        request: RouterRequest(rawInput: "add buy milk"),
        policy: RoutingPolicy(
            preferredProviders: ["task.create": ["ticktick", "reminders"]]
        )
    )

    #expect(resolution.providerID == "ticktick")
}

@Test func routerDefersExternalProviderWithoutConfirmation() async throws {
    var registry = try CapabilityRegistry()
    let external = TestProvider(
        id: "ticktick",
        kind: .external,
        capabilities: ["task.create"],
        confirmationBehavior: .always
    )
    try registry.registerProvider(external.descriptor)

    let router = Router(
        capabilityRegistry: registry,
        primaryBackend: TestBackend(
            planToReturn: RouterPlan(
                capability: "task.create",
                parameters: ["title": .string("Buy milk")],
                confidence: 0.91
            )
        ),
        providers: [external],
        eventStore: InMemoryDispatchEventStore()
    )

    let resolution = try await router.route(request: RouterRequest(rawInput: "add buy milk"))

    #expect(resolution.confirmationRequired)
    #expect(resolution.result.metadata["status"] == .string("awaiting_confirmation"))
}

private struct StubExecutor: SkillExecutor {
    let result: ExecutionResult
    func execute(plan: RouterPlan, mode: ExecutionMode) async -> ExecutionResult {
        result
    }
}

@Test("SkillExecutor protocol can be implemented")
func skillExecutorProtocol() async {
    let executor = StubExecutor(result: .success(metadata: ["status": .string("ok")]))
    let plan = RouterPlan(capability: "test.action", parameters: [:], confidence: 1.0)
    let result = await executor.execute(plan: plan, mode: .live)
    #expect(result.success)
    #expect(result.metadata["status"] == .string("ok"))
}

@Test("Auto-dispatches when confidence gap above threshold")
func autoDispatchesWithClearGap() async throws {
    var registry = try CapabilityRegistry()
    let reminders = TestProvider(id: "reminders", capabilities: ["task.create"])
    let tickTick = TestProvider(id: "ticktick", kind: .external, priority: 10, capabilities: ["task.create"])
    try registry.registerProvider(reminders.descriptor)
    try registry.registerProvider(tickTick.descriptor)

    let candidates = [
        MatchCandidate(
            skillID: "reminders", skillName: "Reminders", actionID: "create",
            actionTitle: "Create Task", capability: "task.create",
            distance: 0.05, confidence: 0.95
        ),
        MatchCandidate(
            skillID: "ticktick", skillName: "TickTick", actionID: "create",
            actionTitle: "Create Task", capability: "task.create",
            distance: 0.25, confidence: 0.75
        ),
    ]

    let router = Router(
        capabilityRegistry: registry,
        primaryBackend: TestBackend(
            planToReturn: RouterPlan(
                capability: "task.create",
                parameters: ["title": .string("Buy milk")],
                confidence: 0.95,
                suggestedProviderID: "reminders",
                matchCandidates: candidates
            )
        ),
        providers: [reminders, tickTick],
        eventStore: InMemoryDispatchEventStore()
    )

    // Gap of 0.20 > default threshold of 0.15 — should auto-dispatch (not ambiguous)
    let resolution = try await router.route(request: RouterRequest(rawInput: "add buy milk"))
    #expect(resolution.providerID == "reminders")
}

@Test("Prompts when confidence gap below threshold")
func promptsWhenGapTooSmall() async throws {
    var registry = try CapabilityRegistry()
    let reminders = TestProvider(id: "reminders", capabilities: ["task.create"])
    let tickTick = TestProvider(id: "ticktick", kind: .external, priority: 10, capabilities: ["task.create"])
    try registry.registerProvider(reminders.descriptor)
    try registry.registerProvider(tickTick.descriptor)

    let candidates = [
        MatchCandidate(
            skillID: "reminders", skillName: "Reminders", actionID: "create",
            actionTitle: "Create Task", capability: "task.create",
            distance: 0.10, confidence: 0.90
        ),
        MatchCandidate(
            skillID: "ticktick", skillName: "TickTick", actionID: "create",
            actionTitle: "Create Task", capability: "task.create",
            distance: 0.15, confidence: 0.85
        ),
    ]

    let router = Router(
        capabilityRegistry: registry,
        primaryBackend: TestBackend(
            planToReturn: RouterPlan(
                capability: "task.create",
                parameters: ["title": .string("Buy milk")],
                confidence: 0.90,
                suggestedProviderID: "reminders",
                matchCandidates: candidates
            )
        ),
        providers: [reminders, tickTick],
        eventStore: InMemoryDispatchEventStore()
    )

    // Gap of 0.05 < default threshold of 0.15 — should prompt (ambiguous)
    await #expect(throws: RouterError.self) {
        _ = try await router.route(request: RouterRequest(rawInput: "add buy milk"))
    }
}

@Test("Auto-dispatches with single provider regardless of gap")
func autoDispatchesSingleProvider() async throws {
    var registry = try CapabilityRegistry()
    let reminders = TestProvider(id: "reminders", capabilities: ["task.create"])
    try registry.registerProvider(reminders.descriptor)

    let candidates = [
        MatchCandidate(
            skillID: "reminders", skillName: "Reminders", actionID: "create",
            actionTitle: "Create Task", capability: "task.create",
            distance: 0.10, confidence: 0.90
        ),
        MatchCandidate(
            skillID: "reminders", skillName: "Reminders", actionID: "list",
            actionTitle: "List Tasks", capability: "task.create",
            distance: 0.11, confidence: 0.89
        ),
    ]

    let router = Router(
        capabilityRegistry: registry,
        primaryBackend: TestBackend(
            planToReturn: RouterPlan(
                capability: "task.create",
                parameters: ["title": .string("Buy milk")],
                confidence: 0.90,
                suggestedProviderID: "reminders",
                matchCandidates: candidates
            )
        ),
        providers: [reminders],
        eventStore: InMemoryDispatchEventStore()
    )

    // Only one provider — no ambiguity possible, regardless of tiny gap
    let resolution = try await router.route(request: RouterRequest(rawInput: "add buy milk"))
    #expect(resolution.providerID == "reminders")
}

@Test("Falls back to preferences when no match candidates")
func fallbackWithoutCandidates() async throws {
    var registry = try CapabilityRegistry()
    let reminders = TestProvider(id: "reminders", capabilities: ["task.create"])
    let tickTick = TestProvider(id: "ticktick", kind: .external, priority: 10, capabilities: ["task.create"])
    try registry.registerProvider(reminders.descriptor)
    try registry.registerProvider(tickTick.descriptor)

    let router = Router(
        capabilityRegistry: registry,
        primaryBackend: TestBackend(
            planToReturn: RouterPlan(
                capability: "task.create",
                parameters: ["title": .string("Buy milk")],
                confidence: 0.80
            )
        ),
        providers: [reminders, tickTick],
        eventStore: InMemoryDispatchEventStore()
    )

    // No suggestedProviderID, no matchCandidates — falls back to policy preferred provider
    let resolution = try await router.route(
        request: RouterRequest(rawInput: "add buy milk"),
        policy: RoutingPolicy(
            preferredProviders: ["task.create": ["ticktick", "reminders"]]
        )
    )
    #expect(resolution.providerID == "ticktick")
}

@Test func routerRejectsUnknownCapabilities() async throws {
    let router = Router(
        capabilityRegistry: try CapabilityRegistry(),
        primaryBackend: TestBackend(
            planToReturn: RouterPlan(
                capability: "unknown.capability",
                parameters: [:],
                confidence: 0.2
            )
        ),
        providers: [],
        eventStore: InMemoryDispatchEventStore()
    )

    await #expect(throws: RouterError.unsupportedCapability("unknown.capability")) {
        _ = try await router.route(request: RouterRequest(rawInput: "something"))
    }
}
