import CapabilityRegistry
import Testing

@Test func canonicalRegistryContainsExpectedCapabilities() throws {
    let registry = try CapabilityRegistry()

    #expect(registry.contains("task.create"))
    #expect(registry.contains("calendar.event.create"))
    #expect(registry.contains("url.open"))
}

@Test func providerRegistrationIndexesByCapability() throws {
    var registry = try CapabilityRegistry()
    try registry.registerProvider(
        ProviderDescriptor(
            id: "reminders",
            displayName: "Apple Reminders",
            kind: .system,
            priority: 90,
            capabilities: ["task.create", "task.complete"]
        )
    )

    let providers = registry.providers(for: "task.create")

    #expect(providers.count == 1)
    #expect(providers.first?.id == "reminders")
}

@Test func invalidCapabilityFormatIsRejected() {
    #expect(CapabilityID.isValid("TaskCreate") == false)
    #expect(CapabilityID.isValid("task") == false)
    #expect(CapabilityID.isValid("task.create") == true)
}
