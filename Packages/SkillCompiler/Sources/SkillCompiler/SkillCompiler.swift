import Foundation
import RouterCore
import SkillRegistry

public enum SkillCompilerError: Error, Sendable {
    case noLanguagesConfigured
    case noSupportedLanguages([String])
}

public struct SkillCompiler: Sendable {
    public let languages: [String]
    private let embeddingService: EmbeddingService

    public init(languages: [String], embeddingService: EmbeddingService = EmbeddingService()) {
        self.languages = languages
        self.embeddingService = embeddingService
    }

    /// Compile one or more YAML skill manifests into a CompiledIndex.
    /// Each example in each action gets embedded per supported language.
    public func compile(manifests: [YAMLSkillManifest]) throws -> CompiledIndex {
        guard languages.isEmpty == false else {
            throw SkillCompilerError.noLanguagesConfigured
        }

        // Filter to languages that actually have NLEmbedding support
        let supported = embeddingService.supportedLanguages()
        let activeLanguages = languages.filter { supported.contains($0) }
        guard activeLanguages.isEmpty == false else {
            throw SkillCompilerError.noSupportedLanguages(languages)
        }

        var entries: [CompiledEntry] = []

        for manifest in manifests {
            for action in manifest.actions {
                let actionEntries = compileAction(
                    action: action,
                    skillID: manifest.skillID,
                    skillName: manifest.name,
                    languages: activeLanguages
                )
                entries.append(contentsOf: actionEntries)
            }
        }

        return CompiledIndex(entries: entries)
    }

    private func compileAction(
        action: YAMLSkillAction,
        skillID: String,
        skillName: String,
        languages: [String]
    ) -> [CompiledEntry] {
        var entries: [CompiledEntry] = []

        // Collect all texts to embed: examples + description (if present)
        var textsToEmbed = action.examples
        if let description = action.description, description.isEmpty == false {
            textsToEmbed.append(description)
        }

        for language in languages {
            for text in textsToEmbed {
                guard let vector = embeddingService.embed(text, language: language) else {
                    continue
                }
                entries.append(CompiledEntry(
                    embedding: vector,
                    skillID: skillID,
                    skillName: skillName,
                    actionID: action.id,
                    actionTitle: action.title,
                    capability: .init(rawValue: action.id),
                    parameters: action.parameters,
                    shortcutArguments: action.shortcutArguments,
                    originalExample: text,
                    language: language
                ))
            }
        }

        return entries
    }
}
