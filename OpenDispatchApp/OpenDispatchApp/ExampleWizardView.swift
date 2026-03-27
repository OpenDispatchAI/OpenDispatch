import SwiftData
import SwiftUI
import RouterCore
import SkillCompiler

struct ExampleWizardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speechCapture = SpeechCaptureManager()

    @State private var inputText = ""
    @State private var selectedSkillID: String?
    @State private var selectedActionID: String?
    @State private var currentStep: WizardStep = .input
    @State private var savedCount = 0
    @State private var duplicateWarning: String?

    enum WizardStep {
        case input
        case matchPreview
        case pickAction
        case saved
    }

    struct SkillAction: Identifiable {
        let skillID: String
        let skillName: String
        let actionID: String
        let actionTitle: String
        var id: String { "\(skillID)|\(actionID)" }
    }

    private var availableActions: [SkillAction] {
        appState.compiledManifests.flatMap { manifest in
            manifest.actions.map { action in
                SkillAction(skillID: manifest.skillID, skillName: manifest.name,
                            actionID: action.id, actionTitle: action.title)
            }
        }
    }

    @State private var actionSearchText = ""

    private var filteredActions: [SkillAction] {
        if actionSearchText.isEmpty { return availableActions }
        let query = actionSearchText.lowercased()
        return availableActions.filter {
            $0.skillName.lowercased().contains(query)
            || $0.actionTitle.lowercased().contains(query)
            || $0.actionID.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch currentStep {
                case .input:
                    inputStep
                case .matchPreview:
                    matchPreviewStep
                case .pickAction:
                    pickActionStep
                case .saved:
                    savedStep
                }
            }
            .navigationTitle("Teach OpenDispatch")
        }
    }

    // MARK: - Step 1: Input

    private var inputStep: some View {
        VStack(spacing: 24) {
            Text("Say or type something you'd say to OpenDispatch")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.top)

            TextField("e.g., add milk to my shopping list", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal)

            Button {
                if speechCapture.isListening {
                    speechCapture.stop()
                } else {
                    Task { await speechCapture.start() }
                }
            } label: {
                Label(
                    speechCapture.isListening ? "Stop" : "Speak",
                    systemImage: speechCapture.isListening ? "mic.fill" : "mic"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(speechCapture.isListening ? .red : .blue)
            .padding(.horizontal)

            Spacer()

            Button("Next") {
                currentStep = .matchPreview
            }
            .buttonStyle(.borderedProminent)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding()
        }
        .onChange(of: speechCapture.transcript) { _, newValue in
            if newValue.isEmpty == false {
                inputText = newValue
            }
        }
    }

    // MARK: - Step 2: Match Preview

    private var matchPreviewStep: some View {
        VStack(spacing: 16) {
            Text("Current match for:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\u{201C}\(inputText)\u{201D}")
                .font(.headline)
                .italic()

            if let index = appState.compiledIndex {
                let candidates = matchCandidates(in: index)
                if candidates.isEmpty {
                    Label("No close match found", systemImage: "questionmark.circle")
                        .foregroundStyle(.orange)
                } else {
                    List(candidates, id: \.self) { candidate in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(candidate.skillName) \u{2014} \(candidate.actionTitle)")
                                    .font(.body)
                                Text(candidate.actionID)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(candidate.confidence * 100))%")
                                .font(.caption.bold())
                                .foregroundStyle(candidate.confidence > 0.7 ? .green : .orange)
                        }
                    }
                    .listStyle(.plain)
                }
            } else {
                Text("Index not compiled \u{2014} preview unavailable")
                    .foregroundStyle(.secondary)
            }

            Text("Examples added in this session won't appear in the preview until recompilation completes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            HStack {
                Button("Back") { currentStep = .input }
                Spacer()
                Button("Choose Action") { currentStep = .pickAction }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    @State private var embeddingService: EmbeddingService? = {
        guard let backend = ParaphraseBackend() else { return nil }
        return EmbeddingService(backend: backend)
    }()

    private func matchCandidates(in index: CompiledIndex) -> [MatchCandidate] {
        guard let service = embeddingService,
              let vector = service.embed(inputText, language: "en") else { return [] }
        return index.nearestNeighbors(to: vector, count: 5)
    }

    // MARK: - Step 3: Pick Action

    private var pickActionStep: some View {
        VStack(spacing: 8) {
            Text("What should this do?")
                .font(.headline)
                .padding(.top)

            if let duplicateWarning {
                Label(duplicateWarning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
            }

            List(filteredActions) { item in
                Button {
                    selectedSkillID = item.skillID
                    selectedActionID = item.actionID
                    saveExample(
                        skillID: item.skillID,
                        actionID: item.actionID,
                        skillName: item.skillName,
                        actionTitle: item.actionTitle
                    )
                } label: {
                    VStack(alignment: .leading) {
                        Text("\(item.skillName) \u{2014} \(item.actionTitle)")
                        Text(item.actionID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $actionSearchText, prompt: "Search actions")

            Button("Back") { currentStep = .matchPreview }
                .padding()
        }
    }

    // MARK: - Step 4: Saved

    private var savedStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Saved!")
                .font(.title2.bold())

            Text("\u{201C}\(inputText)\u{201D} \u{2192} \(selectedSkillID ?? "") / \(selectedActionID ?? "")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Add Another") {
                inputText = ""
                selectedSkillID = nil
                selectedActionID = nil
                duplicateWarning = nil
                currentStep = .input
                savedCount += 1
            }
            .buttonStyle(.borderedProminent)

            Button("Done") {
                dismiss()
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Save

    private func saveExample(skillID: String, actionID: String, skillName: String, actionTitle: String) {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        // Check for duplicates across all user examples
        if let existing = findDuplicate(text: trimmed) {
            duplicateWarning = "This example already exists on \(existing.skillName) \u{2014} \(existing.actionTitle)"
            return
        }

        let record = UserExampleRecord(
            skillID: skillID,
            actionID: actionID,
            skillName: skillName,
            actionTitle: actionTitle,
            text: trimmed
        )
        modelContext.insert(record)
        try? modelContext.save()
        duplicateWarning = nil
        appState.scheduleRecompile()
        currentStep = .saved
    }

    private func findDuplicate(text: String) -> UserExampleRecord? {
        let descriptor = FetchDescriptor<UserExampleRecord>(
            predicate: #Predicate { $0.text == text }
        )
        return try? modelContext.fetch(descriptor).first
    }
}
