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

@Test func routerPromptsWhenDomainIsAmbiguous() async throws {
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
                parameters: ["title": .string("buy milk")],
                confidence: 0.91,
                title: "Create Task",
                routing: RoutingHints(domain: "errands", listHint: "errands", audience: "shared")
            )
        ),
        providers: [reminders, tickTick],
        eventStore: InMemoryDispatchEventStore()
    )

    await #expect(throws: RouterError.ambiguousProviders(
        [
            DestinationOption(providerID: "reminders", providerDisplayName: "reminders"),
            DestinationOption(providerID: "ticktick", providerDisplayName: "ticktick"),
        ],
        RouterPlan(
            capability: "task.create",
            parameters: ["title": .string("buy milk")],
            confidence: 0.91,
            title: "Create Task",
            routing: RoutingHints(domain: "errands", listHint: "errands", audience: "shared")
        )
    )) {
        _ = try await router.route(request: RouterRequest(rawInput: "add milk"))
    }
}

@Test func routerUsesDomainHeuristicForGroceries() async throws {
    var registry = try CapabilityRegistry()
    let reminders = TestProvider(id: "apple_reminders", capabilities: ["task.create"])
    let tickTick = TestProvider(id: "ticktick", kind: .external, priority: 10, capabilities: ["task.create"])
    try registry.registerProvider(reminders.descriptor)
    try registry.registerProvider(tickTick.descriptor)

    let router = Router(
        capabilityRegistry: registry,
        primaryBackend: TestBackend(
            planToReturn: RouterPlan(
                capability: "task.create",
                parameters: ["title": .string("buy milk")],
                confidence: 0.91,
                title: "Create Task",
                routing: RoutingHints(domain: "grocery", listHint: "groceries", audience: "shared")
            )
        ),
        providers: [reminders, tickTick],
        eventStore: InMemoryDispatchEventStore()
    )

    let resolution = try await router.route(request: RouterRequest(rawInput: "add milk"))

    #expect(resolution.providerID == "ticktick")
}

@Test func routerUsesDomainPreferenceBeforeDefaultPriority() async throws {
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
                parameters: ["title": .string("buy milk")],
                confidence: 0.91,
                title: "Create Task",
                routing: RoutingHints(domain: "grocery", listHint: "groceries", audience: "shared")
            )
        ),
        providers: [reminders, tickTick],
        eventStore: InMemoryDispatchEventStore()
    )

    let resolution = try await router.route(
        request: RouterRequest(rawInput: "add milk"),
        policy: RoutingPolicy(
            preferredProviders: ["task.create.grocery": ["ticktick"]]
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
