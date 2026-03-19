import Executors
import RouterCore
import Testing

@Test func urlSchemeExecutorInterpolatesTemplate() async {
    let executor = URLSchemeExecutor(urlHandler: NoOpURLHandler())
    let result = await executor.execute(
        urlTemplate: "ticktick://add?title={{title}}",
        parameters: ["title": .string("Buy Milk & Eggs")],
        mode: .dryRun
    )

    #expect(result.success)
    #expect(result.metadata["url"] == .string("ticktick://add?title=Buy%20Milk%20%26%20Eggs"))
}

@Test func shortcutsExecutorBuildsEncodedURL() async {
    let executor = ShortcutsExecutor(urlHandler: NoOpURLHandler())
    let result = await executor.execute(
        shortcutName: "Capture Task",
        parameters: ["title": .string("Buy milk")],
        mode: .dryRun
    )

    #expect(result.success)
    #expect(result.metadata["url"]?.stringValue?.contains("shortcuts://run-shortcut") == true)
}

@Test func shortcutsBridgeExecutorSubstitutesTemplates() async {
    let executor = ShortcutsBridgeExecutor(
        bridgeShortcut: "My Shortcut",
        actionArguments: [
            "vehicle.climate.set_temperature": [
                "action": .string("vehicle.unlock"),
                "temp": .string("{{temperature}}"),
            ]
        ],
        urlHandler: NoOpURLHandler()
    )
    let plan = RouterPlan(
        capability: "vehicle.climate.set_temperature",
        parameters: ["temperature": .integer(21)],
        confidence: 1.0
    )
    let result = await executor.execute(plan: plan, mode: .dryRun)
    #expect(result.success)
    #expect(result.metadata["shortcut_name"] == .string("My Shortcut"))
}

@Test func shortcutsBridgeExecutorFailsWithoutShortcut() async {
    let executor = ShortcutsBridgeExecutor(
        bridgeShortcut: nil,
        actionArguments: [:],
        urlHandler: NoOpURLHandler()
    )
    let plan = RouterPlan(capability: "test", parameters: [:], confidence: 1.0)
    let result = await executor.execute(plan: plan, mode: .live)
    #expect(result.success == false)
}

@Test func shortcutsBridgeExecutorUsesCorrectActionArguments() async {
    let executor = ShortcutsBridgeExecutor(
        bridgeShortcut: "Tesla Bridge",
        actionArguments: [
            "vehicle.unlock": ["action": .string("unlock")],
            "vehicle.lock": ["action": .string("lock")],
        ],
        urlHandler: NoOpURLHandler()
    )
    let lockPlan = RouterPlan(capability: "vehicle.lock", parameters: [:], confidence: 1.0)
    let result = await executor.execute(plan: lockPlan, mode: .dryRun)
    #expect(result.success)
}
