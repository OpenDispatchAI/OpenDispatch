import Foundation
import CapabilityRegistry
import RouterCore
import SkillCompiler
import SkillRegistry
#if canImport(FoundationModels)
import FoundationModels
#endif

struct EmbeddingRouterBackend: RouterPlanningBackend, Sendable {
    let id = "embedding_router"

    private let compiledIndex: CompiledIndex
    private let embeddingService: EmbeddingService
    private let confidenceThreshold: Double
    private let ambiguityGapThreshold: Double
    private let topK: Int

    init(
        compiledIndex: CompiledIndex,
        embeddingService: EmbeddingService = EmbeddingService(),
        confidenceThreshold: Double = 0.4,
        ambiguityGapThreshold: Double = 0.15,
        topK: Int = 5
    ) {
        self.compiledIndex = compiledIndex
        self.embeddingService = embeddingService
        self.confidenceThreshold = confidenceThreshold
        self.ambiguityGapThreshold = ambiguityGapThreshold
        self.topK = topK
    }

    func plan(
        request: RouterRequest,
        availableSkills: [PlannerSkillContext]
    ) async throws -> RouterPlan {
        let inputText = request.rawInput.trimmingCharacters(in: .whitespacesAndNewlines)

        // Detect language and embed
        let detectedLanguage = embeddingService.detectLanguage(of: inputText) ?? "en"
        guard let queryVector = embeddingService.embed(inputText, language: detectedLanguage) else {
            return fallbackPlan(rawInput: inputText)
        }

        // Search
        let candidates = compiledIndex.nearestNeighbors(to: queryVector, count: topK)

        // Always log match candidates for debugging
        if let top = candidates.first {
            print("[EmbeddingRouter] Top match: \(top.skillName)/\(top.actionTitle) confidence=\(String(format: "%.3f", top.confidence)) distance=\(String(format: "%.3f", top.distance))")
        }
        for (i, c) in candidates.prefix(5).enumerated() {
            print("[EmbeddingRouter]   #\(i+1) \(c.actionID) confidence=\(String(format: "%.3f", c.confidence))")
        }

        guard let topMatch = candidates.first, topMatch.confidence >= confidenceThreshold else {
            print("[EmbeddingRouter] Below threshold (\(confidenceThreshold)), falling back")
            return fallbackPlan(rawInput: inputText, matchCandidates: candidates)
        }

        // Build parameters from shortcut arguments
        var parameters: [String: JSONValue] = [:]
        var needsExtraction = false

        if let entry = compiledIndex.entry(for: topMatch) {
            if let args = entry.shortcutArguments {
                parameters = args
            }
            needsExtraction = entry.requiresParameterExtraction
        }

        // Phase 2: Extract parameters from user input using Foundation Model
        if needsExtraction, let entry = compiledIndex.entry(for: topMatch), let paramSchemas = entry.parameters {
            let extracted = await extractParameters(
                from: inputText,
                schemas: paramSchemas,
                actionTitle: entry.actionTitle
            )
            // Substitute {{placeholder}} values and merge extracted params
            for (key, value) in parameters {
                if let template = value.stringValue,
                   template.hasPrefix("{{"), template.hasSuffix("}}") {
                    let paramName = String(template.dropFirst(2).dropLast(2))
                    if let extractedValue = extracted[paramName] {
                        parameters[key] = extractedValue
                    }
                }
            }
            // Also add extracted params directly (for non-shortcut skills)
            for (key, value) in extracted {
                if parameters[key] == nil {
                    parameters[key] = value
                }
            }
        }

        return RouterPlan(
            capability: topMatch.capability,
            parameters: parameters,
            confidence: topMatch.confidence,
            title: "\(topMatch.skillName) → \(topMatch.actionTitle)",
            suggestedProviderID: topMatch.skillID,
            matchCandidates: candidates
        )
    }

    // MARK: - Phase 2: Parameter Extraction

