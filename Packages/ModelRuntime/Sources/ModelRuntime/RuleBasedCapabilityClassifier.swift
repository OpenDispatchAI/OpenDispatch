import CapabilityRegistry
import Foundation
import RouterCore

struct RuleBasedCapabilityClassifier {
    func planForMatchedSkill(
        capability: CapabilityID,
        rawInput: String,
        normalizedInput: String,
        suggestedProviderID: String
    ) -> RouterPlan {
        RouterPlan(
            capability: capability,
            parameters: parameters(for: capability, rawInput: rawInput),
            confidence: 0.88,
            title: title(for: capability),
            routing: routingHints(for: capability, normalizedInput: normalizedInput),
            suggestedProviderID: suggestedProviderID
        )
    }

    func classify(rawInput: String) -> RouterPlan? {
        let normalizedInput = rawInput.lowercased()

        if let title = suffix(
            afterAnyOf: [
                "add ",
                "todo ",
                "remind me to ",
                "create reminder ",
                "create task ",
                "remember to ",
            ],
            in: normalizedInput,
            original: rawInput
        ) {
            return RouterPlan(
                capability: "task.create",
                parameters: ["title": .string(title)],
                confidence: 0.92,
                title: "Create Task",
                routing: routingHints(for: "task.create", normalizedInput: normalizedInput)
            )
        }

        if let title = suffix(
            afterAnyOf: [
                "complete ",
                "finish ",
                "done ",
                "mark done ",
            ],
            in: normalizedInput,
            original: rawInput
        ) {
            return RouterPlan(
                capability: "task.complete",
                parameters: ["title": .string(title)],
                confidence: 0.9,
                title: "Complete Task",
                routing: routingHints(for: "task.complete", normalizedInput: normalizedInput)
            )
        }

        if let body = suffix(
            afterAnyOf: ["note ", "write note ", "capture note "],
            in: normalizedInput,
            original: rawInput
        ) {
            return RouterPlan(
                capability: "note.create",
                parameters: [
                    "title": .string(inferTitle(from: body)),
                    "body": .string(body),
                ],
                confidence: 0.84,
                title: "Create Note"
            )
        }

        if let title = suffix(
            afterAnyOf: ["schedule ", "calendar "],
            in: normalizedInput,
            original: rawInput
        ) {
            return RouterPlan(
                capability: "calendar.event.create",
                parameters: ["title": .string(title)],
                confidence: 0.8,
                title: "Create Calendar Event"
            )
        }

        if let name = suffix(
            afterAnyOf: ["run shortcut ", "shortcut "],
            in: normalizedInput,
            original: rawInput
        ) {
            return RouterPlan(
                capability: "shortcut.run",
                parameters: ["name": .string(name)],
                confidence: 0.93,
                title: "Run Shortcut"
            )
        }

        if let destination = suffix(
            afterAnyOf: ["open "],
            in: normalizedInput,
            original: rawInput
        ) {
            return RouterPlan(
                capability: "url.open",
                parameters: ["url": .string(inferURL(from: destination))],
                confidence: 0.77,
                title: "Open URL"
            )
        }

        return nil
    }

    func fallbackPlan(rawInput: String) -> RouterPlan {
        let normalizedInput = rawInput.lowercased()
        return RouterPlan(
            capability: "log.event",
            parameters: [
                "text": .string(rawInput),
                "tags": .array(extractTags(from: normalizedInput).map(JSONValue.string)),
                "normalized_intent": .string("log.event"),
            ],
            confidence: 0.61,
            title: "Log Event"
        )
    }

    private func parameters(for capability: CapabilityID, rawInput: String) -> [String: JSONValue] {
        switch capability.rawValue {
        case "task.create", "task.complete":
            ["title": .string(rawInput)]
        case "shortcut.run":
            ["name": .string(rawInput)]
        case "url.open":
            ["url": .string(inferURL(from: rawInput))]
        case "note.create":
            [
                "title": .string(inferTitle(from: rawInput)),
                "body": .string(rawInput),
            ]
        case "calendar.event.create":
            ["title": .string(rawInput)]
        default:
            [
                "text": .string(rawInput),
                "tags": .array(extractTags(from: rawInput.lowercased()).map(JSONValue.string)),
                "normalized_intent": .string(capability.rawValue),
            ]
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

    private func routingHints(
        for capability: CapabilityID,
        normalizedInput: String
    ) -> RoutingHints? {
        guard capability == "task.create" || capability == "task.complete" else {
            return nil
        }

        let groceryKeywords = [
            "milk", "eggs", "bread", "groceries", "grocery", "shopping", "supermarket",
            "cheese", "fruit", "vegetables", "banana", "bananas", "coffee",
        ]
        if groceryKeywords.contains(where: normalizedInput.contains) {
            return RoutingHints(domain: "grocery", listHint: "groceries", audience: "shared")
        }

        let workKeywords = [
            "work", "client", "meeting", "report", "deck", "invoice", "follow up", "email",
            "slack", "jira", "roadmap",
        ]
        if workKeywords.contains(where: normalizedInput.contains) {
            return RoutingHints(domain: "work", listHint: "work", audience: "personal")
        }

        let personalKeywords = [
            "mom", "dad", "family", "doctor", "home", "personal", "gym",
        ]
        if personalKeywords.contains(where: normalizedInput.contains) {
            return RoutingHints(domain: "personal", listHint: "personal", audience: "personal")
        }

        return nil
    }

    private func suffix(
        afterAnyOf prefixes: [String],
        in normalized: String,
        original: String
    ) -> String? {
        for prefix in prefixes where normalized.hasPrefix(prefix) {
            let start = original.index(original.startIndex, offsetBy: prefix.count)
            let value = String(original[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty == false {
                return value
            }
        }
        return nil
    }

    private func inferTitle(from input: String) -> String {
        input.split(separator: " ").prefix(5).joined(separator: " ")
    }

    private func inferURL(from input: String) -> String {
        if input.contains("://") {
            return input
        }
        if input.contains(".") {
            return "https://\(input)"
        }
        return input
    }

    private func extractTags(from input: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "and", "for", "with", "into", "from", "that", "this",
            "have", "just", "need", "will", "your", "about",
        ]
        return Array(
            Set(
                input
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .map { $0.lowercased() }
                    .filter { $0.count > 2 && stopWords.contains($0) == false }
                    .prefix(4)
            )
        ).sorted()
    }
}
