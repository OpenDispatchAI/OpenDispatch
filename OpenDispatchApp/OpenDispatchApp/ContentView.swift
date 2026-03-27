import CapabilityRegistry
import RouterCore
import SkillCompiler
import SkillRegistry
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showExampleWizard = false

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "bolt.circle")
                }
            SkillManagerView()
                .tabItem {
                    Label("Skills", systemImage: "shippingbox")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
            DebugView()
                .tabItem {
                    Label("Debug", systemImage: "ladybug")
                }
        }
        .alert(
            "Set Up Routing?",
            isPresented: Binding(
                get: { appState.wizardPromptSkill != nil },
                set: { if !$0 { appState.wizardPromptSkill = nil } }
            )
        ) {
            Button("Set Up Now") {
                appState.wizardPromptSkill = nil
                showExampleWizard = true
            }
            Button("Later", role: .cancel) {
                appState.wizardPromptSkill = nil
            }
        } message: {
            if let skill = appState.wizardPromptSkill {
                let shared = appState.sharedCapabilities(for: skill)
                Text("\(skill.name) can also handle \(shared.joined(separator: ", ")). Want to set up which commands go where?")
            }
        }
        .sheet(isPresented: $showExampleWizard) {
            ExampleWizardView()
        }
    }
}

private struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @Query(sort: \DispatchEventRecord.timestamp, order: .reverse) private var events: [DispatchEventRecord]
    @StateObject private var speechCapture = SpeechCaptureManager()
    @State private var searchText = ""
    @FocusState private var inputFocused: Bool

    private var filteredEvents: [DispatchEventRecord] {
        guard searchText.isEmpty == false else { return Array(events.prefix(25)) }
        return events.filter {
            $0.rawInput.localizedCaseInsensitiveContains(searchText)
                || $0.capability.localizedCaseInsensitiveContains(searchText)
                || $0.providerID.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Dispatch")
                            .font(.headline)
                        Text("Planner: \(appState.backendSelection.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if appState.dryRunEnabled {
                            Text("Dry Run Mode is enabled. External actions will be planned, but not actually launched.")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                        TextField("Type a command", text: $appState.commandInput, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .focused($inputFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                inputFocused = false
                            }
                        HStack {
                            Button(speechCapture.isListening ? "Stop Listening" : "Listen") {
                                Task {
                                    if speechCapture.isListening {
                                        speechCapture.stop()
                                    } else {
                                        await speechCapture.start()
                                    }
                                }
                            }
                            .buttonStyle(.bordered)

                            Button("Dispatch") {
                                inputFocused = false
                                Task {
                                    await appState.submitCurrentInput(
                                        source: speechCapture.transcript.isEmpty ? .text : .speech
                                    )
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(appState.commandInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if let error = speechCapture.errorMessage, error.isEmpty == false {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        if let error = appState.lastError, error.isEmpty == false {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        if let latestLog = appState.executionLogs.first {
                            Text(latestLog)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Recent Events")
                                .font(.headline)
                            Spacer()
                            TextField("Search", text: $searchText)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 180)
                        }

                        ForEach(filteredEvents) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.rawInput)
                                    .font(.body)
                                Text("\(event.capability) -> \(event.providerID)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(event.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("OpenDispatch")
            .alert(
                "Confirm Action",
                isPresented: Binding(
                    get: { appState.pendingConfirmation != nil },
                    set: { _ in }
                ),
                actions: {
                    Button("Cancel", role: .cancel) {
                        appState.dismissPendingConfirmation()
                    }
                    Button("Continue") {
                        Task {
                            await appState.confirmPendingAction()
                        }
                    }
                },
                message: {
                    if let pending = appState.pendingConfirmation {
                        Text("Run \(pending.plan.capability.rawValue) with \(pending.providerName)?")
                    }
                }
            )
            .confirmationDialog(
                "Choose Destination",
                isPresented: Binding(
                    get: { appState.pendingDestinationChoice != nil },
                    set: { _ in }
                ),
                titleVisibility: .visible
            ) {
                if let choice = appState.pendingDestinationChoice {
                    ForEach(choice.options) { option in
                        Button(option.providerDisplayName) {
                            Task {
                                await appState.choosePendingDestination(option)
                            }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    appState.dismissPendingDestinationChoice()
                }
            } message: {
                if let choice = appState.pendingDestinationChoice {
                    let label = choice.plan.capability.rawValue
                    Text("Select where to send this \(label) action.")
                }
            }
            .onChange(of: appState.captureModeRequested) { _, requested in
                guard requested else { return }
                inputFocused = true
                Task {
                    await speechCapture.start()
                    appState.captureModeRequested = false
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: speechCapture.transcript) { _, newValue in
                if newValue.isEmpty == false {
                    appState.commandInput = newValue
                }
            }
        }
    }
}

private struct SkillManagerView: View {
    @EnvironmentObject private var appState: AppState
    @Query(sort: \InstalledSkillRecord.installedAt, order: .reverse) private var installedSkills: [InstalledSkillRecord]
    @Query(sort: \RepositorySourceRecord.name) private var repositories: [RepositorySourceRecord]
    @State private var isImporting = false
    @State private var isAddingRepository = false
    @State private var repositoryName = ""
    @State private var repositoryKind: RepositorySourceKind = .httpIndex
    @State private var repositoryLocation = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Installed Skills") {
                    if installedSkills.isEmpty {
                        Text("No skills installed.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(installedSkills) { skill in
                            let capabilities = skill.installedSkill?.manifest.capabilities.map(\.rawValue).joined(separator: ", ")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(skill.name)
                                Text("\(capabilities?.isEmpty == false ? capabilities! : skill.capability) via \(skill.providerName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(skill.sourceLocation)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                Section("Repositories") {
                    ForEach(repositories) { repository in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(repository.name)
                            Text(repository.location)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let error = repository.lastError, error.isEmpty == false {
                                Text(error)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            } else {
                                Text("Discovered skills: \(repository.discoveredSkillsCount)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                Section("Validation") {
                    if appState.validationMessages.isEmpty {
                        Text("No validation issues.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.validationMessages, id: \.self) { message in
                            Text(message)
                        }
                    }
                }
            }
            .navigationTitle("Skill Manager")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Refresh") {
                        Task { await appState.refreshRepositories() }
                    }
                    Button("Repository") {
                        isAddingRepository = true
                    }
                    Button("Import") {
                        isImporting = true
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case let .success(urls):
                    Task { await appState.importSkillDirectories(urls) }
                case .failure:
                    break
                }
            }
            .sheet(isPresented: $isAddingRepository) {
                NavigationStack {
                    Form {
                        TextField("Name", text: $repositoryName)
                        Picker("Type", selection: $repositoryKind) {
                            ForEach(RepositorySourceKind.allCases, id: \.self) { kind in
                                Text(kind.rawValue).tag(kind)
                            }
                        }
                        TextField("Location", text: $repositoryLocation)
                    }
                    .navigationTitle("Add Repository")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                isAddingRepository = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                Task {
                                    await appState.addRepository(
                                        name: repositoryName,
                                        kind: repositoryKind,
                                        location: repositoryLocation
                                    )
                                    repositoryName = ""
                                    repositoryLocation = ""
                                    repositoryKind = .httpIndex
                                    isAddingRepository = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var newLanguageCode = ""

    private var sortedCapabilities: [String] {
        appState.providerOptions.keys.sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Languages") {
                    ForEach(appState.configuredLanguages, id: \.self) { lang in
                        HStack {
                            Text(Locale.current.localizedString(forLanguageCode: lang) ?? lang)
                            Spacer()
                            if appState.configuredLanguages.count > 1 {
                                Button(role: .destructive) {
                                    appState.configuredLanguages.removeAll { $0 == lang }
                                    Task { await appState.recompileSkillIndex() }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                            }
                        }
                    }
                    HStack {
                        TextField("Language code (e.g., nl)", text: $newLanguageCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Add") {
                            let code = newLanguageCode.trimmingCharacters(in: .whitespaces).lowercased()
                            guard code.isEmpty == false,
                                  appState.configuredLanguages.contains(code) == false else { return }
                            appState.configuredLanguages.append(code)
                            newLanguageCode = ""
                            Task { await appState.recompileSkillIndex() }
                        }
                        .disabled(newLanguageCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if appState.configuredLanguages != ["en"] {
                        Label("Multilingual support requires downloading an additional model (~470MB). Coming soon.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Multilingual routing requires a downloadable model. English is supported out of the box.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Model Backend") {
                    Picker("Planner", selection: Binding(
                        get: { appState.backendSelection },
                        set: { appState.updateBackendSelection($0) }
                    )) {
                        ForEach(BackendSelection.allCases) { backend in
                            Text(backend.title).tag(backend)
                        }
                    }
                    Toggle(
                        "Enable Remote Escalation",
                        isOn: Binding(
                            get: { appState.escalationEnabled },
                            set: { appState.updateEscalation($0) }
                        )
                    )
                    Toggle(
                        "Dry Run Mode",
                        isOn: Binding(
                            get: { appState.dryRunEnabled },
                            set: { appState.updateDryRun($0) }
                        )
                    )
                }

                Section("Provider Preferences") {
                    ForEach(sortedCapabilities, id: \.self) { capability in
                        Picker(capability, selection: Binding(
                            get: { appState.selectedProvider(for: capability) },
                            set: { appState.setPreferredProvider($0, for: capability) }
                        )) {
                            Text("System Default").tag("")
                            ForEach(appState.providerOptions[capability] ?? []) { option in
                                Text(option.name).tag(option.id)
                            }
                        }
                    }
                }

                Section("Custom Examples") {
                    NavigationLink {
                        ExampleWizardView()
                    } label: {
                        Label("Teach OpenDispatch", systemImage: "text.bubble")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct DebugView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                compiledIndexSection
                userExamplesSection
                orphanedExamplesSection
                matchCandidatesSection
                routerPlanSection
                executionLogsSection
                errorSection
            }
            .navigationTitle("Debug")
        }
    }

    // MARK: - Compiled Index

    private var compiledIndexSection: some View {
        Section("Compiled Index") {
            switch appState.compileStatus {
            case .notCompiled:
                Label("Not compiled", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Button("Compile Now") {
                    Task { await appState.recompileSkillIndex() }
                }
            case let .compiling(progress):
                HStack(spacing: 8) {
                    ProgressView()
                    Text(progress)
                        .font(.caption)
                }
            case let .compiled(entryCount, skillCount, timestamp):
                Label("\(entryCount) embeddings from \(skillCount) skills", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                Text("Compiled \(timestamp.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Show compiled skills breakdown
                ForEach(appState.compiledManifests, id: \.skillID) { manifest in
                    NavigationLink {
                        CompiledSkillDetailView(manifest: manifest, index: appState.compiledIndex)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(manifest.name)
                                    .font(.subheadline)
                                Text("\(manifest.actions.count) actions, \(manifest.actions.flatMap(\.examples).count) examples")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if manifest.builtIn {
                                Text("Built-in")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                Button("Recompile") {
                    Task { await appState.recompileSkillIndex() }
                }
            case let .failed(error):
                Label("Compile failed", systemImage: "xmark.circle")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                Button("Retry") {
                    Task { await appState.recompileSkillIndex() }
                }
            }
        }
    }

    // MARK: - User Examples

    @ViewBuilder
    private var userExamplesSection: some View {
        if let index = appState.compiledIndex {
            let userEntries = index.entries.filter { $0.source == .user }
            if userEntries.isEmpty == false {
                Section("User Examples in Index") {
                    let grouped = Dictionary(grouping: userEntries) { "\($0.skillID)|\($0.actionID)" }
                    ForEach(grouped.keys.sorted(), id: \.self) { key in
                        let entries = grouped[key]!
                        let first = entries.first!
                        DisclosureGroup("\(first.skillName) — \(first.actionTitle) (\(entries.count))") {
                            ForEach(entries, id: \.originalExample) { entry in
                                HStack {
                                    Text(entry.originalExample)
                                        .font(.caption)
                                    Spacer()
                                    if entry.isNegative {
                                        Text("NEG")
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                    }
                                    Text(entry.language)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Orphaned Examples

    @ViewBuilder
    private var orphanedExamplesSection: some View {
        if appState.orphanedUserExamples.isEmpty == false {
            Section("Orphaned User Examples") {
                Label(
                    "\(appState.orphanedUserExamples.count) examples reference removed skills",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)

                ForEach(appState.orphanedUserExamples, id: \.text) { orphan in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(orphan.text).font(.caption)
                            Text("\(orphan.skillName) — \(orphan.actionTitle)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            deleteOrphan(orphan)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
    }

    private func deleteOrphan(_ orphan: UserExample) {
        let context = ModelContext(appState.modelContainer)
        let sid = orphan.skillID
        let aid = orphan.actionID
        let txt = orphan.text
        let descriptor = FetchDescriptor<UserExampleRecord>(
            predicate: #Predicate { $0.skillID == sid && $0.actionID == aid && $0.text == txt }
        )
        if let records = try? context.fetch(descriptor) {
            for record in records { context.delete(record) }
            try? context.save()
        }
        appState.orphanedUserExamples.removeAll { $0.skillID == sid && $0.actionID == aid && $0.text == txt }
    }

    // MARK: - Match Candidates

    private var matchCandidatesSection: some View {
        Section("Last Match Candidates") {
            if appState.lastMatchCandidates.isEmpty {
                Text("No matches yet. Dispatch a command to see routing results.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(Array(appState.lastMatchCandidates.enumerated()), id: \.offset) { rank, candidate in
                    HStack {
                        Text("#\(rank + 1)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(candidate.skillName) → \(candidate.actionTitle)")
                                .font(.subheadline)
                            Text(candidate.actionID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.1f%%", candidate.confidence * 100))
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(rank == 0 ? .bold : .regular)
                                .foregroundStyle(rank == 0 ? .green : .primary)
                            Text(String(format: "d=%.3f", candidate.distance))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Confidence gap
                if appState.lastMatchCandidates.count >= 2 {
                    let gap = appState.lastMatchCandidates[1].distance - appState.lastMatchCandidates[0].distance
                    HStack {
                        Text("Confidence gap")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.3f", gap))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(gap > 0.15 ? .green : .orange)
                        Text(gap > 0.15 ? "(clear)" : "(ambiguous)")
                            .font(.caption2)
                            .foregroundStyle(gap > 0.15 ? .green : .orange)
                    }
                }
            }
        }
    }

    // MARK: - RouterPlan JSON

    private var routerPlanSection: some View {
        Section("RouterPlan JSON") {
            if appState.lastPlanJSON.isEmpty {
                Text("No plan yet.")
                    .foregroundStyle(.secondary)
            } else {
                Text(appState.lastPlanJSON)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Execution Logs

    private var executionLogsSection: some View {
        Section("Execution Logs") {
            if appState.executionLogs.isEmpty {
                Text("No logs yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.executionLogs, id: \.self) { log in
                    Text(log)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Error

    @ViewBuilder
    private var errorSection: some View {
        if let error = appState.lastError, error.isEmpty == false {
            Section("Last Error") {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Compiled Skill Detail View

private struct CompiledSkillDetailView: View {
    let manifest: YAMLSkillManifest
    let index: CompiledIndex?
    @Environment(\.openURL) private var openURL
    @State private var showingInstallAlert = false

    var body: some View {
        List {
            Section("Skill Info") {
                LabeledContent("ID", value: manifest.skillID)
                LabeledContent("Version", value: manifest.version)
                if let shortcut = manifest.bridgeShortcut {
                    LabeledContent("Bridge Shortcut", value: shortcut)
                }
                LabeledContent("Built-in", value: manifest.builtIn ? "Yes" : "No")
            }

            if let shortcutName = manifest.bridgeShortcut {
                Section("Bridge Shortcut") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("This skill requires the shortcut **\(shortcutName)** to be installed in the Shortcuts app.", systemImage: "arrow.down.app")
                            .font(.callout)

                        if let shareURL = manifest.bridgeShortcutShareURL,
                           let url = URL(string: shareURL) {
                            Button {
                                showingInstallAlert = true
                            } label: {
                                Label("Install Bridge Shortcut", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.borderedProminent)
                            .alert("Install Shortcut", isPresented: $showingInstallAlert) {
                                Button("Cancel", role: .cancel) {}
                                Button("Open in Shortcuts") {
                                    openURL(url)
                                }
                            } message: {
                                Text("This will open the Shortcuts app to install \"\(shortcutName)\". You'll need to confirm the installation there.")
                            }
                        }

                        #if DEBUG
                        // Debug: open shortcuts app to verify installation
                        Button {
                            if let url = URL(string: "shortcuts://") {
                                openURL(url)
                            }
                        } label: {
                            Label("Open Shortcuts App", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.bordered)
                        #endif
                    }
                }
            }

            ForEach(manifest.actions, id: \.id) { action in
                Section(action.title) {
                    LabeledContent("Action ID", value: action.id)

                    if let desc = action.description {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let args = action.shortcutArguments, args.isEmpty == false {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Shortcut Arguments")
                                .font(.caption)
                                .fontWeight(.semibold)
                            ForEach(args.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                Text("\(key): \(value.stringValue ?? "...")")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if action.requiresParameterExtraction {
                        Label("Requires Phase 2 extraction", systemImage: "brain")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Examples (\(action.examples.count))")
                            .font(.caption)
                            .fontWeight(.semibold)
                        ForEach(action.examples, id: \.self) { example in
                            let entryCount = index?.entries.filter {
                                $0.skillID == manifest.skillID
                                    && $0.actionID == action.id
                                    && $0.originalExample == example
                                    && $0.isNegative == false
                            }.count ?? 0
                            HStack {
                                Text("• \(example)")
                                    .font(.caption)
                                Spacer()
                                if entryCount > 0 {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }

                    if action.negativeExamples.isEmpty == false {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Negative Examples (\(action.negativeExamples.count))")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.red)
                            ForEach(action.negativeExamples, id: \.self) { example in
                                let entryCount = index?.entries.filter {
                                    $0.skillID == manifest.skillID
                                        && $0.actionID == action.id
                                        && $0.originalExample == example
                                        && $0.isNegative
                                }.count ?? 0
                                HStack {
                                    Text("• \(example)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if entryCount > 0 {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                    }

                    NavigationLink("Edit Custom Examples") {
                        ExampleEditorView(
                            skillID: manifest.skillID,
                            actionID: action.id,
                            skillName: manifest.name,
                            actionTitle: action.title
                        )
                    }

                    // Show compiled embeddings grouped by language
                    if let index {
                        let actionEntries = index.entries.filter {
                            $0.skillID == manifest.skillID
                                && $0.actionID == action.id
                                && $0.isNegative == false
                        }
                        let languages = Set(actionEntries.map(\.language)).sorted()

                        if languages.count > 1 || languages.first != "en" {
                            ForEach(languages, id: \.self) { language in
                                let langEntries = actionEntries.filter { $0.language == language }
                                let langName = Locale.current.localizedString(forLanguageCode: language) ?? language
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Compiled (\(langName))")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.blue)
                                    ForEach(langEntries, id: \.originalExample) { entry in
                                        HStack {
                                            Text("• \(entry.originalExample)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(manifest.name)
    }
}
