# OpenDispatch

OpenDispatch is a local-first command router for iPhone. It interprets short natural-language commands, matches them against a compiled vector index of installed skills, and dispatches structured actions to apps via Shortcuts bridge integrations.

## Architecture

Repository layout:

```text
OpenDispatch
├── OpenDispatchApp
├── Packages
│   ├── CapabilityRegistry
│   ├── RouterCore
│   ├── SkillRegistry
│   ├── SkillCompiler
│   ├── Executors
│   ├── SystemProviders
│   ├── ExternalProviders
│   └── ModelRuntime
├── SampleSkills
├── SkillRepositories
└── docs
```

Package responsibilities:

- `CapabilityRegistry`: canonical capabilities plus provider indexing.
- `RouterCore`: domain types (`RouterPlan`, `CompiledIndex`, `MatchCandidate`), routing policy, destination resolution, provider selection, cosine similarity search with negative example penalties.
- `SkillRegistry`: YAML skill manifest parsing and validation, repository index support.
- `SkillCompiler`: compile pipeline that converts YAML skill examples into sentence embeddings via a pluggable `EmbeddingBackend` protocol. Includes translation service for multilingual support and compiled index persistence.
- `Executors`: deterministic execution primitives for local logging, Shortcuts, and URL schemes.
- `SystemProviders`: Apple-first providers for reminders, notes, calendar, shortcuts, and local logging.
- `ExternalProviders`: manifest-backed providers that map legacy JSON skills onto built-in executors.
- `ModelRuntime`: legacy planner backends (rule-based, Apple Foundation Model).

## Compiled Embedding Router

The primary routing backend compiles skill examples into a vector index at install time, then matches user commands via cosine similarity search at runtime.

```text
COMPILE TIME (on skill install / first launch)
  YAML skill files
    → parse actions + examples + negative examples
    → translate to configured languages (Foundation Model)
    → embed with paraphrase-multilingual-MiniLM (384-dim, 50+ languages)
    → cache compiled index to disk

RUNTIME (on user command)
  User input → embed (~10ms) → cosine search (~1ms) → top 5 matches
    → apply negative example penalties
    → execute immediately (if no parameters needed)
    → or Phase 2: Foundation Model extracts parameters via GenerationSchema (~1s)
```

The compiled index is cached between app launches. Recompilation is triggered by skill changes, language settings changes, or tapping "Recompile" in the Debug tab.

See [docs/compiled-embedding-router.md](docs/compiled-embedding-router.md) for full details.

## Capability Routing

OpenDispatch routes by capability, not by chatbot-style skill names.

Canonical MVP capabilities:

- `log.event`
- `task.create`
- `task.complete`
- `note.create`
- `calendar.event.create`
- `shortcut.run`
- `url.open`

Skills register additional capabilities dynamically (e.g., `vehicle.unlock`, `vehicle.climate.start`). Multiple skills can provide the same capability — the router handles disambiguation via confidence gaps and user preferences.

## Local-First Privacy Model

- All routing runs on-device via compiled embeddings and a bundled sentence transformer.
- Phase 2 parameter extraction uses the on-device Foundation Model (no network).
- Remote escalation is optional and disabled by default.
- Every dispatch event is stored locally with SwiftData.
- External skills are declarative only. No arbitrary code execution is allowed.
- Shortcut-backed actions support per-action confirmation control.

## Skill Format (YAML)

Skills are defined as YAML files with actions, examples, negative examples, and optional shortcut bridge configuration.

