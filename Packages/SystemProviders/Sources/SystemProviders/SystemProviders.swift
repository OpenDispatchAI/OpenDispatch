import CapabilityRegistry
import Executors
import Foundation
import RouterCore

#if canImport(EventKit)
import EventKit
#endif

#if canImport(UIKit)
import UIKit
#endif

public protocol ReminderStore: Sendable {
    func createTask(title: String, notes: String?, dueDate: Date?) async throws -> String
    func completeTask(title: String) async throws -> Bool
}

public protocol CalendarStore: Sendable {
    func createEvent(title: String, start: Date?, end: Date?, notes: String?) async throws -> String
}

public protocol ClipboardWriting: Sendable {
    func copy(_ text: String) async
}

public struct LocalLogProvider: DispatchProvider {
    public let descriptor = ProviderDescriptor(
        id: "local_log",
        displayName: "Local Log",
        kind: .system,
        priority: 100,
        capabilities: ["log.event"]
    )
    public let confirmationBehavior: ConfirmationBehavior = .never

    private let executor: LocalLogExecutor

    public init(sink: any LocalLogSink) {
        executor = LocalLogExecutor(sink: sink)
    }

    public func validate(plan: RouterPlan) throws {
        if plan.parameters["text"]?.stringValue?.isEmpty != false {
            throw RouterError.providerValidationFailed(descriptor.id)
        }
    }

    public func execute(plan: RouterPlan, mode: ExecutionMode) async -> ExecutionResult {
        await executor.execute(
            rawInput: plan.parameters["text"]?.stringValue ?? "",
            parameters: plan.parameters,
            mode: mode
        )
    }
}

public struct RemindersProvider: DispatchProvider {
    public let descriptor = ProviderDescriptor(
        id: "apple_reminders",
        displayName: "Apple Reminders",
        kind: .system,
        priority: 90,
        capabilities: ["task.create", "task.complete"]
    )
    public let confirmationBehavior: ConfirmationBehavior = .destructiveOnly

    private let reminderStore: any ReminderStore

    public init(reminderStore: any ReminderStore) {
        self.reminderStore = reminderStore
    }

    public func validate(plan: RouterPlan) throws {
        if plan.parameters["title"]?.stringValue?.isEmpty != false {
            throw RouterError.providerValidationFailed(descriptor.id)
        }
        if let dueDate = plan.parameters["due_date"]?.stringValue,
           parseISO8601Date(dueDate) == nil {
            throw RouterError.providerValidationFailed(descriptor.id)
        }
    }