    private func extractParameters(
        from input: String,
        schemas: [ParameterSchema],
        actionTitle: String
    ) async -> [String: JSONValue] {
        // Try Foundation Model first (iOS 26+)
        if #available(iOS 26.0, *) {
            if let result = await extractWithFoundationModel(
                input: input, schemas: schemas, actionTitle: actionTitle
            ) {
                return result
            }
        }

        // Fallback: simple regex-based extraction for common types
        return extractWithRegex(from: input, schemas: schemas)
    }

    @available(iOS 26.0, *)
    private func extractWithFoundationModel(
        input: String,
        schemas: [ParameterSchema],
        actionTitle: String
    ) async -> [String: JSONValue]? {
        #if !canImport(FoundationModels)
        return nil
        #else
        guard SystemLanguageModel.default.availability == .available else {
            return nil
        }

        // Dynamically build a GenerationSchema from the YAML parameter definitions
        let properties: [GenerationSchema.Property] = schemas.map { param in
            switch param.type {
            case "number", "int", "integer":
                return .init(
                    name: param.name,
                    description: param.description ?? param.name,
                    type: Double?.self
                )
            default:
                return .init(
                    name: param.name,
                    description: param.description ?? param.name,
                    type: String?.self
                )
            }
        }

        let schema = GenerationSchema(
            type: GeneratedContent.self,
            description: "Extract parameters for action: \(actionTitle)",
            properties: properties
        )

        let instructions = """
        Extract parameter values from the user's command.
        Action: \(actionTitle)
        Return structured values matching the schema.
        For numbers, extract the numeric value.
        If a value is not present in the input, return null.
        """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: input,
                schema: schema,
                options: GenerationOptions(maximumResponseTokens: 120)
            )

            // Extract values from GeneratedContent into JSONValue dictionary
            var result: [String: JSONValue] = [:]
            for param in schemas {
                switch param.type {
                case "number", "int", "integer":
                    if let value: Double = try? response.content.value(Double?.self, forProperty: param.name) {
                        if value == value.rounded() && value >= Double(Int.min) && value <= Double(Int.max) {
                            result[param.name] = .integer(Int(value))
                        } else {
                            result[param.name] = .number(value)
                        }
                    }
                default:
                    if let value: String = try? response.content.value(String?.self, forProperty: param.name),
                       value.isEmpty == false {
                        result[param.name] = .string(value)
                    }
                }
            }

            print("[Phase2] Extracted parameters via schema: \(result)")
            return result
        } catch {
            print("[Phase2] Foundation Model schema extraction failed: \(error)")
            return nil
        }
        #endif
    }

    /// Simple regex fallback for extracting numbers from input
    private func extractWithRegex(
        from input: String,
        schemas: [ParameterSchema]
    ) -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]

        for schema in schemas {
            switch schema.type {
            case "number", "int", "integer":
                // Find first number in input
                if let match = input.range(of: #"\d+\.?\d*"#, options: .regularExpression) {
                    let numberStr = String(input[match])
                    if let intVal = Int(numberStr) {
                        result[schema.name] = .integer(intVal)
                    } else if let doubleVal = Double(numberStr) {
                        result[schema.name] = .number(doubleVal)
                    }
                }
            case "string":
                // For string params, pass the whole input as value
                result[schema.name] = .string(input)
            default:
                break
            }
        }

        return result
    }

    // MARK: - Fallback

    private func fallbackPlan(
        rawInput: String,
        matchCandidates: [MatchCandidate] = []
    ) -> RouterPlan {
        RouterPlan(
            capability: CapabilityID(rawValue: "log.event"),
            parameters: [
                "normalized_intent": .string(rawInput),
            ],
            confidence: 0.3,
            title: "Log event",
            suggestedProviderID: nil,
            matchCandidates: matchCandidates.isEmpty ? nil : matchCandidates
        )
    }
}
