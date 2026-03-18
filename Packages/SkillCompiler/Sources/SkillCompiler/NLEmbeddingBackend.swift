import Foundation
import NaturalLanguage

/// Embedding backend using Apple's NLEmbedding.
/// Used as a fallback for testing and when no Core ML model is available.
public struct NLEmbeddingBackend: EmbeddingBackend, Sendable {
    private let language: NLLanguage

    public init(language: NLLanguage = .english) {
        self.language = language
    }

    public func embed(_ text: String) -> [Float]? {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: language) else {
            return nil
        }
        guard let vector = embedding.vector(for: text) else {
            return nil
        }
        return vector.map { Float($0) }
    }
}