    public func execute(plan: RouterPlan, mode: ExecutionMode) async -> ExecutionResult {
        let title = plan.parameters["title"]?.stringValue ?? ""
        let dueDate = parseISO8601Date(plan.parameters["due_date"]?.stringValue)

        if mode == .dryRun {
            var metadata: [String: JSONValue] = [
                "status": .string("dry_run"),
                "title": .string(title),
            ]
            if let dueDateString = plan.parameters["due_date"]?.stringValue {
                metadata["due_date"] = .string(dueDateString)
            }
            return .success(metadata: metadata, toolCall: ToolCall(executorID: "eventkit_reminders", payload: plan.parameters))
        }

        do {
            switch plan.capability.rawValue {
            case "task.create":
                let identifier = try await reminderStore.createTask(
                    title: title,
                    notes: plan.parameters["notes"]?.stringValue,
                    dueDate: dueDate
                )
                var metadata: [String: JSONValue] = [
                    "status": .string("created"),
                    "identifier": .string(identifier),
                ]
                if let dueDateString = plan.parameters["due_date"]?.stringValue {
                    metadata["due_date"] = .string(dueDateString)
                }
                return .success(metadata: metadata, toolCall: ToolCall(executorID: "eventkit_reminders", payload: plan.parameters))
            case "task.complete":
                let completed = try await reminderStore.completeTask(title: title)
                return completed
                    ? .success(
                        metadata: ["status": .string("completed")],
                        toolCall: ToolCall(executorID: "eventkit_reminders", payload: plan.parameters)
                    )
                    : .failure(
                        "Reminder not found.",
                        toolCall: ToolCall(executorID: "eventkit_reminders", payload: plan.parameters)
                    )
            default:
                return .failure("Unsupported reminders capability.")
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func parseISO8601Date(_ value: String?) -> Date? {
        guard let value, value.isEmpty == false else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

public struct CalendarProvider: DispatchProvider {
    public let descriptor = ProviderDescriptor(
        id: "apple_calendar",
        displayName: "Apple Calendar",
        kind: .system,
        priority: 80,
        capabilities: ["calendar.event.create"]
    )
    public let confirmationBehavior: ConfirmationBehavior = .never

    private let calendarStore: any CalendarStore

    public init(calendarStore: any CalendarStore) {
        self.calendarStore = calendarStore
    }

    public func validate(plan: RouterPlan) throws {
        if plan.parameters["title"]?.stringValue?.isEmpty != false {
            throw RouterError.providerValidationFailed(descriptor.id)
        }
    }

    public func execute(plan: RouterPlan, mode: ExecutionMode) async -> ExecutionResult {
        if mode == .dryRun {
            return .success(
                metadata: [
                    "status": .string("dry_run"),
                    "title": .string(plan.parameters["title"]?.stringValue ?? ""),
                ],
                toolCall: ToolCall(executorID: "eventkit_calendar", payload: plan.parameters)
            )
        }

        let formatter = ISO8601DateFormatter()
        let start = plan.parameters["start_date"]?.stringValue.flatMap(formatter.date(from:))
        let end = plan.parameters["end_date"]?.stringValue.flatMap(formatter.date(from:))

        do {
            let identifier = try await calendarStore.createEvent(
                title: plan.parameters["title"]?.stringValue ?? "",
                start: start,
                end: end,
                notes: plan.parameters["notes"]?.stringValue
            )
            return .success(
                metadata: [
                    "status": .string("created"),
                    "identifier": .string(identifier),
                ],
                toolCall: ToolCall(executorID: "eventkit_calendar", payload: plan.parameters)
            )
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

public struct ShortcutsProvider: DispatchProvider {
    public let descriptor = ProviderDescriptor(
        id: "apple_shortcuts",
        displayName: "Apple Shortcuts",
        kind: .system,
        priority: 70,
        capabilities: ["shortcut.run"]
    )
    public let confirmationBehavior: ConfirmationBehavior = .always

    private let executor: ShortcutsExecutor

    public init(urlHandler: any URLHandling) {
        executor = ShortcutsExecutor(urlHandler: urlHandler)
    }

    public func validate(plan: RouterPlan) throws {
        if plan.parameters["name"]?.stringValue?.isEmpty != false {
            throw RouterError.providerValidationFailed(descriptor.id)
        }
    }

    public func execute(plan: RouterPlan, mode: ExecutionMode) async -> ExecutionResult {
        await executor.execute(
            shortcutName: plan.parameters["name"]?.stringValue ?? "",
            parameters: plan.parameters,
            mode: mode
        )
    }
}

public struct NotesProvider: DispatchProvider {
    public let descriptor = ProviderDescriptor(
        id: "apple_notes",
        displayName: "Apple Notes",
        kind: .system,
        priority: 60,
        capabilities: ["note.create"]
    )
    public let confirmationBehavior: ConfirmationBehavior = .always

    private let clipboard: any ClipboardWriting
    private let urlHandler: any URLHandling

    public init(
        clipboard: any ClipboardWriting,
        urlHandler: any URLHandling
    ) {
        self.clipboard = clipboard
        self.urlHandler = urlHandler
    }

    public func validate(plan: RouterPlan) throws {
        if plan.parameters["body"]?.stringValue?.isEmpty != false {
            throw RouterError.providerValidationFailed(descriptor.id)
        }
    }

    public func execute(plan: RouterPlan, mode: ExecutionMode) async -> ExecutionResult {
        let body = plan.parameters["body"]?.stringValue ?? ""
        let url = URL(string: "notes://")!

        if mode == .dryRun {
            return .success(
                metadata: [
                    "status": .string("dry_run"),
                    "url": .string(url.absoluteString),
                    "body_preview": .string(body),
                ],
                toolCall: ToolCall(executorID: "apple_notes_bridge", payload: plan.parameters)
            )
        }

        await clipboard.copy(body)
        guard await urlHandler.canOpen(url) else {
            return .failure("Notes app cannot be opened.")
        }

        let didOpen = await urlHandler.open(url)
        return didOpen
            ? .success(
                metadata: [
                    "status": .string("opened"),
                    "clipboard": .string("body"),
                    "url": .string(url.absoluteString),
                ],
                toolCall: ToolCall(executorID: "apple_notes_bridge", payload: plan.parameters)
            )
            : .failure("Unable to open Notes.")
    }
}

public enum SystemProviderFactory {
    public static func defaultProviders(
        urlHandler: any URLHandling,
        logSink: any LocalLogSink,
        clipboard: any ClipboardWriting = SystemClipboard(),
        reminderStore: any ReminderStore = EventKitReminderStore(),
        calendarStore: any CalendarStore = EventKitCalendarStore()
    ) -> [any DispatchProvider] {
        [
            LocalLogProvider(sink: logSink),
            RemindersProvider(reminderStore: reminderStore),
            CalendarProvider(calendarStore: calendarStore),
            NotesProvider(clipboard: clipboard, urlHandler: urlHandler),
            ShortcutsProvider(urlHandler: urlHandler),
        ]
    }

    public static func register(
        providers: [any DispatchProvider],
        into registry: inout CapabilityRegistry
    ) throws {
        for provider in providers {
            try registry.registerProvider(provider.descriptor)
        }
    }
}

public actor SystemClipboard: ClipboardWriting {
    public init() {}

    public func copy(_ text: String) async {
        #if canImport(UIKit)
        await MainActor.run {
            UIPasteboard.general.string = text
        }
        #endif
    }
}

#if canImport(EventKit)
public actor EventKitReminderStore: ReminderStore {
    private let eventStore = EKEventStore()

    public init() {}

    public func createTask(title: String, notes: String?, dueDate: Date?) async throws -> String {
        try await requestAccess()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        if let dueDate {
            reminder.dueDateComponents = Calendar.autoupdatingCurrent.dateComponents(
                [.year, .month, .day, .hour, .minute, .second, .timeZone],
                from: dueDate
            )
        }
        try eventStore.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    public func completeTask(title: String) async throws -> Bool {
        try await requestAccess()
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )
        let reminderIdentifier: String? = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let match = reminders?.first {
                    $0.title.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }
                continuation.resume(returning: match?.calendarItemIdentifier)
            }
        }

        guard let reminderIdentifier,
              let reminder = eventStore.calendarItem(withIdentifier: reminderIdentifier) as? EKReminder else {
            return false
        }

        reminder.isCompleted = true
        reminder.completionDate = Date()
        try eventStore.save(reminder, commit: true)
        return true
    }

    private func requestAccess() async throws {
        _ = try await eventStore.requestFullAccessToReminders()
    }
}

public actor EventKitCalendarStore: CalendarStore {
    private let eventStore = EKEventStore()

    public init() {}

    public func createEvent(title: String, start: Date?, end: Date?, notes: String?) async throws -> String {
        try await requestAccess()
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.notes = notes
        event.calendar = eventStore.defaultCalendarForNewEvents
        event.startDate = start ?? Date().addingTimeInterval(300)
        event.endDate = end ?? event.startDate.addingTimeInterval(3600)
        try eventStore.save(event, span: .thisEvent)
        return event.eventIdentifier
    }

    private func requestAccess() async throws {
        _ = try await eventStore.requestFullAccessToEvents()
    }
}
#else
public actor EventKitReminderStore: ReminderStore {
    public init() {}

    public func createTask(title: String, notes: String?, dueDate: Date?) async throws -> String {
        throw ModelUnavailableError()
    }

    public func completeTask(title: String) async throws -> Bool {
        throw ModelUnavailableError()
    }
}

public actor EventKitCalendarStore: CalendarStore {
    public init() {}

    public func createEvent(title: String, start: Date?, end: Date?, notes: String?) async throws -> String {
        throw ModelUnavailableError()
    }
}

private struct ModelUnavailableError: LocalizedError {
    var errorDescription: String? {
        "EventKit is unavailable on this platform."
    }
}
#endif
