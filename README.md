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
- `RouterCore`: domain types (`RouterPlan`, `CompiledIndex`, `MatchCandidate`), routing policy, destination resolution, provider selection, plan validation, execution orchestration, event storage protocol.
- `SkillRegistry`: YAML skill manifest parsing and validation, legacy JSON manifest support, repository index support.
- `SkillCompiler`: compile pipeline that converts YAML skill examples into NLEmbedding vectors. Stores the compiled index to disk for fast loading on subsequent launches.
- `Executors`: deterministic execution primitives for local logging, Shortcuts, and URL schemes.
- `SystemProviders`: Apple-first providers for reminders, notes, calendar, shortcuts, and local logging.
- `ExternalProviders`: manifest-backed providers that map skills onto built-in executors.
- `ModelRuntime`: planner backends including rule-based, Apple Foundation Model, and compiled embedding router.

## Compiled Embedding Router

The primary routing backend compiles skill examples into a vector index at install time, then matches user commands via cosine similarity search at runtime.

```text
COMPILE TIME (on skill install / first launch)
  YAML skill files → parse actions + examples → embed with NLEmbedding → store compiled index

RUNTIME (on user command)
  User input → embed with NLEmbedding (~5ms) → nearest-neighbor search (~1ms) → top 5 matches
    → execute immediately (if no parameters needed)
    → or Phase 2: Foundation Model extracts parameters from matched action's schema (~1s)
```

The compiled index is cached to disk between app launches. Recompilation is triggered by skill changes or tapping "Recompile" in the Debug tab.

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

Skills can register additional capabilities (e.g., `vehicle.unlock`, `vehicle.climate.start`). Multiple skills can provide the same capability — the router handles disambiguation.

## Local-First Privacy Model

- Core routing works offline through the compiled embedding index and NLEmbedding.
- Phase 2 parameter extraction uses the on-device Foundation Model (no network).
- Remote escalation is optional and disabled by default.
- Every dispatch event is stored locally with SwiftData.
- External skills are declarative only. No arbitrary code execution is allowed.
- Shortcut-backed actions require confirmation before execution.

## Skill Format (YAML)

Skills are defined as YAML files with actions, examples, and optional shortcut bridge configuration.

```yaml
skill_id: tesla
name: Tesla
version: 1.0.0
bridge_shortcut: "OpenDispatch - Tesla"
bridge_shortcut_share_url: https://www.icloud.com/shortcuts/...

actions:
  - id: vehicle.unlock
    title: "Unlock"
    description: "Unlock your Tesla vehicle"
    shortcut_arguments:
      action: vehicle.unlock
      vehicle: default
    examples:
      - unlock my car
      - unlock the tesla
      - open my car

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

Actions without `parameters` execute immediately after vector matching — no LLM call needed. Actions with `parameters` trigger a lean Foundation Model call to extract values.

See [docs/skill-yaml-format.md](docs/skill-yaml-format.md) for the full format reference.

## App Screens

- Home: text dispatch, speech capture, recent event history
- Skill Manager: installed skills, repository sources, import and validation feedback
- Settings: backend selection, escalation toggle, dry-run, provider preferences
- Debug: compiled index inspector, match candidates with confidence scores, RouterPlan JSON, execution logs

## Add A Skill

1. Create a `skill.yaml` file with actions and examples.
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

This repository is an MVP focused on deterministic routing via compiled embeddings, local storage, and a safe plugin model. The embedding router is functional with NLEmbedding sentence embeddings. Known limitation: NLEmbedding produces relatively tight confidence clusters for short command phrases — a bundled sentence transformer (e.g., MiniLM) would improve discrimination. Translation of skill examples for multilingual support is planned but not yet implemented.

## Acknowledgments

The compiled embedding router architecture, YAML skill format, and Phase 2 parameter extraction pipeline were designed and implemented collaboratively with [Claude](https://claude.ai) (Anthropic). The core insight — that you can replace slow LLM prompt-stuffing with pre-compiled NLEmbedding vectors and only call the language model when parameter extraction is actually needed — emerged from a single brainstorming session that went from "how do we make routing faster" to working code with 22 passing end-to-end tests in one sitting. It was a genuinely fun afternoon of building.
