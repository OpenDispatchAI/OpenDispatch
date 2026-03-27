import CapabilityRegistry
import Foundation
import OSLog
import RouterCore

#if canImport(FoundationModels)
import FoundationModels
#endif

struct PlannedCommandClassification: Sendable, Equatable {
    var capability: String
    var confidence: Double
    var primaryText: String?
    var taskTitle: String?
    var dueDate: String?
    var noteTitle: String?
    var noteBody: String?
    var eventTitle: String?
    var shortcutName: String?
    var url: String?
    var suggestedProviderID: String?
    var normalizedIntent: String?
    var tags: [String]
}

private extension PlannedCommandClassification {
    var debugSummary: String {
        """
        capability=\(capability), confidence=\(confidence), primaryText=\(primaryText ?? "nil"), taskTitle=\(taskTitle ?? "nil"), dueDate=\(dueDate ?? "nil"), noteTitle=\(noteTitle ?? "nil"), noteBody=\(noteBody ?? "nil"), eventTitle=\(eventTitle ?? "nil"), shortcutName=\(shortcutName ?? "nil"), url=\(url ?? "nil"), suggestedProviderID=\(suggestedProviderID ?? "nil"), normalizedIntent=\(normalizedIntent ?? "nil"), tags=\(tags)
        """
    }

    func merged(
        taskTitle: String? = nil,
        dueDate: String? = nil,
        noteTitle: String? = nil,
        noteBody: String? = nil,
        eventTitle: String? = nil,
        shortcutName: String? = nil,
        url: String? = nil,
        normalizedIntent: String? = nil,
        tags: [String]? = nil
    ) -> PlannedCommandClassification {
        PlannedCommandClassification(
            capability: capability,
            confidence: confidence,
            primaryText: primaryText,
            taskTitle: taskTitle ?? self.taskTitle,
            dueDate: dueDate ?? self.dueDate,
            noteTitle: noteTitle ?? self.noteTitle,
            noteBody: noteBody ?? self.noteBody,
            eventTitle: eventTitle ?? self.eventTitle,
            shortcutName: shortcutName ?? self.shortcutName,
            url: url ?? self.url,
            suggestedProviderID: suggestedProviderID,
            normalizedIntent: normalizedIntent ?? self.normalizedIntent,
            tags: tags ?? self.tags
        )
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    init(content: GeneratedContent) throws {
        self.init(
            capability: try content.value(String.self, forProperty: "capability"),
            confidence: try content.value(Double.self, forProperty: "confidence"),
            primaryText: try content.value(String?.self, forProperty: "primaryText"),
            taskTitle: try content.value(String?.self, forProperty: "taskTitle"),
            dueDate: try content.value(String?.self, forProperty: "dueDate"),
            noteTitle: try content.value(String?.self, forProperty: "noteTitle"),
            noteBody: try content.value(String?.self, forProperty: "noteBody"),
            eventTitle: try content.value(String?.self, forProperty: "eventTitle"),
            shortcutName: try content.value(String?.self, forProperty: "shortcutName"),
            url: try content.value(String?.self, forProperty: "url"),
            suggestedProviderID: try content.value(String?.self, forProperty: "suggestedProviderID"),
            normalizedIntent: try content.value(String?.self, forProperty: "normalizedIntent"),
            tags: try content.value([String].self, forProperty: "tags")
        )
    }
    #endif
}

struct AppleFoundationPlanBuilder {
    private let classifier = RuleBasedCapabilityClassifier()
    private let canonicalCapabilities = Set(CanonicalCapabilities.default.all.map { $0.id.rawValue })

    private struct ValidationFailure: Error, Sendable {
        let message: String
    }

    func plan(
        from classification: PlannedCommandClassification,
        request: RouterRequest,
        availableSkills: [PlannerSkillContext]
    ) -> RouterPlan? {
        try? planResult(
            from: classification,
            request: request,
            availableSkills: availableSkills
        ).get()
    }

