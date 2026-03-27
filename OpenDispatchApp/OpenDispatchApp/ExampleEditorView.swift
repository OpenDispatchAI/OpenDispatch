import SwiftData
import SwiftUI

struct ExampleEditorView: View {
    let skillID: String
    let actionID: String
    let skillName: String
    let actionTitle: String

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query private var examples: [UserExampleRecord]
    @State private var newText = ""
    @State private var newIsNegative = false
    @State private var duplicateWarning: String?

    init(skillID: String, actionID: String, skillName: String, actionTitle: String) {
        self.skillID = skillID
        self.actionID = actionID
        self.skillName = skillName
        self.actionTitle = actionTitle

        let sid = skillID
        let aid = actionID
        _examples = Query(
            filter: #Predicate<UserExampleRecord> {
                $0.skillID == sid && $0.actionID == aid
            },
            sort: \.createdAt
        )
    }

    var body: some View {
        List {
            Section("Your Examples") {
                if examples.isEmpty {
                    Text("No custom examples yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(examples) { example in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(example.text)
                            if example.isNegative {
                                Text("Negative example")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        Spacer()
                    }
                }
                .onDelete(perform: deleteExamples)
            }

            Section("Add Example") {
                TextField("e.g., add milk to my shopping list", text: $newText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: newText) { _, _ in duplicateWarning = nil }
                if let duplicateWarning {
                    Label(duplicateWarning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Toggle("Negative example", isOn: $newIsNegative)
                Button("Add") {
                    addExample()
                }
                .disabled(newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("\(skillName) — \(actionTitle)")
    }

    private func addExample() {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        // Check for duplicates — search across all user examples, not just this action
        if let existing = findDuplicate(text: trimmed) {
            duplicateWarning = "This example already exists on \(existing.skillName) \u{2014} \(existing.actionTitle)"
            return
        }

        let record = UserExampleRecord(
            skillID: skillID,
            actionID: actionID,
            skillName: skillName,
            actionTitle: actionTitle,
            text: trimmed,
            isNegative: newIsNegative
        )
        modelContext.insert(record)
        try? modelContext.save()
        newText = ""
        newIsNegative = false
        duplicateWarning = nil
        appState.scheduleRecompile()
    }

    private func findDuplicate(text: String) -> UserExampleRecord? {
        let descriptor = FetchDescriptor<UserExampleRecord>(
            predicate: #Predicate { $0.text == text }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func deleteExamples(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(examples[index])
        }
        try? modelContext.save()
        appState.scheduleRecompile()
    }
}
