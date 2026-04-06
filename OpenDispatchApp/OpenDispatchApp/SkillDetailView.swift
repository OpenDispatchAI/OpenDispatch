import SkillRegistry
import SwiftData
import SwiftUI

struct SkillDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Query(sort: \InstalledSkillRecord.skillID) private var installedSkills: [InstalledSkillRecord]
    let entry: SkillRepositoryEntry
    let repositoryLocation: String

    @State private var skillInfo: SkillInfo?
    @State private var isLoadingInfo = false
    @State private var isInstalling = false
    @State private var loadError: String?

    private var isInstalled: Bool {
        guard let skillID = entry.skillID else { return false }
        return installedSkills.contains { $0.skillID == skillID }
    }

    var body: some View {
        List {
            headerSection
            if let skillInfo {
                actionsSection(skillInfo.actions)
            } else if isLoadingInfo {
                Section {
                    ProgressView("Loading details...")
                }
            } else if let loadError {
                Section {
                    Text(loadError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle(entry.name)
        .safeAreaInset(edge: .bottom) {
            installButton
                .padding()
                .background(.bar)
        }
        .task {
            await loadInfo()
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                if let author = entry.author {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let version = entry.version {
                    Text("Version \(version)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let description = skillInfo?.description ?? entry.description {
                    Text(description)
                        .font(.body)
                }
                if let tags = entry.tags, tags.isEmpty == false {
                    HStack(spacing: 4) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.fill.tertiary, in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private func actionsSection(_ actions: [SkillInfoAction]) -> some View {
        Section("Actions (\(actions.count))") {
            ForEach(actions) { action in
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.body)
                    Text(action.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var installButton: some View {
        if isInstalled {
            Button(role: .destructive) {
                Task { await uninstall() }
            } label: {
                Label("Uninstall", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(isInstalling)
        } else {
            Button {
                Task { await install() }
            } label: {
                if isInstalling {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Install", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isInstalling || entry.downloadURL == nil)
        }
    }

    private func loadInfo() async {
        guard let skillID = entry.skillID,
              let baseURL = SkillStoreService.baseURL(from: repositoryLocation) else {
            return
        }
        isLoadingInfo = true
        do {
            let service = SkillStoreService()
            skillInfo = try await service.fetchSkillInfo(skillID: skillID, baseURL: baseURL)
        } catch {
            loadError = error.localizedDescription
        }
        isLoadingInfo = false
    }

    private func install() async {
        isInstalling = true
        await appState.installSkillFromStore(entry: entry, repositoryLocation: repositoryLocation)
        isInstalling = false
    }

    private func uninstall() async {
        guard let skillID = entry.skillID else { return }
        isInstalling = true
        await appState.uninstallSkill(skillID: skillID)
        isInstalling = false
    }
}
