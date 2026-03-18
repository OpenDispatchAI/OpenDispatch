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
    private let translationService: TranslationService

    public init(
        languages: [String],
        embeddingService: EmbeddingService,
        translationService: TranslationService = TranslationService()
    ) {
        self.languages = languages
        self.embeddingService = embeddingService
        self.translationService = translationService
    }

    /// Compile one or more YAML skill manifests into a CompiledIndex.
    /// Translates examples to configured languages if needed, then embeds all.
    public func compile(manifests: [YAMLSkillManifest]) async throws -> CompiledIndex {
        guard languages.isEmpty == false else {
            throw SkillCompilerError.noLanguagesConfigured
        }

        var entries: [CompiledEntry] = []

        for manifest in manifests {
            for action in manifest.actions {
                let actionEntries = await compileAction(
                    action: action,
                    skillID: manifest.skillID,
                    skillName: manifest.name
                )
                entries.append(contentsOf: actionEntries)
            }
        }

        return CompiledIndex(entries: entries)
    }

    private func compileAction(
        action: YAMLSkillAction,
        skillID: String,
        skillName: String
    ) async -> [CompiledEntry] {
        var entries: [CompiledEntry] = []

        // Detect source language of examples
        let sampleText = action.examples.prefix(3).joined(separator: " ")
        let sourceLanguage = translationService.detectLanguage(of: sampleText) ?? "en"

        // Build texts to embed per language
        // Build context for translation: "Unlock — Unlock the car doors so you can get in"
        let translationContext = [action.title, action.description]
            .compactMap { $0 }
            .joined(separator: " — ")

        for language in languages {
            // Positive examples
            var textsToEmbed: [String]
            if language == sourceLanguage {
                textsToEmbed = action.examples
            } else {
                textsToEmbed = await translationService.translate(
                    examples: action.examples,
                    fromLanguage: sourceLanguage,
                    toLanguage: language,
                    context: translationContext
                )
            }

            // Also embed description if present
            if let description = action.description, description.isEmpty == false {
                if language == sourceLanguage {
                    textsToEmbed.append(description)
                } else {
                    let translated = await translationService.translate(
                        examples: [description],
                        fromLanguage: sourceLanguage,
                        toLanguage: language,
                        context: translationContext
                    )
                    textsToEmbed.append(translated.first ?? description)
                }
            }

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

            // Negative examples
            var negativeTexts: [String]
            if language == sourceLanguage {
                negativeTexts = action.negativeExamples
            } else if action.negativeExamples.isEmpty == false {
                negativeTexts = await translationService.translate(
                    examples: action.negativeExamples,
                    fromLanguage: sourceLanguage,
                    toLanguage: language,
                    context: translationContext
                )
            } else {
                negativeTexts = []
            }

            for text in negativeTexts {
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
                    language: language,
                    isNegative: true
                ))
            }
        }

        return entries
    }
}
