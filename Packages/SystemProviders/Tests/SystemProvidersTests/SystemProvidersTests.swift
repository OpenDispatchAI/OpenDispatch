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

@Test func remindersProviderCreatesReminder() async throws {
    let store = TestReminderStore()
    let provider = RemindersProvider(reminderStore: store)

    let result = await provider.execute(
        plan: RouterPlan(
            capability: "task.create",
            parameters: [
                "title": .string("Call mom"),
                "notes": .string("From OpenDispatch"),
                "due_date": .string("2026-03-16T09:00:00+01:00"),
            ],
            confidence: 1
        ),
        mode: .live
    )

    #expect(result.success)
    #expect(result.metadata["status"] == .string("created"))
    #expect(result.metadata["identifier"] == .string("reminder-1"))
    #expect(result.metadata["due_date"] == .string("2026-03-16T09:00:00+01:00"))
    #expect(await store.snapshot().count == 1)
    #expect(await store.snapshot().first?.title == "Call mom")
    #expect(await store.snapshot().first?.dueDate != nil)
}