```yaml
skill_id: tesla
name: Tesla
version: 1.0.0
bridge_shortcut: "OpenDispatch - Tesla V1"
bridge_shortcut_share_url: https://www.icloud.com/shortcuts/...

actions:
  - id: vehicle.unlock
    title: "Unlock"
    description: "Unlock the car doors so you can get in"
    confirmation: none
    shortcut_arguments:
      action: vehicle.unlock
      vehicle: default
    examples:
      - unlock my car
      - unlock the tesla
      - unlock the car doors
    negative_examples:
      - open my car windows
      - open the trunk

  - id: vehicle.climate.set_temperature
    title: "Set Temperature"
    description: "Set the Tesla cabin temperature"
    shortcut_arguments:
      action: vehicle.climate.set_temperature
      vehicle: default
      temperature: "{{temperature}}"
    parameters:
      - name: temperature
        type: number
        description: "Target temperature in degrees"
        required: true
    examples:
      - set the car to 21 degrees
      - make the tesla 19 degrees
```

- Actions without `parameters` execute immediately after vector matching — no LLM call needed.
- Actions with `parameters` trigger a lean Foundation Model call to extract values using a dynamically generated schema.
- `negative_examples` prevent misrouting by penalizing confidence when input is close to a counter-example.
- `confirmation: required | none | destructive_only` controls per-action confirmation prompts.

See [docs/skill-yaml-format.md](docs/skill-yaml-format.md) for the full format reference.

## Embedding Model

The app bundles [paraphrase-multilingual-MiniLM-L12-v2](https://huggingface.co/sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2), a 384-dimensional sentence transformer supporting 50+ languages. Converted to Core ML, it runs on the Neural Engine with a custom Unigram (SentencePiece) tokenizer.

The embedding system uses the `EmbeddingBackend` protocol — models can be swapped without code changes. Falls back to Apple's NLEmbedding if the bundled model fails to load.

## Multilingual Support

- Users configure languages in Settings
- The compile step translates skill examples to all configured languages via the on-device Foundation Model
- Both original and translated examples are embedded in the index
- The bundled model supports 50+ languages natively

## App Screens

- Home: text dispatch, speech capture, recent event history
- Skill Manager: installed skills, repository sources, import and validation feedback
- Settings: backend selection, escalation toggle, dry-run, provider preferences, language configuration
- Debug: compiled index inspector with per-skill drill-in, match candidates with confidence scores and gap indicator, negative examples, compiled embeddings per language, RouterPlan JSON, execution logs, bridge shortcut install

## Add A Skill

1. Create a `skill.yaml` file with actions, examples, and optionally negative examples.
2. For app integrations, create a bridge shortcut in Apple Shortcuts that accepts JSON input and branches on the `action` field.
3. Add a `bridge_shortcut_share_url` so users can install the shortcut.
4. Bundle the YAML in the app or import it from the Skill Manager screen.
5. The compile step embeds all examples into the vector index automatically.

## Testing

```bash
# Package tests (includes end-to-end embedding routing tests)
cd Packages/RouterCore && swift test
cd Packages/SkillRegistry && swift test
cd Packages/SkillCompiler && swift test

# App build
xcodebuild -project OpenDispatchApp/OpenDispatch.xcodeproj -scheme OpenDispatch -destination 'generic/platform=iOS Simulator' build
```

## Status

This repository is an MVP focused on deterministic routing via compiled embeddings, local storage, and a safe plugin model. The embedding router uses a bundled paraphrase-multilingual-MiniLM sentence transformer (384-dim, 50+ languages) with a custom Unigram tokenizer. Negative examples provide disambiguation for overlapping commands. Translation of skill examples to configured languages is supported via the on-device Foundation Model. The architecture supports pluggable embedding backends via the `EmbeddingBackend` protocol for future model upgrades.

## Acknowledgments

The compiled embedding router architecture, YAML skill format, and Phase 2 parameter extraction pipeline were designed and implemented collaboratively with [Claude](https://claude.ai) (Anthropic). The core insight — that you can replace slow LLM prompt-stuffing with pre-compiled embedding vectors and only call the language model when parameter extraction is actually needed — emerged from a single brainstorming session that went from "how do we make routing faster" to working code with 22 passing end-to-end tests in one sitting. It was a genuinely fun afternoon of building.
