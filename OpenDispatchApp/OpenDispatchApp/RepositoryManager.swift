import CapabilityRegistry
import Foundation
import SkillRegistry
import SwiftData

@MainActor @Observable final class RepositoryManager {

    static let defaultSkillRepoURL: String = {
        ProcessInfo.processInfo.environment["OD_SKILL_REPO_URL"]
            ?? "https://opendispatch.ai/api/v1/index.json"
    }()

    var log: (String) -> Void = { message in print("[OpenDispatch] \(message)") }

    let modelContainer: ModelContainer
    let compiler: SkillCompilationManager

    init(modelContainer: ModelContainer, compiler: SkillCompilationManager) {
        self.modelContainer = modelContainer
        self.compiler = compiler
    }

    func addRepository(name: String, kind: RepositorySourceKind, location: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false, trimmedLocation.isEmpty == false else { return }

        let context = ModelContext(modelContainer)
        context.insert(
            RepositorySourceRecord(
                name: trimmedName,
                kind: kind.rawValue,
                location: trimmedLocation
            )
        )
        try? context.save()
    }

    func refreshRepositories() async {
        do {
            let skillService = try makeSkillService()
            let context = ModelContext(modelContainer)
            let repositories = try context.fetch(FetchDescriptor<RepositorySourceRecord>())

            for repository in repositories {
                guard let source = repository.repositorySource else { continue }
                do {
                    let index = try await skillService.repositoryIndex(for: source)
                    repository.lastRefreshedAt = Date()
                    repository.lastError = nil
                    repository.discoveredSkillsCount = index.skills.count
                } catch {
                    repository.lastRefreshedAt = Date()
                    repository.lastError = error.localizedDescription
                }
            }
            try context.save()
        } catch {
            log("Error: \(error.localizedDescription)")
        }
    }

    func installSkillFromStore(entry: SkillRepositoryEntry, repositoryLocation: String) async {
        guard let downloadURLString = entry.downloadURL,
              let downloadURL = URL(string: downloadURLString),
              let skillID = entry.skillID else {
            log("Error: Skill has no download URL or ID.")
            return
        }

        do {
            let storeService = SkillStoreService()
            let yaml = try await storeService.downloadSkillYAML(from: downloadURL)
            let _ = try storeService.installSkill(yaml: yaml, skillID: skillID)

            let context = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<InstalledSkillRecord>(
                predicate: #Predicate { $0.skillID == skillID }
            )
            if let existing = (try? context.fetch(descriptor))?.first {
                existing.name = entry.name
                existing.version = entry.version ?? "1.0.0"
                existing.yamlFilePath = "\(skillID)/skill.yaml"
                existing.installedAt = Date()
            } else {
                context.insert(InstalledSkillRecord(
                    skillID: skillID,
                    name: entry.name,
                    version: entry.version ?? "1.0.0",
                    repositoryLocation: repositoryLocation,
                    yamlFilePath: "\(skillID)/skill.yaml"
                ))
            }
            try context.save()

            await compiler.recompileSkillIndex()
        } catch {
            log("Error: \(error.localizedDescription)")
        }
    }

    func uninstallSkill(skillID: String) async {
        do {
            let storeService = SkillStoreService()
            try storeService.uninstallSkill(skillID: skillID)

            let context = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<InstalledSkillRecord>(
                predicate: #Predicate { $0.skillID == skillID }
            )
            if let record = (try? context.fetch(descriptor))?.first {
                context.delete(record)
                try context.save()
            }

            await compiler.recompileSkillIndex()
        } catch {
            log("Error: \(error.localizedDescription)")
        }
    }

    func sharedCapabilities(for manifest: YAMLSkillManifest) -> [String] {
        let newCapabilities = Set(manifest.actions.map(\.id))
        let existingCapabilities = Set(compiler.compiledManifests.flatMap(\.actions).map(\.id))
        return Array(newCapabilities.intersection(existingCapabilities))
    }

    func makeSkillService() throws -> SkillRegistryService {
        SkillRegistryService(capabilityRegistry: try CapabilityRegistry())
    }

    func ensureDefaultRepository() async {
        let context = ModelContext(modelContainer)
        let existing = (try? context.fetch(FetchDescriptor<RepositorySourceRecord>())) ?? []
        guard existing.isEmpty else { return }

        context.insert(
            RepositorySourceRecord(
                name: "OpenDispatch Official",
                kind: RepositorySourceKind.httpIndex.rawValue,
                location: Self.defaultSkillRepoURL
            )
        )
        try? context.save()
    }
}
