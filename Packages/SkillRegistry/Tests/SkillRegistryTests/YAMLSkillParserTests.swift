import Foundation
import Testing
@testable import SkillRegistry

@Suite("YAML Skill Parser")
struct YAMLSkillParserTests {

    static let teslaYAML = """
    skill_id: tesla
    name: Tesla
    version: 1.0.0
    bridge_shortcut: "OpenDispatch - Tesla v1"
    bridge_shortcut_share_url: https://icloud.com/abc123

    actions:
      - id: vehicle.unlock
        title: "Unlock"
        description: "Unlock your Tesla vehicle"
        shortcut_arguments:
          action: unlock
        examples:
          - unlock my car
          - unlock the tesla
      - id: vehicle.lock
        title: "Lock"
        description: "Lock your Tesla vehicle"
        shortcut_arguments:
          action: lock
        examples:
          - lock my car
          - lock the tesla
    """

    static let remindersYAML = """
    skill_id: apple_reminders
    name: Apple Reminders
    version: 1.0.0
    built_in: true

    actions:
      - id: task.create
        title: "Create Task"
        description: "Create a new reminder"
        parameters:
          - name: title
            type: string
            required: true
          - name: due_date
            type: date
            required: false
        examples:
          - add milk
          - remind me to call mom
    """

    @Test("Parses external skill with bridge shortcut")
    func parseExternalSkill() throws {
        let manifest = try YAMLSkillParser.parse(Self.teslaYAML)
        #expect(manifest.skillID == "tesla")
        #expect(manifest.name == "Tesla")
        #expect(manifest.version == "1.0.0")
        #expect(manifest.bridgeShortcut == "OpenDispatch - Tesla v1")
        #expect(manifest.bridgeShortcutShareURL == "https://icloud.com/abc123")
        #expect(manifest.builtIn == false)
        #expect(manifest.actions.count == 2)
        #expect(manifest.actions[0].id == "vehicle.unlock")
        #expect(manifest.actions[0].title == "Unlock")
        #expect(manifest.actions[0].description == "Unlock your Tesla vehicle")
        #expect(manifest.actions[0].examples.count == 2)
        #expect(manifest.actions[0].shortcutArguments?["action"]?.stringValue == "unlock")
        #expect(manifest.actions[1].id == "vehicle.lock")
    }

    @Test("Parses built-in skill with parameters")
    func parseBuiltInSkill() throws {
        let manifest = try YAMLSkillParser.parse(Self.remindersYAML)
        #expect(manifest.skillID == "apple_reminders")
        #expect(manifest.builtIn == true)
        #expect(manifest.bridgeShortcut == nil)
        #expect(manifest.actions[0].parameters?.count == 2)
        #expect(manifest.actions[0].parameters?[0].name == "title")
        #expect(manifest.actions[0].parameters?[0].required == true)
        #expect(manifest.actions[0].parameters?[1].name == "due_date")
        #expect(manifest.actions[0].parameters?[1].required == false)
    }

    @Test("Parameterless actions don't require extraction")
    func parameterlessActions() throws {
        let manifest = try YAMLSkillParser.parse(Self.teslaYAML)
        #expect(manifest.actions[0].requiresParameterExtraction == false)
    }

    @Test("Actions with parameters require extraction")
    func actionsWithParameters() throws {
        let manifest = try YAMLSkillParser.parse(Self.remindersYAML)
        #expect(manifest.actions[0].requiresParameterExtraction == true)
    }

    @Test("Rejects YAML missing skill_id")
    func rejectsMissingSkillID() {
        let yaml = """
        name: Bad Skill
        version: 1.0.0
        actions:
          - id: something
            title: Something
            examples:
              - do something
        """
        #expect(throws: YAMLSkillParserError.self) {
            try YAMLSkillParser.parse(yaml)
        }
    }

    @Test("Rejects YAML with empty actions")
    func rejectsEmptyActions() {
        let yaml = """
        skill_id: empty
        name: Empty
        version: 1.0.0
        actions: []
        """
        #expect(throws: YAMLSkillParserError.self) {
            try YAMLSkillParser.parse(yaml)
        }
    }

    @Test("Rejects action with no examples")
    func rejectsActionNoExamples() {
        let yaml = """
        skill_id: bad
        name: Bad
        version: 1.0.0
        actions:
          - id: something
            title: Something
            description: Does something
            examples: []
        """
        #expect(throws: YAMLSkillParserError.self) {
            try YAMLSkillParser.parse(yaml)
        }
    }

    @Test("Defaults name to skill_id when missing")
    func defaultsNameToSkillID() throws {
        let yaml = """
        skill_id: my_skill
        version: 1.0.0
        actions:
          - id: do.thing
            title: Thing
            examples:
              - do the thing
        """
        let manifest = try YAMLSkillParser.parse(yaml)
        #expect(manifest.name == "my_skill")
    }
}