    func validationFailure(
        for classification: PlannedCommandClassification,
        request: RouterRequest,
        availableSkills: [PlannerSkillContext]
    ) -> String? {
        switch planResult(
            from: classification,
            request: request,
            availableSkills: availableSkills
        ) {
        case .success:
            nil
        case let .failure(reason):
            reason.message
        }
    }

    private func planResult(
        from classification: PlannedCommandClassification,
        request: RouterRequest,
        availableSkills: [PlannerSkillContext]
    ) -> Result<RouterPlan, ValidationFailure> {
        let normalizedCapability = classification.capability.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedCapability.isEmpty == false else {
            return .failure(ValidationFailure(message: "Capability was empty."))
        }

        let capability = CapabilityID(rawValue: normalizedCapability)
        let supportedCapabilities = canonicalCapabilities.union(availableSkills.map(\.capability.rawValue))
        guard supportedCapabilities.contains(capability.rawValue) else {
            return .failure(ValidationFailure(message: "Unsupported capability '\(capability.rawValue)'."))
        }

        let normalizedInput = request.rawInput.lowercased()
        let heuristicPlan = classifier.classify(rawInput: request.rawInput)
        let suggestedProviderID = validatedSuggestedProviderID(
            classification.suggestedProviderID,
            availableSkills: availableSkills
        )

        if canonicalCapabilities.contains(capability.rawValue) == false {
            let fallbackProviderID = suggestedProviderID
                ?? availableSkills.first(where: { $0.capability == capability })?.providerID
                ?? "custom_skill"
            return .success(classifier.planForMatchedSkill(
                capability: capability,
                rawInput: request.rawInput,
                normalizedInput: normalizedInput,
                suggestedProviderID: fallbackProviderID
            ))
        }

        guard let parameters = parameters(
            for: capability,
            classification: classification,
            rawInput: request.rawInput
        ) else {
            return .failure(
                ValidationFailure(message: parameterFailureReason(for: capability, classification: classification))
            )
        }

        return .success(RouterPlan(
            capability: capability,
            parameters: parameters,
            confidence: clampedConfidence(classification.confidence),
            title: title(for: capability),
            suggestedProviderID: suggestedProviderID ?? heuristicPlan?.suggestedProviderID
        ))
    }

    private func parameters(
        for capability: CapabilityID,
        classification: PlannedCommandClassification,
        rawInput: String
    ) -> [String: JSONValue]? {
        switch capability.rawValue {
        case "task.create":
            guard let title = firstNonEmpty(classification.taskTitle, classification.primaryText) else {
                return nil
            }
            var parameters: [String: JSONValue] = ["title": .string(title)]
            if let dueDate = cleanedOptionalString(classification.dueDate) {
                parameters["due_date"] = .string(dueDate)
            }
            return parameters
        case "task.complete":
            guard let title = firstNonEmpty(classification.taskTitle, classification.primaryText) else {
                return nil
            }
            return ["title": .string(title)]
        case "note.create":
            let body = firstNonEmpty(classification.noteBody, classification.primaryText) ?? rawInput
            let title = firstNonEmpty(classification.noteTitle, inferredNoteTitle(from: body))
                ?? inferredNoteTitle(from: body)
            return [
                "title": .string(title),
                "body": .string(body),
            ]
        case "calendar.event.create":
            guard let title = firstNonEmpty(
                classification.eventTitle,
                classification.primaryText,
                classification.taskTitle
            ) else {
                return nil
            }
            return ["title": .string(title)]
        case "shortcut.run":
            guard let name = firstNonEmpty(classification.shortcutName, classification.primaryText) else {
                return nil
            }
            return ["name": .string(name)]
        case "url.open":
            guard let destination = firstNonEmpty(classification.url, classification.primaryText) else {
                return nil
            }
            return ["url": .string(normalizedURL(from: destination))]
        case "log.event":
            return [
                "text": .string(rawInput),
                "tags": .array(cleanedTags(from: classification.tags).map(JSONValue.string)),
                "normalized_intent": .string(
                    firstNonEmpty(classification.normalizedIntent, capability.rawValue) ?? capability.rawValue
                ),
            ]
        default:
            return nil
        }
    }

