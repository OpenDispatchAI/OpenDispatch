import Foundation
import NaturalLanguage

/// Protocol for embedding backends (e.g., Core ML sentence transformers).
public protocol EmbeddingBackend: Sendable {
    func embed(_ text: String) -> [Float]?
}

public struct EmbeddingService: Sendable {
    private let backend: any EmbeddingBackend

    public init(backend: any EmbeddingBackend) {
        self.backend = backend
    }

    /// Embed a text string into a vector.
    public func embed(_ text: String, language: String) -> [Float]? {
        backend.embed(text)
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

    /// Detect the dominant language of a text string.
    public func detectLanguage(of text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }
}
