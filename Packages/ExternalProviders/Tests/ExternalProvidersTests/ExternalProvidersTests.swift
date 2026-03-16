import Foundation
import Executors
import ExternalProviders
import RouterCore
import SkillRegistry
import Testing

@Test func manifestBackedProviderExecutesLegacyURLScheme() async {
    let skill = InstalledSkill(
        manifest: SkillManifest(
            name: "ticktick_add_task",
            capability: "task.create",
            executor: .urlScheme,
            urlTemplate: "ticktick://add?title={{title}}",
            providerName: "TickTick",
            providerID: "ticktick"
        ),
        documentation: "Adds a task.",
        sourceLocation: "/tmp/ticktick"
    )
    let provider = ManifestBackedProvider(
        skill: skill,
        urlHandler: NoOpURLHandler(),
        logSink: InMemoryLocalLogSink()
    )

    let result = await provider.execute(
        plan: RouterPlan(
            capability: "task.create",
            parameters: ["title": .string("Buy milk")],
            confidence: 1
        ),
        mode: .dryRun
    )

    #expect(result.success)
    #expect(result.metadata["url"] == .string("ticktick://add?title=Buy%20milk"))
}

@Test func manifestBackedProviderExecutesBridgeShortcutPayload() async throws {
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
                    paramsSchema: ["vehicle": "string"],
                    keywords: ["tesla", "climate"],
                    examples: ["turn on the car ac"]
                ),
            ],
            name: "Tesla"
        ),
        documentation: "Tesla bridge skill.",
        sourceLocation: "/tmp/tesla"
    )
    let provider = ManifestBackedProvider(
        skill: skill,
        urlHandler: NoOpURLHandler(),
        logSink: InMemoryLocalLogSink()
    )

    let result = await provider.execute(
        plan: RouterPlan(
            capability: "vehicle.climate.start",
            parameters: ["vehicle": .string("default")],
            confidence: 1
        ),
        mode: .dryRun
    )

    #expect(result.success)
    #expect(result.toolCall?.payload["shortcut_name"] == JSONValue.string("OpenDispatch - Tesla"))

    let urlString = try #require(result.toolCall?.payload["url"]?.stringValue)
    let url = try #require(URL(string: urlString))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let payloadText = try #require(components.queryItems?.first(where: { $0.name == "text" })?.value)
    let payloadData = Data(payloadText.utf8)
    let payload = try JSONDecoder().decode([String: JSONValue].self, from: payloadData)

    #expect(payload["action"] == .string("vehicle.climate.start"))
    #expect(payload["params"] == .object(["vehicle": .string("default")]))
}
