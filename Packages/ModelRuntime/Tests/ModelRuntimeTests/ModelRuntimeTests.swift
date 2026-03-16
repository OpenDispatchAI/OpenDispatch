@testable import ModelRuntime
import RouterCore
import Testing

@Test func ruleBasedBackendCreatesTaskPlan() async throws {
    let backend = RuleBasedBackend()
    let plan = try await backend.plan(
        request: RouterRequest(rawInput: "add buy milk"),
        availableSkills: []
    )

    #expect(plan.capability == "task.create")
    #expect(plan.parameters["title"] == .string("buy milk"))
    #expect(plan.title == "Create Task")
    #expect(plan.routing == RoutingHints(domain: "grocery", listHint: "groceries", audience: "shared"))
}

@Test func ruleBasedBackendCreatesReminderPlanFromPRDExample() async throws {
    let backend = RuleBasedBackend()
    let plan = try await backend.plan(
        request: RouterRequest(rawInput: "Create reminder call mom tomorrow"),
        availableSkills: []
    )

    #expect(plan.capability == "task.create")
    #expect(plan.parameters["title"] == .string("call mom tomorrow"))
    #expect(plan.title == "Create Task")
    #expect(plan.routing == RoutingHints(domain: "personal", listHint: "personal", audience: "personal"))
}

@Test func ruleBasedBackendCreatesCompletionPlanWithWorkRouting() async throws {
    let backend = RuleBasedBackend()
    let plan = try await backend.plan(
        request: RouterRequest(rawInput: "finish client report"),
        availableSkills: []
    )

    #expect(plan.capability == "task.complete")
    #expect(plan.parameters["title"] == .string("client report"))
    #expect(plan.title == "Complete Task")
    #expect(plan.routing == RoutingHints(domain: "work", listHint: "work", audience: "personal"))
}

@Test func ruleBasedBackendFallsBackToEventLogging() async throws {
    let backend = RuleBasedBackend()
    let plan = try await backend.plan(
        request: RouterRequest(rawInput: "dog pooped"),
        availableSkills: []
    )

    #expect(plan.capability == "log.event")
    #expect(plan.confidence < 0.7)
}

@Test func appleFoundationPlanBuilderCreatesStructuredReminderPlan() {
    let builder = AppleFoundationPlanBuilder()
    let plan = builder.plan(
        from: PlannedCommandClassification(
            capability: "task.create",
            confidence: 0.98,
            primaryText: nil,
            taskTitle: "bel oma morgen",
            dueDate: "2026-03-16T09:00:00+01:00",
            noteTitle: nil,
            noteBody: nil,
            eventTitle: nil,
            shortcutName: nil,
            url: nil,
            routingDomain: "personal",
            routingListHint: "personal",
            routingAudience: "personal",
            suggestedProviderID: nil,
            normalizedIntent: nil,
            tags: []
        ),
        request: RouterRequest(rawInput: "Herinner me eraan oma morgen te bellen"),
        availableSkills: []
    )

    #expect(plan?.capability == "task.create")
    #expect(plan?.parameters["title"] == .string("bel oma morgen"))
    #expect(plan?.parameters["due_date"] == .string("2026-03-16T09:00:00+01:00"))
    #expect(plan?.routing == RoutingHints(domain: "personal", listHint: "personal", audience: "personal"))
}

@Test func appleFoundationPlanBuilderUsesInstalledSkillCapability() {
    let builder = AppleFoundationPlanBuilder()
    let skill = PlannerSkillContext(
        id: "ride-request",
        name: "Ride Request",
        capability: "ride.request",
        providerID: "ride_provider",
        keywords: ["ride"],
        examples: ["get me a ride home"],
        documentation: "Use this skill when the user wants to request a ride."
    )
    let plan = builder.plan(
        from: PlannedCommandClassification(
            capability: "ride.request",
            confidence: 0.95,
            primaryText: "get me a ride home",
            taskTitle: nil,
            dueDate: nil,
            noteTitle: nil,
            noteBody: nil,
            eventTitle: nil,
            shortcutName: nil,
            url: nil,
            routingDomain: nil,
            routingListHint: nil,
            routingAudience: nil,
            suggestedProviderID: "ride_provider",
            normalizedIntent: nil,
            tags: []
        ),
        request: RouterRequest(rawInput: "Get me a ride home"),
        availableSkills: [skill]
    )

    #expect(plan?.capability == "ride.request")
    #expect(plan?.suggestedProviderID == "ride_provider")
    #expect(plan?.parameters["text"] == .string("Get me a ride home"))
}

@Test func appleFoundationPlanBuilderRejectsUnsupportedCapabilityAlias() {
    let builder = AppleFoundationPlanBuilder()
    let plan = builder.plan(
        from: PlannedCommandClassification(
            capability: "reminder.create",
            confidence: 0.94,
            primaryText: "call mom tomorrow",
            taskTitle: nil,
            dueDate: nil,
            noteTitle: nil,
            noteBody: nil,
            eventTitle: nil,
            shortcutName: nil,
            url: nil,
            routingDomain: nil,
            routingListHint: nil,
            routingAudience: nil,
            suggestedProviderID: nil,
            normalizedIntent: nil,
            tags: []
        ),
        request: RouterRequest(rawInput: "Create reminder call mom tomorrow"),
        availableSkills: []
    )

    #expect(plan == nil)
}

@Test func appleFoundationPlanBuilderRejectsTaskPlanWithoutRequiredTitle() {
    let builder = AppleFoundationPlanBuilder()
    let plan = builder.plan(
        from: PlannedCommandClassification(
            capability: "task.create",
            confidence: 0.91,
            primaryText: nil,
            taskTitle: nil,
            dueDate: nil,
            noteTitle: nil,
            noteBody: nil,
            eventTitle: nil,
            shortcutName: nil,
            url: nil,
            routingDomain: nil,
            routingListHint: nil,
            routingAudience: nil,
            suggestedProviderID: nil,
            normalizedIntent: nil,
            tags: []
        ),
        request: RouterRequest(rawInput: "Create reminder call mom tomorrow"),
        availableSkills: []
    )

    #expect(plan == nil)
}

@Test func appleFoundationPlanBuilderDoesNotAttachDueDateToTaskCompletion() {
    let builder = AppleFoundationPlanBuilder()
    let plan = builder.plan(
        from: PlannedCommandClassification(
            capability: "task.complete",
            confidence: 0.94,
            primaryText: nil,
            taskTitle: "feed the dog",
            dueDate: "2026-03-16T09:00:00+01:00",
            noteTitle: nil,
            noteBody: nil,
            eventTitle: nil,
            shortcutName: nil,
            url: nil,
            routingDomain: nil,
            routingListHint: nil,
            routingAudience: nil,
            suggestedProviderID: nil,
            normalizedIntent: nil,
            tags: []
        ),
        request: RouterRequest(rawInput: "Complete feed the dog tomorrow"),
        availableSkills: []
    )

    #expect(plan?.capability == "task.complete")
    #expect(plan?.parameters["title"] == .string("feed the dog"))
    #expect(plan?.parameters["due_date"] == nil)
}
