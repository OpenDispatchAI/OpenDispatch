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

@Test func repositoryIndexDecodesAPIFormat() throws {
    let json = """
    {
        "version": 1,
        "generated_at": "2026-04-05T17:10:09+00:00",
        "skill_count": 1,
        "skills": [
            {
                "skill_id": "tesla",
                "name": "Tesla",
                "version": "1.0.0",
                "description": "Control your car via OpenDispatch.",
                "author": "OpenDispatch",
                "action_count": 30,
                "example_count": 114,
                "tags": ["automotive"],
                "requires_bridge_shortcut": false,
                "download_url": "https://opendispatch.ai/api/v1/skills/tesla/download"
            }
        ]
    }
    """
    let data = Data(json.utf8)
    let index = try JSONDecoder().decode(SkillRepositoryIndex.self, from: data)

    #expect(index.version == 1)
    #expect(index.skillCount == 1)
    #expect(index.skills.count == 1)

    let entry = index.skills[0]
    #expect(entry.skillID == "tesla")
    #expect(entry.name == "Tesla")
    #expect(entry.downloadURL == "https://opendispatch.ai/api/v1/skills/tesla/download")
    #expect(entry.tags == ["automotive"])
    #expect(entry.path == nil)
}

@Test func skillInfoDecodesFromAPI() throws {
    let json = """
    {
        "skill_id": "tesla",
        "name": "Tesla",
        "version": "1.0.0",
        "description": "Full implementation of the official Tesla app.",
        "author": "OpenDispatch",
        "author_url": null,
        "tags": ["automotive"],
        "languages": [],
        "requires_bridge_shortcut": false,
        "bridge_shortcut": "OpenDispatch - Tesla V1",
        "bridge_shortcut_share_url": "https://opendispatch.ai/api/v1/skills/tesla/shortcut",
        "actions": [
            {
                "id": "vehicle.unlock",
                "title": "Unlock",
                "description": "Unlock your Tesla vehicle",
                "example_count": 5,
                "has_parameters": false,
                "confirmation": null
            },
            {
                "id": "vehicle.climate.set_temperature",
                "title": "Set Temperature",
                "description": "Set the Tesla cabin temperature",
                "example_count": 4,
                "has_parameters": true,
                "confirmation": null
            }
        ],
        "created_at": "2026-04-04T20:06:30+00:00",
        "updated_at": "2026-04-05T16:55:57+00:00"
    }
    """
    let data = Data(json.utf8)
    let info = try JSONDecoder().decode(SkillInfo.self, from: data)

    #expect(info.skillID == "tesla")
    #expect(info.name == "Tesla")
    #expect(info.actions.count == 2)
    #expect(info.actions[0].id == "vehicle.unlock")
    #expect(info.actions[0].hasParameters == false)
    #expect(info.actions[1].hasParameters == true)
    #expect(info.bridgeShortcut == "OpenDispatch - Tesla V1")
}
