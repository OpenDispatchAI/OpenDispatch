import Foundation

public struct SkillInfo: Codable, Hashable, Sendable {
    public let skillID: String
    public let name: String
    public let version: String
    public let description: String
    public let author: String
    public let authorURL: String?
    public let tags: [String]
    public let languages: [String]
    public let requiresBridgeShortcut: Bool
    public let bridgeShortcut: String?
    public let bridgeShortcutShareURL: String?
    public let actions: [SkillInfoAction]
    public let createdAt: String
    public let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case skillID = "skill_id"
        case name
        case version
        case description
        case author
        case authorURL = "author_url"
        case tags
        case languages
        case requiresBridgeShortcut = "requires_bridge_shortcut"
        case bridgeShortcut = "bridge_shortcut"
        case bridgeShortcutShareURL = "bridge_shortcut_share_url"
        case actions
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct SkillInfoAction: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let exampleCount: Int
    public let hasParameters: Bool
    public let confirmation: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case exampleCount = "example_count"
        case hasParameters = "has_parameters"
        case confirmation
    }
}
