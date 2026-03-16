# Compiled Embedding Router

The compiled embedding router is OpenDispatch's primary command routing system. It replaces the previous approach of sending all skill descriptions to an on-device language model with a pre-computed vector index that matches user commands in milliseconds.

## How It Works

### Overview

```
COMPILE TIME (on skill install / change / first launch)
───────────────────────────────────────────────────────
YAML skill files
  → Parse actions + examples
  → Embed each example using NLEmbedding
  → Store as compiled index (vectors + metadata)
  → Cache index to disk (Application Support)

APP LAUNCH
───────────────────────────────────────────────────────
Cached index exists?
  → Yes: load from disk (instant)
  → No: compile fresh, then cache

RUNTIME (on user command)
───────────────────────────────────────────────────────
User says "unlock my car"
  → Embed input using NLEmbedding (~5ms)
  → Cosine similarity search against index (~1ms)
  → Top 5 matches with confidence scores
  → Execute or extract parameters
```

### Caching

The compiled index is cached to disk (`Application Support/OpenDispatch/compiled_index.json`) after the first successful compile. On subsequent app launches, the cached index is loaded instantly without recompiling.

Recompilation is triggered by:
- Tapping "Recompile" in the Debug tab
- Installing or updating a skill
- Changing language settings

The cache is a JSON file containing all embedding vectors and metadata. For ~200 entries this is a few hundred KB.

### Compile Step

On first launch (or when recompilation is triggered), every example from every installed YAML skill gets converted into a numerical vector using Apple's [NLEmbedding](https://developer.apple.com/documentation/naturallanguage/nlembedding) framework.

The result is a flat array of `CompiledEntry` structs, each containing:
- The embedding vector (array of floats)
- Skill metadata (skill ID, name, action ID, title)
- Shortcut arguments (the literal payload to send on execution)
- Parameter schema (if the action needs runtime extraction)
- The original example text and language (for debugging)

For a typical setup with 10-20 skills and 5-10 examples each, this produces ~100-200 vectors. The compile step takes a few seconds, dominated by NLEmbedding model loading.

### Runtime Routing

When a user speaks or types a command:

1. **Embed the input** — NLEmbedding converts the text to a vector in the same space as the compiled examples. This takes ~5ms.

2. **Nearest-neighbor search** — Cosine distance is computed between the input vector and every entry in the index. The top 5 closest matches are returned, sorted by distance (ascending). This takes <1ms for ~200 vectors.

3. **Confidence scoring** — Each match gets a confidence score: `confidence = 1.0 - cosine_distance`. A score of 1.0 means identical vectors; 0.0 means completely unrelated.

4. **Decision branching:**

| Condition | Action |
|---|---|
| High confidence, no parameters needed | Execute immediately via shortcut |
| High confidence, parameters needed | Phase 2: Foundation Model extracts parameters from the single matched action's schema |
| Low confidence or ambiguous | Ask the user to clarify |
| No match above threshold | Fall back to `log.event` |

### Phase 2: Parameter Extraction

Some actions need values extracted from the user's command. For example, "set the car to 21 degrees" needs the temperature `21` extracted.

Phase 2 only runs when the matched action has a `parameters` field in its YAML definition. It sends a lean prompt to the on-device Foundation Model containing only the matched action's parameter schema — not all skills. This keeps the LLM call fast (~1 second).

Actions without parameters (like `vehicle.unlock`) skip Phase 2 entirely and execute immediately after the vector match.

## Architecture

### Packages

| Package | Role |
|---|---|
| **RouterCore** | Defines `CompiledIndex`, `CompiledEntry`, `MatchCandidate`, `ParameterSchema` types |
| **SkillRegistry** | YAML parsing (`YAMLSkillParser`, `YAMLSkillManifest`) |
| **SkillCompiler** | Compile pipeline: `SkillCompiler`, `EmbeddingService`, `CompiledIndexStore` |
| **App target** | `EmbeddingRouterBackend` (conforms to `RouterPlanningBackend`) |

### Key Types

**`CompiledIndex`** — The compiled vector database. Contains an array of `CompiledEntry` and a `compiledAt` timestamp. Provides `nearestNeighbors(to:count:)` for search and `entry(for:)` for looking up metadata from a match.

**`CompiledEntry`** — One vector in the index. Stores the embedding, skill/action metadata, shortcut arguments, parameter schema, and the original example text.

