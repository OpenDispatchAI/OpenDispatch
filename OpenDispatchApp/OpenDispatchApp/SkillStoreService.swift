import Foundation
import SkillRegistry

struct SkillStoreService: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchSkillInfo(skillID: String, baseURL: URL) async throws -> SkillInfo {
        let url = baseURL.appending(path: "skills/\(skillID)/info.json")
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(SkillInfo.self, from: data)
    }

    func downloadSkillYAML(from url: URL) async throws -> String {
        let (data, _) = try await session.data(from: url)
        guard let yaml = String(data: data, encoding: .utf8) else {
            throw SkillStoreError.invalidYAMLData
        }
        return yaml
    }

    func installSkill(yaml: String, skillID: String) throws -> URL {
        let dir = try installedSkillsDirectory().appending(path: skillID, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appending(path: "skill.yaml")
        try yaml.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func uninstallSkill(skillID: String) throws {
        let dir = try installedSkillsDirectory().appending(path: skillID, directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: dir.path()) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    func installedSkillsDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appending(path: "OpenDispatch/InstalledSkills", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func baseURL(from repositoryLocation: String) -> URL? {
        guard let url = URL(string: repositoryLocation) else { return nil }
        return url.deletingLastPathComponent()
    }
}

enum SkillStoreError: Error, LocalizedError {
    case invalidYAMLData

    var errorDescription: String? {
        switch self {
        case .invalidYAMLData:
            return "Downloaded skill data is not valid UTF-8."
        }
    }
}