    private func title(for capability: CapabilityID) -> String {
        switch capability.rawValue {
        case "task.create":
            "Create Task"
        case "task.complete":
            "Complete Task"
        case "note.create":
            "Create Note"
        case "calendar.event.create":
            "Create Calendar Event"
        case "shortcut.run":
            "Run Shortcut"
        case "url.open":
            "Open URL"
        default:
            "Log Event"
        }
    }

    private func parameterFailureReason(
        for capability: CapabilityID,
        classification: PlannedCommandClassification
    ) -> String {
        switch capability.rawValue {
        case "task.create", "task.complete":
            return "Capability \(capability.rawValue) requires taskTitle or primaryText, but both were empty."
        case "calendar.event.create":
            return "Capability calendar.event.create requires eventTitle, taskTitle, or primaryText, but all were empty."
        case "shortcut.run":
            return "Capability shortcut.run requires shortcutName or primaryText, but both were empty."
        case "url.open":
            return "Capability url.open requires url or primaryText, but both were empty."
        default:
            return "Capability \(capability.rawValue) did not produce a usable parameter set."
        }
    }

    private func validatedSuggestedProviderID(
        _ providerID: String?,
        availableSkills: [PlannerSkillContext]
    ) -> String? {
        guard let providerID = cleanedOptionalString(providerID) else {
            return nil
        }
        return availableSkills.contains(where: { $0.providerID == providerID }) ? providerID : nil
    }

    private func cleanedTags(from tags: [String]) -> [String] {
        Array(
            Set(
                tags
                    .compactMap(cleanedOptionalString)
                    .prefix(4)
            )
        ).sorted()
    }

    private func inferredNoteTitle(from body: String) -> String {
        body.split(separator: " ").prefix(5).joined(separator: " ")
    }

    private func normalizedURL(from text: String) -> String {
        if text.contains("://") {
            return text
        }
        if text.contains(".") {
            return "https://\(text)"
        }
        return text
    }

