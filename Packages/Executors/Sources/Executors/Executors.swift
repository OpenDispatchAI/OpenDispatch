import Foundation
import RouterCore

public enum ExecutorKind: String, Hashable, Codable, CaseIterable, Sendable {
    case localLog = "local_log"
    case shortcuts = "shortcuts"
    case urlScheme = "url_scheme"
}

public struct LocalLogEntry: Hashable, Codable, Sendable {
    public let timestamp: Date
    public let rawInput: String
    public let tags: [String]
    public let normalizedIntent: String

    public init(
        timestamp: Date = Date(),
        rawInput: String,
        tags: [String],
        normalizedIntent: String
    ) {
        self.timestamp = timestamp
        self.rawInput = rawInput
        self.tags = tags
        self.normalizedIntent = normalizedIntent
    }
}

public protocol LocalLogSink: Sendable {
    func append(_ entry: LocalLogEntry) async throws
}

public actor InMemoryLocalLogSink: LocalLogSink {
    private(set) var entries: [LocalLogEntry] = []

    public init() {}

    public func append(_ entry: LocalLogEntry) async throws {
        entries.append(entry)
    }
}

public protocol URLHandling: Sendable {
    func canOpen(_ url: URL) async -> Bool
    func open(_ url: URL) async -> Bool
}

public struct NoOpURLHandler: URLHandling {
    private let canOpenURLs: Bool
    private let openResult: Bool

    public init(canOpenURLs: Bool = true, openResult: Bool = true) {
        self.canOpenURLs = canOpenURLs
        self.openResult = openResult
    }

    public func canOpen(_ url: URL) async -> Bool {
        canOpenURLs
    }

    public func open(_ url: URL) async -> Bool {
        openResult
    }
}

public struct LocalLogExecutor: Sendable {
    private let sink: any LocalLogSink

    public init(sink: any LocalLogSink) {
        self.sink = sink
    }

    public func execute(
        rawInput: String,
        parameters: [String: JSONValue],
        mode: ExecutionMode
    ) async -> ExecutionResult {
        let tags = parameters["tags"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let intent = parameters["normalized_intent"]?.stringValue ?? "log.event"
        let entry = LocalLogEntry(rawInput: rawInput, tags: tags, normalizedIntent: intent)

        if mode == .dryRun {
            return .success(
                metadata: [
                    "status": .string("dry_run"),
                    "normalized_intent": .string(intent),
                ],
                toolCall: ToolCall(
                    executorID: ExecutorKind.localLog.rawValue,
                    payload: parameters
                )
            )
        }

        do {
            try await sink.append(entry)
            return .success(
                metadata: [
                    "status": .string("logged"),
                    "normalized_intent": .string(intent),
                ],
                toolCall: ToolCall(
                    executorID: ExecutorKind.localLog.rawValue,
                    payload: parameters
                )
            )
        } catch {
            return .failure(
                error.localizedDescription,
                toolCall: ToolCall(
                    executorID: ExecutorKind.localLog.rawValue,
                    payload: parameters
                )
            )
        }
    }
}

public struct ShortcutsExecutor: Sendable {
    private let urlHandler: any URLHandling

    public init(urlHandler: any URLHandling) {
        self.urlHandler = urlHandler
    }

    public func execute(
        shortcutName: String,
        parameters: [String: JSONValue],
        mode: ExecutionMode
    ) async -> ExecutionResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payloadString: String
        do {
            payloadString = String(
                decoding: try encoder.encode(parameters),
                as: UTF8.self
            )
        } catch {
            return .failure(error.localizedDescription)
        }

        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [
            URLQueryItem(name: "name", value: shortcutName),
            URLQueryItem(name: "input", value: "text"),
            URLQueryItem(name: "text", value: payloadString),
        ]

        guard let url = components.url else {
            return .failure("Unable to build Shortcuts URL.")
        }

        let toolCall = ToolCall(
            executorID: ExecutorKind.shortcuts.rawValue,
            payload: [
                "shortcut_name": .string(shortcutName),
                "url": .string(url.absoluteString),
            ]
        )

        if mode == .dryRun {
            return .success(
                metadata: [
                    "status": .string("dry_run"),
                    "shortcut_name": .string(shortcutName),
                    "url": .string(url.absoluteString),
                ],
                toolCall: toolCall
            )
        }

        let didOpen = await urlHandler.open(url)
        return didOpen
            ? .success(
                metadata: [
                    "status": .string("opened"),
                    "shortcut_name": .string(shortcutName),
                    "url": .string(url.absoluteString),
                ],
                toolCall: toolCall
            )
            : .failure(
                "Shortcuts execution failed.",
                metadata: [
                    "shortcut_name": .string(shortcutName),
                    "url": .string(url.absoluteString),
                ],
                toolCall: toolCall
            )
    }
}

public struct URLSchemeExecutor: Sendable {
    private let urlHandler: any URLHandling

    public init(urlHandler: any URLHandling) {
        self.urlHandler = urlHandler
    }

    public func execute(
        urlTemplate: String,
        parameters: [String: JSONValue],
        mode: ExecutionMode
    ) async -> ExecutionResult {
        let renderedURL = TemplateURLRenderer.render(template: urlTemplate, parameters: parameters)
        guard let url = URL(string: renderedURL) else {
            return .failure(
                "Unable to render URL template.",
                metadata: ["template": .string(urlTemplate)]
            )
        }

        let toolCall = ToolCall(
            executorID: ExecutorKind.urlScheme.rawValue,
            payload: [
                "url": .string(url.absoluteString),
            ]
        )

        if mode == .dryRun {
            return .success(
                metadata: [
                    "status": .string("dry_run"),
                    "url": .string(url.absoluteString),
                ],
                toolCall: toolCall
            )
        }

        guard await urlHandler.canOpen(url) else {
            return .failure(
                "URL scheme cannot be opened.",
                metadata: ["url": .string(url.absoluteString)],
                toolCall: toolCall
            )
        }

        let didOpen = await urlHandler.open(url)
        return didOpen
            ? .success(
                metadata: [
                    "status": .string("opened"),
                    "url": .string(url.absoluteString),
                ],
                toolCall: toolCall
            )
            : .failure(
                "URL scheme execution failed.",
                metadata: ["url": .string(url.absoluteString)],
                toolCall: toolCall
            )
    }
}

public enum TemplateURLRenderer {
    public static func render(
        template: String,
        parameters: [String: JSONValue]
    ) -> String {
        parameters.reduce(template) { partial, entry in
            let value = entry.value.stringValue ?? ""
            let encoded = encode(value)
            return partial.replacingOccurrences(of: "{{\(entry.key)}}", with: encoded)
        }
    }

    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?#+")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private extension JSONValue {
    var arrayValue: [JSONValue]? {
        if case let .array(value) = self {
            value
        } else {
            nil
        }
    }
}
