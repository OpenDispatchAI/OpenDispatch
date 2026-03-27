import Foundation
import RouterCore
import SkillRegistry

/// Lightweight representation of a user-added example, decoupled from SwiftData.
public struct UserExample: Sendable {
    public let skillID: String
    public let actionID: String
    public let skillName: String
    public let actionTitle: String
    public let text: String
    public let isNegative: Bool

    public init(skillID: String, actionID: String, skillName: String, actionTitle: String, text: String, isNegative: Bool) {
        self.skillID = skillID
        self.actionID = actionID
        self.skillName = skillName
        self.actionTitle = actionTitle
        self.text = text
        self.isNegative = isNegative
    }
}

/// Result of compilation, including any orphaned user examples.
public struct CompilationResult: Sendable {
    public let index: CompiledIndex
    public let orphanedExamples: [UserExample]
}

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

    /// Backward-compatible overload — returns CompiledIndex directly.
    public func compile(manifests: [YAMLSkillManifest]) async throws -> CompiledIndex {
        try await compile(manifests: manifests, userExamples: []).index
    }

    /// Compile one or more YAML skill manifests into a CompiledIndex,
    /// merging user-provided examples alongside built-in ones.
    /// User examples referencing unknown (skillID, actionID) pairs are returned as orphans.
    public func compile(
        manifests: [YAMLSkillManifest],
        userExamples: [UserExample]
    ) async throws -> CompilationResult {
        guard languages.isEmpty == false else {
            throw SkillCompilerError.noLanguagesConfigured
        }

        let userExamplesByAction = Dictionary(
            grouping: userExamples,
            by: { "\($0.skillID)|\($0.actionID)" }
        )

        var validPairs = Set<String>()
        var entries: [CompiledEntry] = []

        for manifest in manifests {
            for action in manifest.actions {
                let key = "\(manifest.skillID)|\(action.id)"
                validPairs.insert(key)

                let actionEntries = await compileAction(
                    action: action,
                    skillID: manifest.skillID,
                    skillName: manifest.name
                )
                entries.append(contentsOf: actionEntries)

                if let extras = userExamplesByAction[key] {
                    let userEntries = await compileUserExamples(
                        extras,
                        action: action,
                        skillID: manifest.skillID,
                        skillName: manifest.name
                    )
                    entries.append(contentsOf: userEntries)
                }
            }
        }

        let orphaned = userExamples.filter { !validPairs.contains("\($0.skillID)|\($0.actionID)") }

        return CompilationResult(
            index: CompiledIndex(entries: entries),
            orphanedExamples: orphaned
        )
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

    private func compileUserExamples(
        _ examples: [UserExample],
        action: YAMLSkillAction,
        skillID: String,
        skillName: String
    ) async -> [CompiledEntry] {
        var entries: [CompiledEntry] = []

        let userSampleText = examples.prefix(3).map(\.text).joined(separator: " ")
        let sourceLanguage = translationService.detectLanguage(of: userSampleText) ?? "en"
        let translationContext = [action.title, action.description]
            .compactMap { $0 }
            .joined(separator: " — ")

        let positives = examples.filter { !$0.isNegative }
        let negatives = examples.filter { $0.isNegative }

        for language in languages {
            var textsToEmbed: [String]
            if language == sourceLanguage {
                textsToEmbed = positives.map(\.text)
            } else {
                textsToEmbed = await translationService.translate(
                    examples: positives.map(\.text),
                    fromLanguage: sourceLanguage,
                    toLanguage: language,
                    context: translationContext
                )
            }

            for text in textsToEmbed {
                guard let vector = embeddingService.embed(text, language: language) else { continue }
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
                    source: .user
                ))
            }

            var negTexts: [String]
            if language == sourceLanguage {
                negTexts = negatives.map(\.text)
            } else if negatives.isEmpty == false {
                negTexts = await translationService.translate(
                    examples: negatives.map(\.text),
                    fromLanguage: sourceLanguage,
                    toLanguage: language,
                    context: translationContext
                )
            } else {
                negTexts = []
            }

            for text in negTexts {
                guard let vector = embeddingService.embed(text, language: language) else { continue }
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
                    isNegative: true,
                    source: .user
                ))
            }
        }

        return entries
    }
}
