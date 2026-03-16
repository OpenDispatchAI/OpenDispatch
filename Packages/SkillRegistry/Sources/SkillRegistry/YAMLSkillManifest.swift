import Foundation
import RouterCore

public struct YAMLSkillManifest: Hashable, Codable, Sendable {
    public let skillID: String
    public let name: String
    public let version: String
    public let builtIn: Bool
    public let bridgeShortcut: String?
    public let bridgeShortcutShareURL: String?
    public let actions: [YAMLSkillAction]

    public init(
        skillID: String,
        name: String,
        version: String,
        builtIn: Bool = false,
        bridgeShortcut: String? = nil,
        bridgeShortcutShareURL: String? = nil,
        actions: [YAMLSkillAction]
    ) {
        self.skillID = skillID
        self.name = name
        self.version = version
        self.builtIn = builtIn
        self.bridgeShortcut = bridgeShortcut
        self.bridgeShortcutShareURL = bridgeShortcutShareURL
        self.actions = actions
    }
}

public enum YAMLConfirmation: String, Hashable, Codable, Sendable {
    /// Always ask for confirmation before executing (default for destructive/irreversible actions)
    case required
    /// Never ask for confirmation
    case none
    /// Ask for confirmation only if the action is marked destructive in the capability registry
    case destructiveOnly = "destructive_only"
}

public struct YAMLSkillAction: Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let description: String?
    public let shortcutArguments: [String: JSONValue]?
    public let parameters: [ParameterSchema]?
    public let examples: [String]
    public let confirmation: YAMLConfirmation?

    public init(
        id: String,
        title: String,
        description: String? = nil,
        shortcutArguments: [String: JSONValue]? = nil,
        parameters: [ParameterSchema]? = nil,
        examples: [String],
        confirmation: YAMLConfirmation? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.shortcutArguments = shortcutArguments
        self.parameters = parameters
        self.examples = examples
        self.confirmation = confirmation
    }

    public var requiresParameterExtraction: Bool {
        guard let params = parameters else { return false }
        return params.isEmpty == false
    }
}
