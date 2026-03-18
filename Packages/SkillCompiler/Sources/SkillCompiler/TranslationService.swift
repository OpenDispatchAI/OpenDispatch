import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Translates skill examples between languages using the on-device Foundation Model.
public struct TranslationService: Sendable {

    public init() {}

    /// Detect the dominant language of a block of text.
    public func detectLanguage(of text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    /// Determine which target languages need translation from the source.
    public func languagesNeedingTranslation(
        sourceLanguage: String,
        targetLanguages: [String]
    ) -> [String] {
        targetLanguages.filter { $0 != sourceLanguage }
    }

    /// Translate examples from one language to another using the Foundation Model.
    /// Returns the translated examples, or the originals if translation fails.
    /// - Parameters:
    ///   - context: Optional context about what the examples are for (e.g., "Unlock — Unlock the car doors")
    public func translate(
        examples: [String],
        fromLanguage: String,
        toLanguage: String,
        context: String? = nil
    ) async -> [String] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return await translateWithFoundationModel(
                examples: examples,
                fromLanguage: fromLanguage,
                toLanguage: toLanguage,
                context: context
            )
        }
        #endif
        return examples
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func translateWithFoundationModel(
        examples: [String],
        fromLanguage: String,
        toLanguage: String,
        context: String? = nil
    ) async -> [String] {
        guard SystemLanguageModel.default.availability == .available else {
            print("[Translation] Foundation Model not available, skipping translation")
            return examples
        }

        let fromName = Locale.current.localizedString(forLanguageCode: fromLanguage) ?? fromLanguage
        let toName = Locale.current.localizedString(forLanguageCode: toLanguage) ?? toLanguage

        let contextLine = context.map { "\nContext: these are voice commands for the action: \($0)" } ?? ""

        let session = LanguageModelSession {
            """
            You are a translator. Translate each line from \(fromName) to \(toName).
            These are short imperative voice commands that a user speaks to control an app.
            Use the imperative/command form, not infinitive. Keep them short and natural.\(contextLine)
            Return ONLY the translations, one per line, in the same order.
            DO NOT add numbering, quotes, or explanations.
            """
        }

        do {
            let prompt = examples.joined(separator: "\n")
            let response = try await session.respond(to: prompt)
            let lines = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.isEmpty == false }

            if lines.count == examples.count {
                print("[Translation] Translated \(examples.count) examples from \(fromName) to \(toName)")
                return lines
            } else {
                print("[Translation] Count mismatch: expected \(examples.count), got \(lines.count)")
                return lines + Array(examples.dropFirst(lines.count))
            }
        } catch {
            print("[Translation] Failed: \(error.localizedDescription)")
            return examples
        }
    }
    #endif
}
