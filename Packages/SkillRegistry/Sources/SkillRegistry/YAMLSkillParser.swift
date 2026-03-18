import Foundation
import RouterCore
import Yams

public enum YAMLSkillParserError: Error, Sendable {
    case invalidYAML(String)
    case missingField(String)
    case emptyActions
    case actionMissingExamples(String)
}

public enum YAMLSkillParser {

    public static func parse(_ yamlString: String) throws -> YAMLSkillManifest {
        guard let yaml = try Yams.load(yaml: yamlString) as? [String: Any] else {
            throw YAMLSkillParserError.invalidYAML("Could not parse YAML as dictionary")
        }

        guard let skillID = yaml["skill_id"] as? String, skillID.isEmpty == false else {
            throw YAMLSkillParserError.missingField("skill_id")
        }
        let name = yaml["name"] as? String ?? skillID
        let version = yaml["version"] as? String ?? "0.0.0"
        let builtIn = yaml["built_in"] as? Bool ?? false
        let bridgeShortcut = yaml["bridge_shortcut"] as? String
        let bridgeShortcutShareURL = yaml["bridge_shortcut_share_url"] as? String

        guard let actionsRaw = yaml["actions"] as? [[String: Any]], actionsRaw.isEmpty == false else {
            throw YAMLSkillParserError.emptyActions
        }

        let actions = try actionsRaw.map { try parseAction($0) }

        return YAMLSkillManifest(
            skillID: skillID,
            name: name,
            version: version,
            builtIn: builtIn,
            bridgeShortcut: bridgeShortcut,
            bridgeShortcutShareURL: bridgeShortcutShareURL,
            actions: actions
        )
    }

    public static func parse(contentsOf url: URL) throws -> YAMLSkillManifest {
        let yamlString = try String(contentsOf: url, encoding: .utf8)
        return try parse(yamlString)
    }

    private static func parseAction(_ dict: [String: Any]) throws -> YAMLSkillAction {
        guard let id = dict["id"] as? String else {
            throw YAMLSkillParserError.missingField("action.id")
        }
        let title = dict["title"] as? String ?? id
        let description = dict["description"] as? String

        let examples = dict["examples"] as? [String] ?? []
        guard examples.isEmpty == false else {
            throw YAMLSkillParserError.actionMissingExamples(id)
        }

        let shortcutArguments = (dict["shortcut_arguments"] as? [String: Any])
            .map { convertToJSONValues($0) }

        let parameters = (dict["parameters"] as? [[String: Any]])
            .map { $0.map { parseParameter($0) } }

        let negativeExamples = dict["negative_examples"] as? [String] ?? []

        let confirmation = (dict["confirmation"] as? String)
            .flatMap { YAMLConfirmation(rawValue: $0) }

        return YAMLSkillAction(
            id: id,
            title: title,
            description: description,
            shortcutArguments: shortcutArguments,
            parameters: parameters,
            examples: examples,
            negativeExamples: negativeExamples,
            confirmation: confirmation
        )
    }

    private static func parseParameter(_ dict: [String: Any]) -> ParameterSchema {
        ParameterSchema(
            name: dict["name"] as? String ?? "",
            type: dict["type"] as? String ?? "string",
            description: dict["description"] as? String,
            required: dict["required"] as? Bool ?? true
        )
    }

    private static func convertToJSONValues(_ dict: [String: Any]) -> [String: JSONValue] {
        dict.compactMapValues { value in
            switch value {
            case let s as String: .string(s)
            case let i as Int: .integer(i)
            case let d as Double: .number(d)
            case let b as Bool: .bool(b)
            default: .string(String(describing: value))
            }
        }
    }
}
