import CoreML
import Foundation
import SkillCompiler

/// Core ML embedding backend using paraphrase-multilingual-MiniLM-L12-v2.
/// Produces 384-dimensional sentence embeddings supporting 50+ languages.
/// Trained on paraphrase data — good discrimination for short phrases.
final class ParaphraseBackend: EmbeddingBackend, @unchecked Sendable {
    private let model: MLModel
    private let tokenizer: UnigramTokenizer
    private let maxLength = 128

    init?(bundle: Bundle = .main) {
        guard let modelURL = bundle.url(forResource: "ParaphraseMultiMiniLM", withExtension: "mlmodelc")
                ?? bundle.url(forResource: "ParaphraseMultiMiniLM", withExtension: "mlpackage") else {
            print("[Paraphrase] Model not found in bundle")
            return nil
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all

        guard let model = try? MLModel(contentsOf: modelURL, configuration: config) else {
            print("[Paraphrase] Failed to load model")
            return nil
        }
        self.model = model

        guard let vocabURL = bundle.url(forResource: "tokenizer_vocab", withExtension: "tsv"),
              let tokenizer = UnigramTokenizer(tsvURL: vocabURL) else {
            print("[Paraphrase] Failed to load tokenizer")
            return nil
        }
        self.tokenizer = tokenizer

        print("[Paraphrase] Loaded paraphrase-multilingual-MiniLM (\(tokenizer.vocabSize) tokens)")
    }

    func embed(_ text: String) -> [Float]? {
        // No prefix needed — paraphrase model uses symmetric embedding
        let tokens = tokenizer.encode(text, maxLength: maxLength)

        guard let idArray = try? MLMultiArray(shape: [1, NSNumber(value: maxLength)], dataType: .int32),
              let maskArray = try? MLMultiArray(shape: [1, NSNumber(value: maxLength)], dataType: .int32) else {
            return nil
        }

        for i in 0..<maxLength {
            idArray[i] = NSNumber(value: i < tokens.inputIDs.count ? tokens.inputIDs[i] : 0)
            maskArray[i] = NSNumber(value: i < tokens.attentionMask.count ? tokens.attentionMask[i] : 0)
        }

        guard let input = try? MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: idArray),
            "attention_mask": MLFeatureValue(multiArray: maskArray),
        ]),
        let output = try? model.prediction(from: input),
        let embeddings = output.featureValue(for: "embeddings")?.multiArrayValue else {
            return nil
        }

        return (0..<embeddings.count).map { Float(truncating: embeddings[$0]) }
    }
}

// MARK: - Unigram Tokenizer

/// SentencePiece Unigram tokenizer that uses Viterbi algorithm to find
/// the optimal tokenization based on token log-probabilities.
nonisolated final class UnigramTokenizer: @unchecked Sendable {
    private let vocab: [String: (id: Int, score: Double)]
    private let unkTokenID: Int
    private let clsTokenID: Int
    private let sepTokenID: Int
    private let padTokenID: Int

    var vocabSize: Int { vocab.count }

    init?(tsvURL: URL) {
        guard let content = try? String(contentsOf: tsvURL, encoding: .utf8) else {
            return nil
        }

        var vocab: [String: (id: Int, score: Double)] = [:]
        for (index, line) in content.components(separatedBy: .newlines).enumerated() {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2,
                  let score = Double(parts[1]) else { continue }
            let token = String(parts[0])
            vocab[token] = (id: index, score: score)
        }

        self.vocab = vocab
        self.unkTokenID = vocab["<unk>"]?.id ?? 3
        self.clsTokenID = vocab["<s>"]?.id ?? 0
        self.sepTokenID = vocab["</s>"]?.id ?? 2
        self.padTokenID = vocab["<pad>"]?.id ?? 1
    }

    struct TokenizedInput {
        let inputIDs: [Int]
        let attentionMask: [Int]
    }

    func encode(_ text: String, maxLength: Int) -> TokenizedInput {
        let tokenIDs = tokenize(text)
        let truncated = Array(tokenIDs.prefix(maxLength - 2))

        var inputIDs = [clsTokenID]
        inputIDs.append(contentsOf: truncated)
        inputIDs.append(sepTokenID)

        let attentionLength = inputIDs.count
        while inputIDs.count < maxLength {
            inputIDs.append(padTokenID)
        }

        var attentionMask = Array(repeating: 1, count: attentionLength)
        while attentionMask.count < maxLength {
            attentionMask.append(0)
        }

        return TokenizedInput(inputIDs: inputIDs, attentionMask: attentionMask)
    }

    private func tokenize(_ text: String) -> [Int] {
        // SentencePiece pre-tokenization: replace spaces with ▁
        let normalized = "▁" + text.replacingOccurrences(of: " ", with: "▁")

        // Viterbi: find the tokenization with the highest total score
        let chars = Array(normalized)
        let n = chars.count

        // bestScore[i] = best total score for chars[0..<i]
        // bestLen[i] = length of the last token in the best path to position i
        var bestScore = [Double](repeating: -.infinity, count: n + 1)
        var bestLen = [Int](repeating: 0, count: n + 1)
        bestScore[0] = 0

        for i in 0..<n {
            guard bestScore[i] > -.infinity else { continue }

            // Try all substrings starting at position i
            let maxTokenLen = min(n - i, 64) // reasonable max token length
            for length in 1...maxTokenLen {
                let endIdx = i + length
                let substr = String(chars[i..<endIdx])

                if let entry = vocab[substr] {
                    let newScore = bestScore[i] + entry.score
                    if newScore > bestScore[endIdx] {
                        bestScore[endIdx] = newScore
                        bestLen[endIdx] = length
                    }
                }
            }

            // If no token matches from this position, treat single char as UNK
            if bestScore[i + 1] == -.infinity {
                bestScore[i + 1] = bestScore[i] - 100 // heavy penalty for UNK
                bestLen[i + 1] = 1
            }
        }

        // Backtrack to recover the best tokenization
        var tokenIDs: [Int] = []
        var pos = n
        while pos > 0 {
            let length = bestLen[pos]
            let start = pos - length
            let substr = String(chars[start..<pos])

            if let entry = vocab[substr] {
                tokenIDs.append(entry.id)
            } else {
                tokenIDs.append(unkTokenID)
            }
            pos = start
        }

        tokenIDs.reverse()
        return tokenIDs
    }
}
