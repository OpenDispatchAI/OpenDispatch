import SwiftData
import SwiftUI

struct ExampleEditorView: View {
    let skillID: String
    let actionID: String
    let skillName: String
    let actionTitle: String
    let builtInExamples: [String]
    let builtInNegativeExamples: [String]

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query private var userExamples: [UserExampleRecord]
    @Query private var suppressedExamples: [SuppressedExampleRecord]
    @State private var newText = ""
    @State private var newIsNegative = false
    @State private var duplicateWarning: String?

    init(
        skillID: String,
        actionID: String,
        skillName: String,
        actionTitle: String,
        builtInExamples: [String] = [],
        builtInNegativeExamples: [String] = []
    ) {
        self.skillID = skillID
        self.actionID = actionID
        self.skillName = skillName
        self.actionTitle = actionTitle
        self.builtInExamples = builtInExamples
        self.builtInNegativeExamples = builtInNegativeExamples

        let sid = skillID
        let aid = actionID
        _userExamples = Query(
            filter: #Predicate<UserExampleRecord> {
                $0.skillID == sid && $0.actionID == aid
            },
            sort: \.createdAt
        )
        _suppressedExamples = Query(
            filter: #Predicate<SuppressedExampleRecord> {
                $0.skillID == sid && $0.actionID == aid
            }
        )
    }

    private func isSuppressed(_ text: String) -> Bool {
        suppressedExamples.contains { $0.text == text }
    }

    var body: some View {
        List {
            Section("Built-in Examples") {
                ForEach(builtInExamples, id: \.self) { example in
                    Toggle(example, isOn: Binding(
                        get: { !isSuppressed(example) },
                        set: { enabled in
                            if enabled {
                                unsuppress(example)
                            } else {
                                suppress(example)
                            }
                        }
                    ))
                    .font(.body)
                }
                if builtInNegativeExamples.isEmpty == false {
                    ForEach(builtInNegativeExamples, id: \.self) { example in
                        HStack {
                            Toggle(example, isOn: Binding(
                                get: { !isSuppressed(example) },
                                set: { enabled in
                                    if enabled {
                                        unsuppress(example)
                                    } else {
                                        suppress(example)
                                    }
                                }
                            ))
                            Text("NEG")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            Section("Your Examples") {
                if userExamples.isEmpty {
                    Text("No custom examples yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(userExamples) { example in
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
        .navigationTitle("\(skillName) \u{2014} \(actionTitle)")
    }

    // MARK: - Suppression

    private func suppress(_ text: String) {
        let record = SuppressedExampleRecord(
            skillID: skillID,
            actionID: actionID,
            text: text
        )
        modelContext.insert(record)
        try? modelContext.save()
        appState.scheduleRecompile()
    }

    private func unsuppress(_ text: String) {
        if let record = suppressedExamples.first(where: { $0.text == text }) {
            modelContext.delete(record)
            try? modelContext.save()
            appState.scheduleRecompile()
        }
    }

    // MARK: - User Examples

    private func addExample() {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

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
            modelContext.delete(userExamples[index])
        }
        try? modelContext.save()
        appState.scheduleRecompile()
    }
}
