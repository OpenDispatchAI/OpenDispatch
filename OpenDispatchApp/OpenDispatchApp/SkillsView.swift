import SkillRegistry
import SwiftData
import SwiftUI

struct SkillsView: View {
    @EnvironmentObject private var appState: AppState
    @Query(sort: \InstalledSkillRecord.skillID) private var installedSkills: [InstalledSkillRecord]
    @Query(sort: \RepositorySourceRecord.name) private var repositories: [RepositorySourceRecord]
    @State private var indexEntries: [(repository: RepositorySourceRecord, entries: [SkillRepositoryEntry])] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    Section {
                        ProgressView("Loading skills...")
                    }
                }
                if let loadError {
                    Section {
                        Text(loadError)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                ForEach(indexEntries, id: \.repository.id) { group in
                    Section(group.repository.name) {
                        ForEach(group.entries, id: \.name) { entry in
                            NavigationLink {
                                SkillDetailView(
                                    entry: entry,
                                    repositoryLocation: group.repository.location
                                )
                            } label: {
                                SkillRowView(
                                    entry: entry,
                                    isInstalled: isInstalled(entry)
                                )
                            }
                        }
                    }
                }
                if indexEntries.isEmpty, !isLoading {
                    Section {
                        Text("No repositories configured. Add one in Settings.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Skills")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadAllIndexes() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                await loadAllIndexes()
            }
        }
    }

    private func isInstalled(_ entry: SkillRepositoryEntry) -> Bool {
        guard let skillID = entry.skillID else { return false }
        return installedSkills.contains { $0.skillID == skillID }
    }

    private func loadAllIndexes() async {
        isLoading = true
        loadError = nil
        var results: [(repository: RepositorySourceRecord, entries: [SkillRepositoryEntry])] = []

        do {
            let skillService = try appState.makeSkillService()
            for repository in repositories {
                guard let source = repository.repositorySource else { continue }
                do {
                    let index = try await skillService.repositoryIndex(for: source)
                    results.append((repository: repository, entries: index.skills))
                } catch {
                    loadError = "Failed to load \(repository.name): \(error.localizedDescription)"
                }
            }
        } catch {
            loadError = error.localizedDescription
        }

        indexEntries = results
        isLoading = false
    }
}

private struct SkillRowView: View {
    let entry: SkillRepositoryEntry
    let isInstalled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.name)
                        .font(.body.weight(.semibold))
                    if isInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                if let author = entry.author {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let description = entry.description {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
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
        .padding(.vertical, 2)
    }
}
