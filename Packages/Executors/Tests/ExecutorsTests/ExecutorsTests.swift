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
