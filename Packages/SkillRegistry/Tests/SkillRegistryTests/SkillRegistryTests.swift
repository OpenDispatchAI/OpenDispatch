import CapabilityRegistry
import Foundation
import RouterCore
import SkillRegistry
import Testing

@Test func urlSchemeSkillRequiresTemplate() throws {
    let registry = try CapabilityRegistry()
    let service = SkillRegistryService(capabilityRegistry: registry)

    let manifest = SkillManifest(
        name: "ticktick_add_task",
        capability: "task.create",
        executor: .urlScheme,
        providerName: "TickTick",
        providerID: "ticktick"
    )

    let errors = service.validate(manifest: manifest)

    #expect(errors.contains(.missingURLTemplate))
}

@Test func prdSkillAllowsCustomCapabilitiesAndGeneratesDefinitions() throws {
    let registry = try CapabilityRegistry()
    let service = SkillRegistryService(capabilityRegistry: registry)

    let manifest = SkillManifest(
        skillID: "tesla",
        version: "1.0.0",
        bridgeShortcutName: "OpenDispatch - Tesla",
        bridgeShortcutVersion: "1.0.0",
        bridgeInstallURL: "https://www.icloud.com/shortcuts/example",
        bridgeSetupInstructions: ["Install the shortcut.", "Set a default vehicle inside the shortcut."],
        bridgeInputTemplate: [
            "schema_version": .integer(1),
            "skill_id": .string("{{skill_id}}"),
            "skill_version": .string("{{skill_version}}"),
            "action": .string("{{action}}"),
            "params": .string("{{params}}"),
        ],
        actions: [
            SkillAction(
                action: "vehicle.climate.start",
                paramsSchema: ["vehicle": "string"],
                keywords: ["tesla", "ac", "climate"],
                examples: ["turn on the car ac"]
            ),
            SkillAction(
                action: "vehicle.lock",
                paramsSchema: ["vehicle": "string"],
                keywords: ["tesla", "lock"],
                examples: ["lock the tesla"]
            ),
        ],
        name: "Tesla"
    )

    #expect(service.validate(manifest: manifest).isEmpty)

    let definitions = service.capabilityDefinitions(from: [manifest])

    #expect(definitions.contains(where: { $0.id == "vehicle.climate.start" }))
    #expect(definitions.contains(where: { $0.id == "vehicle.lock" }))
}

@Test func planningContextsFlattenSkillActions() throws {
    let registry = try CapabilityRegistry()
    let service = SkillRegistryService(capabilityRegistry: registry)

    let skill = InstalledSkill(
        manifest: SkillManifest(
            skillID: "tesla",
            version: "1.0.0",
            bridgeShortcutName: "OpenDispatch - Tesla",
            bridgeShortcutVersion: "1.0.0",
            bridgeInstallURL: "https://www.icloud.com/shortcuts/example",
            bridgeSetupInstructions: ["Install the shortcut."],
            bridgeInputTemplate: [
                "schema_version": .integer(1),
                "skill_id": .string("{{skill_id}}"),
                "skill_version": .string("{{skill_version}}"),
                "action": .string("{{action}}"),
                "params": .string("{{params}}"),
            ],
            actions: [
                SkillAction(
                    action: "vehicle.climate.start",
                    keywords: ["tesla", "climate"],
                    examples: ["start tesla climate"]
                ),
                SkillAction(
                    action: "vehicle.lock",
                    keywords: ["tesla", "lock"],
                    examples: ["lock the tesla"]
                ),
            ],
            name: "Tesla"
        ),
        documentation: "Tesla bridge skill.",
        sourceLocation: "/tmp/tesla"
    )

    let contexts = service.planningContexts(from: [skill])

    #expect(contexts.count == 2)
    #expect(contexts.contains(where: { $0.capability == "vehicle.climate.start" && $0.providerID == "tesla" }))
    #expect(contexts.contains(where: { $0.capability == "vehicle.lock" && $0.providerID == "tesla" }))
    #expect(contexts.allSatisfy { $0.documentation.contains("Tesla bridge skill.") || $0.documentation.contains("Action:") })
}

@Test func repositoryIndexIsLoadedFromLocalFolder() async throws {
    let registry = try CapabilityRegistry()
    let service = SkillRegistryService(capabilityRegistry: registry)
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let index = SkillRepositoryIndex(
        repository: "Local",
        skills: [.init(name: "ticktick_add_task", path: "ticktick/add-task")]
    )
    let data = try JSONEncoder().encode(index)
    try data.write(to: root.appending(path: "index.json"))

    let result = try await service.repositoryIndex(
        for: RepositorySource(
            name: "Local",
            kind: .localFolder,
            location: root.path
        )
    )

    #expect(result.repository == "Local")
    #expect(result.skills.count == 1)
}