    private func clampedConfidence(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    private func cleanedOptionalString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap(cleanedOptionalString).first
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
private enum AppleFoundationSchemas {
    static func classification(allowedCapabilities: [String]) -> GenerationSchema {
        GenerationSchema(
            type: GeneratedContent.self,
            description: "Structured OpenDispatch command classification.",
            properties: [
                .init(
                    name: "capability",
                    description: "Capability ID for the command. Must be one of the exact supported capability IDs.",
                    type: String.self,
                    guides: [.anyOf(allowedCapabilities)]
                ),
                .init(
                    name: "confidence",
                    description: "Classification confidence between 0 and 1.",
                    type: Double.self,
                    guides: [.range(0.0 ... 1.0)]
                ),
                .init(
                    name: "primaryText",
                    description: "Short extracted text payload in the user's original language.",
                    type: String?.self
                ),
                .init(
                    name: "taskTitle",
                    description: "Task or reminder title for task.create or task.complete.",
                    type: String?.self
                ),
                .init(
                    name: "dueDate",
                    description: "Absolute ISO 8601 due date for task.create when the input includes a date or time.",
                    type: String?.self
                ),
                .init(
                    name: "noteTitle",
                    description: "Note title for note.create.",
                    type: String?.self
                ),
                .init(
                    name: "noteBody",
                    description: "Note body for note.create.",
                    type: String?.self
                ),
                .init(
                    name: "eventTitle",
                    description: "Calendar event title for calendar.event.create.",
                    type: String?.self
                ),
                .init(
                    name: "shortcutName",
                    description: "Shortcut name for shortcut.run.",
                    type: String?.self
                ),
                .init(
                    name: "url",
                    description: "Absolute URL or resolvable host for url.open.",
                    type: String?.self
                ),
                .init(
                    name: "suggestedProviderID",
                    description: "Suggested provider ID only when it exactly matches one of the installed skill providers listed in the prompt.",
                    type: String?.self
                ),
                .init(
                    name: "normalizedIntent",
                    description: "Normalized intent label when capability is log.event.",
                    type: String?.self
                ),
                .init(
                    name: "tags",
                    description: "Up to four short tags when capability is log.event.",
                    type: [String].self,
                    guides: [.maximumCount(4)]
                ),
            ]
        )
    }

    static let task = GenerationSchema(
        type: GeneratedContent.self,
        description: "Structured task extraction result.",
        properties: [
            .init(
                name: "taskTitle",
                description: "Task or reminder title in the user's original language. Required and non-empty.",
                type: String.self
            ),
            .init(
                name: "dueDate",
                description: "Absolute ISO 8601 due date with timezone offset when the input includes a date or time. Otherwise null.",
                type: String?.self
            ),
        ]
    )

    static let taskCompletion = GenerationSchema(
        type: GeneratedContent.self,
        description: "Structured task completion extraction result.",
        properties: [
            .init(
                name: "taskTitle",
                description: "Existing task title in the user's original language. Required and non-empty.",
                type: String.self
            ),
        ]
    )

    static let note = GenerationSchema(
        type: GeneratedContent.self,
        description: "Structured note extraction result.",
        properties: [
            .init(
                name: "noteBody",
                description: "Note body in the user's original language. Required and non-empty.",
                type: String.self
            ),
            .init(
                name: "noteTitle",
                description: "Short note title in the user's original language.",
                type: String?.self
            ),
        ]
    )

    static let event = GenerationSchema(
        type: GeneratedContent.self,
        description: "Structured calendar event extraction result.",
        properties: [
            .init(
                name: "eventTitle",
                description: "Calendar event title in the user's original language. Required and non-empty.",
                type: String.self
            ),
        ]
    )

    static let shortcut = GenerationSchema(
        type: GeneratedContent.self,
        description: "Structured shortcut extraction result.",
        properties: [
            .init(
                name: "shortcutName",
                description: "Shortcut name in the user's original language. Required and non-empty.",
                type: String.self
            ),
        ]
    )

    static let url = GenerationSchema(
        type: GeneratedContent.self,
        description: "Structured URL extraction result.",
        properties: [
            .init(
                name: "url",
                description: "Absolute URL or resolvable host. Required and non-empty.",
                type: String.self
            ),
        ]
    )

    static let logEvent = GenerationSchema(
        type: GeneratedContent.self,
        description: "Structured log event extraction result.",
        properties: [
            .init(
                name: "normalizedIntent",
                description: "Normalized intent label for the logged event. Required and non-empty.",
                type: String.self
            ),
            .init(
                name: "tags",
                description: "Up to four short tags for the logged event.",
                type: [String].self,
                guides: [.maximumCount(4)]
            ),
        ]
    )
}

@available(iOS 26.0, macOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
enum AppleFoundationPlanner {
    private static let logger = Logger(subsystem: "com.iterica.OpenDispatch", category: "AppleFoundationPlanner")

    static func plan(
        request: RouterRequest,
        availableSkills: [PlannerSkillContext],
        builder: AppleFoundationPlanBuilder
    ) async throws -> RouterPlan {
        debugLog("Starting Apple Foundation planning for input: \(request.rawInput)")
        let model = SystemLanguageModel(useCase: .contentTagging)
        switch model.availability {
        case .available:
            debugLog("Apple Foundation model availability: available")
            break
        case let .unavailable(reason):
            debugLog("Apple Foundation model availability: unavailable (\(String(describing: reason)))")
            throw unavailableError(for: reason)
        }

        let session = LanguageModelSession(
            model: model,
            instructions: instructions(for: availableSkills)
        )
        let supportedCapabilities = Array(
            Set(
                CanonicalCapabilities.default.all.map(\.id.rawValue)
                    + availableSkills.map(\.capability.rawValue)
            )
        ).sorted()

        do {
            let response = try await session.respond(
                to: prompt(for: request, availableSkills: availableSkills),
                schema: AppleFoundationSchemas.classification(allowedCapabilities: supportedCapabilities),
                options: GenerationOptions(
                    temperature: 0.0,
                    maximumResponseTokens: 320
                )
            )
            debugLog("Raw classification structured output: \(response.content.jsonString)")
            var classification = try PlannedCommandClassification(content: response.content)
            debugLog("Model classification: \(classification.debugSummary)")

            if let failureReason = builder.validationFailure(
                for: classification,
                request: request,
                availableSkills: availableSkills
            ) {
                debugLog("Initial classification rejected: \(failureReason)")
                if let repaired = try await extractMissingFieldsIfNeeded(
                    for: classification,
                    request: request,
                    model: model
                ) {
                    classification = repaired
                    debugLog("Capability-specific extraction: \(classification.debugSummary)")
                }
            }

            if let plan = builder.plan(
                from: classification,
                request: request,
                availableSkills: availableSkills
            ) {
                debugLog("Planner accepted classification for capability \(plan.capability.rawValue)")
                return plan
            }

            let failureReason = builder.validationFailure(
                for: classification,
                request: request,
                availableSkills: availableSkills
            ) ?? "Unknown validation failure."
            debugLog("Planner rejected classification: \(failureReason)")
            throw ModelBackendError.generationFailed(
                "The on-device model returned a plan OpenDispatch could not use. \(failureReason) capability=\(classification.capability)"
            )
        } catch let error as LanguageModelSession.GenerationError {
            debugLog("LanguageModelSession.GenerationError: \(error.localizedDescription)")
            throw ModelBackendError.generationFailed(
                "Apple Foundation classification failed: \(error.localizedDescription)"
            )
        } catch {
            debugLog("Apple Foundation planning error: \(error.localizedDescription)")
            throw ModelBackendError.generationFailed(
                "Apple Foundation classification failed: \(error.localizedDescription)"
            )
        }
    }

    private static func extractMissingFieldsIfNeeded(
        for classification: PlannedCommandClassification,
        request: RouterRequest,
        model: SystemLanguageModel
    ) async throws -> PlannedCommandClassification? {
        switch classification.capability {
        case "task.create":
            let isTaskTitleMissing = isEmpty(classification.taskTitle) && isEmpty(classification.primaryText)
            let isDueDateMissing = isEmpty(classification.dueDate)
            guard isTaskTitleMissing || isDueDateMissing else {
                return nil
            }
            let taskContent = try await extractStructuredContent(
                model: model,
                instructions: taskExtractionInstructions,
                prompt: taskExtractionPrompt(for: request),
                schema: AppleFoundationSchemas.task,
                label: "task extraction"
            )
            let taskTitle = try taskContent.value(String.self, forProperty: "taskTitle")
            let dueDate = try taskContent.value(String?.self, forProperty: "dueDate")
            return classification.merged(taskTitle: taskTitle, dueDate: dueDate)
        case "task.complete":
            guard isEmpty(classification.taskTitle), isEmpty(classification.primaryText) else {
                return nil
            }
            let taskContent = try await extractStructuredContent(
                model: model,
                instructions: "Extract the task title only. Preserve the user's language and do not include command words.",
                prompt: contextualPrompt(for: request, userPrompt: request.rawInput),
                schema: AppleFoundationSchemas.taskCompletion,
                label: "task completion extraction"
            )
            let taskTitle = try taskContent.value(String.self, forProperty: "taskTitle")
            return classification.merged(taskTitle: taskTitle)
        case "note.create":
            guard isEmpty(classification.noteBody), isEmpty(classification.primaryText) else {
                return nil
            }
            let noteContent = try await extractStructuredContent(
                model: model,
                instructions: "Extract the note body and optional short title. Preserve the user's language.",
                prompt: contextualPrompt(for: request, userPrompt: request.rawInput),
                schema: AppleFoundationSchemas.note,
                label: "note extraction"
            )
            return classification.merged(
                noteTitle: try noteContent.value(String?.self, forProperty: "noteTitle"),
                noteBody: try noteContent.value(String.self, forProperty: "noteBody")
            )
        case "calendar.event.create":
            guard isEmpty(classification.eventTitle), isEmpty(classification.primaryText), isEmpty(classification.taskTitle) else {
                return nil
            }
            let eventContent = try await extractStructuredContent(
                model: model,
                instructions: "Extract the calendar event title only. Preserve the user's language.",
                prompt: contextualPrompt(for: request, userPrompt: request.rawInput),
                schema: AppleFoundationSchemas.event,
                label: "event extraction"
            )
            return classification.merged(eventTitle: try eventContent.value(String.self, forProperty: "eventTitle"))
        case "shortcut.run":
            guard isEmpty(classification.shortcutName), isEmpty(classification.primaryText) else {
                return nil
            }
            let shortcutContent = try await extractStructuredContent(
                model: model,
                instructions: "Extract the shortcut name only. Preserve the user's language.",
                prompt: contextualPrompt(for: request, userPrompt: request.rawInput),
                schema: AppleFoundationSchemas.shortcut,
                label: "shortcut extraction"
            )
            return classification.merged(shortcutName: try shortcutContent.value(String.self, forProperty: "shortcutName"))
        case "url.open":
            guard isEmpty(classification.url), isEmpty(classification.primaryText) else {
                return nil
            }
            let urlContent = try await extractStructuredContent(
                model: model,
                instructions: "Extract the URL or website destination only.",
                prompt: contextualPrompt(for: request, userPrompt: request.rawInput),
                schema: AppleFoundationSchemas.url,
                label: "url extraction"
            )
            return classification.merged(url: try urlContent.value(String.self, forProperty: "url"))
        case "log.event":
            guard isEmpty(classification.normalizedIntent), classification.tags.isEmpty else {
                return nil
            }
            let logEventContent = try await extractStructuredContent(
                model: model,
                instructions: "Extract a normalized intent label and up to four short tags for this log event.",
                prompt: contextualPrompt(for: request, userPrompt: request.rawInput),
                schema: AppleFoundationSchemas.logEvent,
                label: "log event extraction"
            )
            return classification.merged(
                normalizedIntent: try logEventContent.value(String.self, forProperty: "normalizedIntent"),
                tags: try logEventContent.value([String].self, forProperty: "tags")
            )
        default:
            return nil
        }
    }

    private static func extractStructuredContent(
        model: SystemLanguageModel,
        instructions: String,
        prompt: String,
        schema: GenerationSchema,
        label: String
    ) async throws -> GeneratedContent {
        debugLog("\(label) starting with prompt: \(prompt)")
        debugLog("\(label) instructions: \(instructions)")
        let extractionModel = SystemLanguageModel(useCase: .general)
        let session = LanguageModelSession(model: extractionModel, instructions: instructions)
        do {
            let response = try await session.respond(
                to: prompt,
                schema: schema,
                options: GenerationOptions(temperature: 0.0, maximumResponseTokens: 120)
            )
            debugLog("\(label) raw structured output: \(response.content.jsonString)")
            return response.content
        } catch {
            debugLog("\(label) failed: \(error.localizedDescription)")
            throw error
        }
    }

    private static func isEmpty(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }

    private static func debugLog(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        print("[AppleFoundationPlanner] \(message)")
    }

    private static var taskExtractionInstructions: String {
        """
        Extract the task title and optional due date.
        Return the actionable reminder content in the user's original language.
        Do not restate the command as labels like "reminder", "task", "set up", or "create reminder".
        If the input contains a date or time, resolve it to an absolute ISO 8601 timestamp with timezone offset and store it in dueDate.
        Remove date and time phrases from taskTitle when dueDate captures them successfully.
        If there is no date or time in the input, dueDate must be null.

        Valid example:
        Input: Add a reminder to feed the dog tomorrow
        Output taskTitle: feed the dog
        Output dueDate: 2026-03-16T09:00:00+01:00

        Valid example:
        Input: Herinner me eraan oma morgen te bellen
        Output taskTitle: oma te bellen
        Output dueDate: 2026-03-16T09:00:00+01:00

        Invalid example:
        Input: Add a reminder to feed the dog tomorrow
        Output taskTitle: reminder set up
        """
    }

    private static func taskExtractionPrompt(for request: RouterRequest) -> String {
        contextualPrompt(for: request, userPrompt: request.rawInput)
    }

    private static func contextualPrompt(for request: RouterRequest, userPrompt: String) -> String {
        """
        \(temporalContext(for: request))

        User command:
        \(userPrompt)
        """
    }

    private static func temporalContext(for request: RouterRequest) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .autoupdatingCurrent
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]

        return """
        Reference timestamp: \(formatter.string(from: request.timestamp))
        Current timezone: \(TimeZone.autoupdatingCurrent.identifier)
        Resolve relative dates like today, tomorrow, tonight, next Monday, and 8pm against this reference timestamp and timezone.
        """
    }

    private static func instructions(for availableSkills: [PlannerSkillContext]) -> String {
        let supportedCapabilities = (
            CanonicalCapabilities.default.all.map { $0.id.rawValue } +
            availableSkills.map(\.capability.rawValue)
        ).sorted()

        return """
        You are the on-device command classifier for OpenDispatch.
        Classify one user command into a single router plan.
        Preserve the user's language in extracted text.
        Do not translate titles, note bodies, shortcut names, or URLs.
        You must choose a capability from this exact set and copy it exactly: \(supportedCapabilities.joined(separator: ", ")).
        Never invent a capability name, alias, or synonym.
        Installed skills may provide trigger guidance and examples in their documentation. Use that guidance when it is relevant.
        Prefer task.create for reminders, todos, and follow-ups.
        Prefer task.complete when the user is finishing or completing an existing task.
        Prefer log.event when the text is not a clear actionable command.
        Fill only the fields relevant to the chosen capability.
        If the capability is task.create or task.complete, taskTitle must be non-empty.
        If task.create includes a date or time, dueDate must be an absolute ISO 8601 timestamp with timezone offset.
        If the capability is calendar.event.create, eventTitle must be non-empty.
        If the capability is shortcut.run, shortcutName must be non-empty.
        If the capability is url.open, url must be non-empty.
        Only set suggestedProviderID when it exactly matches one of the installed skill providers listed in the prompt.
        """
    }

    private static func prompt(for request: RouterRequest, availableSkills: [PlannerSkillContext]) -> String {
        let skillBlock: String
        if availableSkills.isEmpty {
            skillBlock = "Installed skills: none."
        } else {
            skillBlock = """
            Installed skills:
            \(availableSkills.map(skillDescription).joined(separator: "\n"))
            """
        }

        return """
        \(temporalContext(for: request))

        Supported canonical capabilities:
        - log.event: capture non-actionable or ambiguous text
        - task.create: create a reminder or task
        - task.complete: mark a task complete
        - note.create: create a note
        - calendar.event.create: create a calendar event
        - shortcut.run: run a shortcut
        - url.open: open a URL or deep link

        \(skillBlock)

        User command:
        \(request.rawInput)
        """
    }

    private static func skillDescription(_ skill: PlannerSkillContext) -> String {
        let examples = skill.examples.joined(separator: ", ")
        let documentation = skill.documentation
            .replacingOccurrences(of: "\n", with: " | ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "- name: \(skill.name); capability: \(skill.capability.rawValue); providerID: \(skill.providerID); examples: [\(examples)]; documentation: \(documentation)"
    }

    private static func unavailableError(
        for reason: SystemLanguageModel.Availability.UnavailableReason
    ) -> ModelBackendError {
        switch reason {
        case .deviceNotEligible:
            return .unavailable("Apple Foundation Models needs an Apple Intelligence-capable device.")
        case .appleIntelligenceNotEnabled:
            return .unavailable("Apple Intelligence is turned off. Enable it in Settings to use the on-device model.")
        case .modelNotReady:
            return .unavailable("The Apple on-device model is not ready yet. Finish downloading the model and try again.")
        @unknown default:
            return .unavailable("Apple Foundation Models is unavailable on this device right now.")
        }
    }
}
#endif
