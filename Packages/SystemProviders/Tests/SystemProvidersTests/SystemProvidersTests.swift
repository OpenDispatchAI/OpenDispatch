import Executors
import Foundation
import RouterCore
import SystemProviders
import Testing

private actor TestReminderStore: ReminderStore {
    private(set) var createdTasks: [(title: String, notes: String?, dueDate: Date?)] = []

    func createTask(title: String, notes: String?, dueDate: Date?) async throws -> String {
        createdTasks.append((title, notes, dueDate))
        return "reminder-1"
    }

    func completeTask(title: String) async throws -> Bool {
        false
    }

    func snapshot() -> [(title: String, notes: String?, dueDate: Date?)] {
        createdTasks
    }
}

@Test func localLogProviderSucceeds() async {
    let provider = LocalLogProvider(sink: InMemoryLocalLogSink())
    let result = await provider.execute(
        plan: RouterPlan(
            capability: "log.event",
            parameters: [
                "text": .string("Dog pooped"),
                "tags": .array([.string("dog")]),
                "normalized_intent": .string("log.event"),
            ],
            confidence: 1
        ),
        mode: .live
    )

    #expect(result.success)
    #expect(result.metadata["status"] == .string("logged"))
}

private actor TestCalendarStore: CalendarStore {
    private(set) var events: [(title: String, start: Date?, end: Date?, notes: String?)] = []

    func createEvent(title: String, start: Date?, end: Date?, notes: String?) async throws -> String {
        events.append((title, start, end, notes))
        return "event-1"
    }

    func snapshot() -> [(title: String, start: Date?, end: Date?, notes: String?)] {
        events
    }
}

private actor TestClipboard: ClipboardWriting {
    private(set) var lastCopied: String?

    func copy(_ text: String) async {
        lastCopied = text
    }
}

// MARK: - Native Executor Tests

@Test func remindersNativeExecutorCreatesTask() async throws {
    let store = TestReminderStore()
    let executor = RemindersNativeExecutor(store: store)
    let plan = RouterPlan(
        capability: "task.create",
        parameters: [
            "title": .string("Call mom"),
            "notes": .string("Important"),
            "due_date": .string("2026-03-16T09:00:00+01:00"),
        ],
        confidence: 1.0
    )
    let result = await executor.execute(plan: plan, mode: .live)
    #expect(result.success)
    #expect(result.metadata["status"] == .string("created"))
    #expect(await store.snapshot().count == 1)
}

@Test func remindersNativeExecutorDryRun() async {
    let executor = RemindersNativeExecutor(store: TestReminderStore())
    let plan = RouterPlan(
        capability: "task.create",
        parameters: ["title": .string("Test")],
        confidence: 1.0
    )
    let result = await executor.execute(plan: plan, mode: .dryRun)
    #expect(result.success)
    #expect(result.metadata["status"] == .string("dry_run"))
}

@Test func calendarNativeExecutorCreatesEvent() async throws {
    let store = TestCalendarStore()
    let executor = CalendarNativeExecutor(store: store)
    let plan = RouterPlan(
        capability: "calendar.event.create",
        parameters: ["title": .string("Dentist")],
        confidence: 1.0
    )
    let result = await executor.execute(plan: plan, mode: .live)
    #expect(result.success)
    #expect(result.metadata["status"] == .string("created"))
    #expect(await store.snapshot().count == 1)
}

@Test func notesNativeExecutorOpensNotes() async {
    let clipboard = TestClipboard()
    let executor = NotesNativeExecutor(
        clipboard: clipboard,
        urlHandler: NoOpURLHandler()
    )
    let plan = RouterPlan(
        capability: "note.create",
        parameters: ["body": .string("Meeting notes")],
        confidence: 1.0
    )
    let result = await executor.execute(plan: plan, mode: .live)
    #expect(result.success)
    #expect(await clipboard.lastCopied == "Meeting notes")
}

@Test func shortcutsRunNativeExecutorRunsShortcut() async {
    let executor = ShortcutsRunNativeExecutor(urlHandler: NoOpURLHandler())
    let plan = RouterPlan(
        capability: "shortcut.run",
        parameters: ["name": .string("Morning Routine")],
        confidence: 1.0
    )
    let result = await executor.execute(plan: plan, mode: .dryRun)
    #expect(result.success)
    #expect(result.metadata["shortcut_name"] == .string("Morning Routine"))
}

// MARK: - NativeExecutorRegistry Tests

@Test func nativeExecutorRegistryReturnsExecutorForBundledID() {
    let executor = RemindersNativeExecutor(store: TestReminderStore())
    let registry = NativeExecutorRegistry(executors: ["apple_reminders": executor])
    #expect(registry.executor(for: "apple_reminders") != nil)
}

@Test func nativeExecutorRegistryReturnsNilForUnknownID() {
    let registry = NativeExecutorRegistry(executors: [:])
    #expect(registry.executor(for: "malicious_skill") == nil)
}
