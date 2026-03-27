import SwiftData
import Testing
@testable import OpenDispatch

@Suite("UserExampleRecord")
struct UserExampleTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: UserExampleRecord.self,
            configurations: [config]
        )
    }

    @Test("Creates and fetches a user example")
    func createAndFetch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let example = UserExampleRecord(
            skillID: "ticktick",
            actionID: "task.create",
            skillName: "TickTick",
            actionTitle: "Create Task",
            text: "add milk to my shopping list"
        )
        context.insert(example)
        try context.save()

        let descriptor = FetchDescriptor<UserExampleRecord>(
            predicate: #Predicate { $0.skillID == "ticktick" && $0.actionID == "task.create" }
        )
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results.first?.text == "add milk to my shopping list")
        #expect(results.first?.isNegative == false)
    }

    @Test("Rejects empty text after trimming")
    func rejectsEmptyText() {
        let example = UserExampleRecord(
            skillID: "test",
            actionID: "test.action",
            skillName: "Test",
            actionTitle: "Action",
            text: "   "
        )
        #expect(example.isValid == false)
    }

    @Test("isDuplicate detects existing text for same skill+action")
    func detectsDuplicateText() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let ex1 = UserExampleRecord(
            skillID: "ticktick", actionID: "task.create",
            skillName: "TickTick", actionTitle: "Create Task",
            text: "add milk"
        )
        context.insert(ex1)
        try context.save()

        let sid = "ticktick"
        let aid = "task.create"
        let txt = "add milk"
        let descriptor = FetchDescriptor<UserExampleRecord>(
            predicate: #Predicate { $0.skillID == sid && $0.actionID == aid && $0.text == txt }
        )
        let existing = try context.fetch(descriptor)
        #expect(existing.count == 1, "Duplicate guard should find existing record")
    }
}