**`MatchCandidate`** — A search result. Contains the matched skill/action, a confidence score (0-1), and a cosine distance. The top 5 candidates are attached to the `RouterPlan` for debug visibility.

**`EmbeddingService`** — Wrapper around `NLEmbedding`. Handles embedding text, detecting language, and listing supported languages.

**`SkillCompiler`** — Orchestrates the compile pipeline. Takes `[YAMLSkillManifest]` and configured languages, produces a `CompiledIndex`.

**`EmbeddingRouterBackend`** — The `RouterPlanningBackend` implementation. Takes a `CompiledIndex`, embeds user input, searches, and returns a `RouterPlan` with match candidates.

### Data Flow

```
YAMLSkillManifest
  → SkillCompiler.compile(manifests:)
    → EmbeddingService.embed(example, language)  [for each example]
    → CompiledIndex(entries:)

RouterRequest
  → EmbeddingRouterBackend.plan(request:)
    → EmbeddingService.embed(input, language)
    → CompiledIndex.nearestNeighbors(to:count:)
    → RouterPlan(capability:, parameters:, matchCandidates:)
```

## Cosine Similarity

The router uses cosine distance to measure how similar two vectors are:

```
cosine_distance = 1 - (A · B) / (|A| × |B|)
```

- **Distance 0** — Identical meaning (confidence 1.0)
- **Distance 1** — Unrelated (confidence 0.0)
- **Distance 2** — Opposite meaning (confidence clamped to 0.0)

This works because NLEmbedding places semantically similar text close together in vector space. "Unlock my car" and "open the car" produce similar vectors even though the words are different.

## Ambiguity Detection

When two skills compete for the same command, the **confidence gap** between the top two matches determines behavior:

```
Input: "unlock my car" (only Tesla installed)
  #1: tesla / vehicle.unlock    confidence: 0.92
  #2: tesla / vehicle.lock      confidence: 0.61
  Gap: 0.31 → CLEAR → auto-dispatch to #1

Input: "unlock my car" (Tesla + Polestar installed)
  #1: tesla / vehicle.unlock    confidence: 0.85
  #2: polestar / vehicle.unlock confidence: 0.82
  Gap: 0.03 → AMBIGUOUS → ask user "Tesla or Polestar?"
```

The gap threshold is configurable (default: 0.15).

## Debug Visibility

The Debug tab in the app shows:

- **Compiled Index** — Number of embeddings, skill count, compile timestamp. Drill into each skill to see all actions, their examples, shortcut arguments, and whether each example was successfully embedded.

- **Match Candidates** — After dispatching a command, shows the top 5 matches ranked by confidence with distance values and a confidence gap indicator (clear vs ambiguous).

- **RouterPlan JSON** — The full plan including `matchCandidates` array.

## NLEmbedding

The router uses Apple's [NLEmbedding](https://developer.apple.com/documentation/naturallanguage/nlembedding) for sentence embeddings. Key characteristics:

- Runs entirely on-device (Neural Engine)
- Available since iOS 17
- Supports multiple languages (English, Spanish, French, German, etc.)
- ~5ms per embedding on modern hardware
- No model download required — ships with the OS

Language support varies by device and OS version. The compiler filters configured languages to only those with available NLEmbedding models. Check `EmbeddingService.supportedLanguages()` to see what's available on a given device.

## Multilingual Support (Planned)

The system is designed for multilingual routing:

1. Users configure their languages in settings (e.g., `[en, nl]`)
2. During compilation, examples are translated into all configured languages using the Foundation Model
3. Translated examples are embedded with the appropriate language's NLEmbedding model
4. At runtime, input language is detected and the correct language's embedding model is used

This is not yet implemented (Task 4 in the implementation plan). Currently, examples are embedded with English NLEmbedding regardless of the actual language.

## Performance

| Operation | Time |
|---|---|
| Compile step (16 actions, ~70 examples) | ~2-3 seconds |
| Embed user input | ~5ms |
| Nearest-neighbor search (200 vectors) | <1ms |
| Phase 2 parameter extraction | ~1 second |
| **Total routing (no params)** | **~6ms** |
| **Total routing (with params)** | **~1 second** |

Compare to the previous Foundation Model approach: 2-6 seconds for every command, regardless of complexity.
