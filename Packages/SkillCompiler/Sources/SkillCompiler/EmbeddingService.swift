import Foundation
import NaturalLanguage

public struct EmbeddingService: Sendable {

    public init() {}

    /// Embed a text string into a vector using NLEmbedding for the given language.
    /// Returns nil if sentence embeddings are not available for the language.
    public func embed(_ text: String, language: String) -> [Float]? {
        let nlLanguage = NLLanguage(rawValue: language)
        guard let embedding = NLEmbedding.sentenceEmbedding(for: nlLanguage) else {
            return nil
        }
        guard let vector = embedding.vector(for: text) else {
            return nil
        }
        return vector.map { Float($0) }
    }

    /// Cosine distance between two vectors. 0 = identical, 2 = opposite.
    public func cosineDistance(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, a.isEmpty == false else { return 1.0 }
        var dot: Float = 0, normA: Float = 0, normB: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 1.0 }
        return Double(1.0 - (dot / denom))
    }

    /// Check which languages have sentence embedding support on this device.
    public func supportedLanguages() -> [String] {
        let candidates: [NLLanguage] = [
            .english, .spanish, .french, .german, .italian,
            .portuguese, .dutch, .russian, .simplifiedChinese,
            .japanese, .korean, .arabic, .turkish, .polish,
            .swedish, .danish, .norwegian, .finnish,
        ]
        return candidates
            .filter { NLEmbedding.sentenceEmbedding(for: $0) != nil }
            .map(\.rawValue)
    }

    /// Detect the dominant language of a text string.
    public func detectLanguage(of text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }
}
