# OpenDispatch --- Product Requirements Document (PRD)

Version: 0.2 MVP Project: OpenDispatch Website: https://opendispatch.ai
Status: MVP Specification (Updated)

------------------------------------------------------------------------

# 1. Overview

OpenDispatch is a **local-first command router for iPhone** that
interprets natural language commands and dispatches structured actions
to apps.

Unlike AI chat assistants, OpenDispatch focuses on **deterministic
action routing**, not conversation.

Users trigger OpenDispatch primarily via the **iPhone Action Button**,
voice input, or text input.

The system converts an utterance into a **structured RouterPlan** using
a compiled embedding index, selects the appropriate provider, executes
the action safely, and logs the event locally.

Key principle: **Local-first, deterministic, privacy-preserving
automation.**

------------------------------------------------------------------------

# 2. Problem Statement

Modern AI assistants suffer from several issues:

-   Non-deterministic behavior
-   Cloud dependency
-   Privacy concerns
-   Lack of integration with real app workflows
-   Limited extensibility for power users

At the same time, iOS automation tools (Shortcuts, Siri) require rigid
configuration and do not understand natural language well.

OpenDispatch solves this by acting as a **local command interpreter that
routes intent to deterministic capabilities through user-defined "skills"**.

------------------------------------------------------------------------

# 3. Product Vision

OpenDispatch should become the **system-level action router for
iPhone**.

Instead of asking an assistant, users simply state intent:

Examples:

-   Unlock my car
-   Turn on the car AC
-   Add buy milk
-   Log coffee
-   Set the car to 21 degrees

The system interprets the request and dispatches the appropriate action.
If the user so chooses, complex requests and requests that cannot be matched
can still be routed to Apple Intelligence, or another cloud-based LLM provider (escalation).

OpenDispatch combines:

-   natural language input
-   compiled embedding-based capability routing
-   safe automation execution

------------------------------------------------------------------------

# 4. Goals

Primary goals for MVP:

1.  Enable natural language command routing via compiled embeddings.
2.  Work offline for core features.
3.  Execute actions through deterministic capabilities.
4.  Support extensibility through YAML skill packs.
5.  Maintain App Store compliance.
6.  Provide clear debugging visibility (match candidates, confidence gaps).

Secondary goals:

-   support skill repositories
-   enable external integrations via bridge shortcuts
-   provide safe execution policies
-   support multilingual routing

------------------------------------------------------------------------

# 5. Non-Goals (MVP)

Out of scope for the MVP:

-   conversational AI assistant
-   arbitrary plugin code execution
-   background automation
-   complex multi-step agent planning
-   mandatory cloud services

The MVP prioritizes **reliability and deterministic routing**.

------------------------------------------------------------------------

# 6. Core User Experience

Primary flow:

User presses Action Button\
→ OpenDispatch capture screen opens\
→ user speaks or types command\
→ system embeds input and searches compiled index\
→ top match determines capability and provider\
→ Phase 2 extracts parameters if needed (Foundation Model)\
→ provider executes action\
→ result displayed\
→ event logged locally

Example:

User says: "unlock my car"

System resolves:

Match: vehicle.unlock (Tesla, confidence 78.9%)\
Provider: Tesla (YAMLSkillProvider)\
Executor: ShortcutsExecutor → "OpenDispatch - Tesla V1"

Action executed successfully.

------------------------------------------------------------------------

# 7. System Architecture

High-level pipeline:

```
COMPILE TIME (on skill install / first launch)
  YAML skill files
    → Parse actions, examples, negative examples
    → Translate examples to configured languages (Foundation Model)
    → Embed with sentence transformer (paraphrase-multilingual-MiniLM)
    → Store compiled index to disk (cached between launches)

RUNTIME (on user command)
  User Input
    → Embed with sentence transformer (~10ms)
    → Cosine similarity search against compiled index (~1ms)
    → Top 5 matches with confidence scores
    → Apply negative example penalties
    → Branch:
      → High confidence + no parameters → Execute immediately
      → High confidence + parameters → Phase 2: Foundation Model extraction (~1s)
      → Low confidence → Escalation or log.event fallback
    → DestinationResolver → Provider → Executor
    → Store DispatchEvent locally
```

Packages:

- `CapabilityRegistry`: canonical capabilities plus provider indexing.
- `RouterCore`: domain types (RouterPlan, CompiledIndex, CompiledEntry, MatchCandidate), routing policy, destination resolution, provider selection, cosine distance search with negative example penalties.
- `SkillRegistry`: YAML skill manifest parsing (YAMLSkillParser, YAMLSkillManifest), validation, repository index support.
- `SkillCompiler`: compile pipeline (SkillCompiler), embedding service with pluggable backends (EmbeddingService, EmbeddingBackend protocol), translation service (TranslationService), compiled index persistence (CompiledIndexStore).
- `Executors`: deterministic execution primitives for local logging, Shortcuts, and URL schemes.
- `SystemProviders`: Apple-first providers for reminders, notes, calendar, shortcuts, and local logging.
- `ExternalProviders`: manifest-backed providers that map legacy JSON skills onto built-in executors.
- `ModelRuntime`: legacy planner backends (rule-based, Apple Foundation Model). The compiled embedding router (EmbeddingRouterBackend) lives in the app target.

------------------------------------------------------------------------

# 8. Core Concepts

## RouterRequest

Represents user input.

Fields:

-   raw_text
-   timestamp
-   input_source (voice / text / action_button)

------------------------------------------------------------------------

## RouterPlan

Structured plan describing the action.

Fields:

- capability
- parameters
- confidence
- title
- routing (hints)
- suggestedProviderID
- matchCandidates (top 5 ranked matches for debug traceability)

RouterPlan must support routing hints and match candidate traceability.

Example:

```json
{
  "capability": "vehicle.unlock",
  "parameters": {
    "action": "vehicle.unlock",
    "vehicle": "default"
  },
  "confidence": 0.789,
  "title": "Tesla → Unlock",
  "suggestedProviderID": "tesla",
  "matchCandidates": [
    {"skillName": "Tesla", "actionTitle": "Unlock", "actionID": "vehicle.unlock", "confidence": 0.789},
    {"skillName": "Tesla", "actionTitle": "Lock", "actionID": "vehicle.lock", "confidence": 0.752},
    {"skillName": "Tesla", "actionTitle": "Honk Horn", "actionID": "vehicle.horn", "confidence": 0.679}
  ]
}
```

## Compiled Index

The compiled index is the core routing data structure. It contains embedding vectors for every skill example, indexed for cosine similarity search.

Fields per entry:

- embedding (vector of floats, 384-dim)
- skillID, skillName
- actionID, actionTitle
- capability
- shortcutArguments (literal payload for execution)
- parameters (schema for Phase 2 extraction)
- originalExample (the text that was embedded)
- language
- isNegative (for counter-examples)

The index is versioned (schemaVersion) and cached to disk. Schema changes trigger automatic recompilation.

## Match Candidates

Each routing result includes the top 5 match candidates with confidence scores and distances. The confidence gap between #1 and #2 indicates routing certainty:

- Large gap (>0.15): clear match, auto-dispatch
- Small gap (<0.15): ambiguous, may prompt user

------------------------------------------------------------------------

## Negative Examples

Skills can define negative examples per action to prevent misrouting:

```yaml
- id: vehicle.unlock
  examples:
    - unlock my car
    - unlock the tesla
  negative_examples:
    - open my car windows
    - open the trunk
    - open the frunk
```

Negative examples are embedded during compilation. At search time, if user input is close to a negative example for an action, that action's confidence is penalized. This prevents "open my car windows" from routing to vehicle.unlock.

------------------------------------------------------------------------

## Destination Resolver

DestinationResolver maps routing hints to providers and concrete destinations.

Responsibilities:

- map routing hints to providers
- map routing hints to concrete destinations within a provider
- apply user preferences
- apply heuristic classification
- validate required destination parameters
- prompt user if ambiguous

------------------------------------------------------------------------

## Capability

Capabilities represent the **type of action requested**.

Core capabilities:

-   log.event
-   task.create
-   task.complete
-   note.create
-   calendar.event.create
-   shortcut.run
-   url.open

Skills register additional capabilities dynamically (e.g., vehicle.unlock, vehicle.climate.start). Capability IDs follow the pattern `word.word` with underscores allowed (e.g., `vehicle.climate.set_temperature`).

------------------------------------------------------------------------

## Provider

Providers implement capabilities.

Two types:

1. **System providers** (built-in): AppleRemindersProvider, AppleNotesProvider, etc.
2. **YAML skill providers** (YAMLSkillProvider): backed by bridge shortcuts, registered from compiled YAML manifests.

Each YAML skill registers as a single provider with all its actions as capabilities.

------------------------------------------------------------------------

## Executor

Executors perform the actual action.

Executors are built into the app and cannot be extended with code.

Types:

- LocalLogExecutor
- ShortcutsExecutor (primary executor for YAML skills via bridge shortcuts)
- URLSchemeExecutor

------------------------------------------------------------------------

## Per-Action Confirmation

Skills can specify confirmation behavior per action:

```yaml
- id: vehicle.frunk.open
  title: "Open Frunk"
  confirmation: required    # can't close via software
  ...

- id: vehicle.unlock
  title: "Unlock"
  confirmation: none        # no confirmation needed
  ...
```

Values: `required`, `none`, `destructive_only`. Actions marked `required` always prompt for user confirmation before execution.

------------------------------------------------------------------------

# 9. Plugin System (YAML Skills)

Skills are **content-only YAML files representing an integration/domain** (e.g., Tesla, TickTick, Hue).

Each skill is a single `skill.yaml` file containing:

- Skill metadata (ID, name, version)
- Bridge shortcut configuration (name, share URL)
- Actions with examples, negative examples, parameters, and shortcut arguments

Example:

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
      - unlock my tesla
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

### Skill Compilation

At install time (or on first launch), skills are compiled:

1. Parse YAML manifest
2. Detect source language of examples
3. Translate examples to all configured languages (Foundation Model)
4. Embed all examples (positive and negative) using the sentence transformer
5. Store compiled index to disk

The compiled index is cached and loaded instantly on subsequent launches. Recompilation is triggered by skill changes, language settings changes, or manual recompile from the Debug tab.

### Shortcut Arguments

The `shortcut_arguments` field defines the literal JSON payload sent to the bridge shortcut. Values with `{{placeholder}}` syntax are filled from Phase 2 parameter extraction at runtime.

### Phase 2: Parameter Extraction

Actions with `parameters` trigger a lean Foundation Model call using a dynamically generated `GenerationSchema`. Only the matched action's parameter schema is sent — not all skills. This keeps extraction fast (~1s) and accurate.

Actions without `parameters` skip Phase 2 entirely and execute immediately after vector matching.

### Validation Rules

- `skill_id` must be present and non-empty
- `actions` must be a non-empty list
- Each action must have a non-empty `id`
- Each action must have at least one example
- Capability IDs must match the pattern `word.word` (underscores allowed)

See [docs/skill-yaml-format.md](docs/skill-yaml-format.md) for the full format reference.

------------------------------------------------------------------------

# 10. Embedding Model

The app bundles **paraphrase-multilingual-MiniLM-L12-v2**, a 384-dimensional sentence transformer supporting 50+ languages. The model is converted to Core ML format (~224MB) and runs on the Neural Engine.

The embedding system uses the `EmbeddingBackend` protocol, allowing the model to be swapped without code changes. If the bundled model fails to load, the system falls back to Apple's NLEmbedding.

A custom Unigram (SentencePiece) tokenizer processes input text using a Viterbi algorithm to find the optimal tokenization based on token log-probabilities.

------------------------------------------------------------------------

# 11. Multilingual Support

Multilingual routing works through two mechanisms:

1. **Compile-time translation**: When users configure additional languages, the Foundation Model translates all skill examples. Both original and translated examples are embedded in the index.

2. **Multilingual embedding model**: The bundled paraphrase-multilingual-MiniLM supports 50+ languages natively. Commands in different languages map to similar vector regions.

Users configure languages in Settings. Adding or removing a language triggers recompilation of the skill index.

Known limitation: automated translation produces literal translations that may not match natural phrasing in the target language. Community-contributed skill files with native examples are preferred for production quality.

------------------------------------------------------------------------

# 12. Skill Repositories

Skills can be distributed through repositories.

Supported repository types:

-   HTTP index
-   GitHub repository
-   local folder

Users can add custom repositories.

------------------------------------------------------------------------

# 13. Storage

Local storage stores events and installed skills.

Entities:

- DispatchEvent (timestamp, raw_input, router_plan, provider, parameters, result)
- InstalledSkill
- RepositorySource
- CompiledIndex (cached to Application Support, versioned with schemaVersion)

------------------------------------------------------------------------

# 14. Safety Model

Execution policies:

- LocalLogExecutor → auto-run
- System providers → confirmation for destructive actions
- URL scheme execution → confirmation required
- Shortcuts execution → per-action confirmation (configurable in YAML)
- Actions with `confirmation: required` → always prompt

Provide dry-run mode for testing new skills.

Bridge shortcut installation and updates must always be user-approved through Shortcuts. The app provides guided install flows with iCloud share URLs.

------------------------------------------------------------------------

# 15. UI Requirements

SwiftUI app screens:

Home

-   listen button
-   text input
-   recent history

Skill Manager

-   list installed skills
-   import skill packs
-   validation errors
-   bridge shortcut install flow with share URL

Settings

-   backend selection (Rule-Based / Apple Foundation / Compiled Embedding)
-   escalation toggle
-   dry-run mode
-   provider preferences
-   language configuration (triggers recompilation)

Debug Screen

-   Compiled index inspector (entry count, skill breakdown, drill-in to actions)
-   Match candidates with confidence scores and confidence gap indicator
-   Per-action detail: examples, negative examples, compiled embeddings per language
-   RouterPlan JSON
-   Execution logs
-   Bridge shortcut install button

------------------------------------------------------------------------

# 16. Action Button Integration

Add AppIntent:

DispatchCommandIntent

Purpose:

Launch OpenDispatch capture screen from Action Button.

AppIntent must call RouterCore.

------------------------------------------------------------------------

# 17. Quality Requirements

Include:

-   SwiftLint configuration
-   swift-format configuration
-   unit tests

Test coverage required for:

-   RouterCore (CompiledIndex, MatchCandidate, cosine distance, negative penalties)
-   CapabilityRegistry
-   SkillRegistry YAML parsing and validation
-   SkillCompiler (compile pipeline, embedding, end-to-end routing)

------------------------------------------------------------------------

# 18. Privacy Model

OpenDispatch is **local-first by default**.

Guarantees:

-   All routing runs on-device via compiled embeddings
-   Phase 2 parameter extraction uses the on-device Foundation Model (no network)
-   No data leaves the device unless user enables escalation
-   All logs stored locally
-   Plugins cannot execute code
-   The bundled sentence transformer runs entirely on-device

------------------------------------------------------------------------

# 19. Future Iterations

Planned future capabilities:

-   Downloadable multilingual models (e5-base, larger models)
-   User-editable examples with recompilation
-   Fine-tuned embedding model for short command discrimination
-   Advanced routing heuristics
-   Multi-step plans
-   Mac version
-   Richer integrations

------------------------------------------------------------------------

# 20. Success Criteria (MVP)

The MVP is successful if users can:

1.  Trigger OpenDispatch from Action Button.
2.  Speak or type a command.
3.  See a RouterPlan generated with match candidates.
4.  Execute an action locally via a bridge shortcut.
5.  Install a YAML skill pack.
6.  View history of executed commands.
7.  Install a bridge shortcut via the guided install flow.
8.  Inspect compiled embeddings and match candidates in the Debug screen.
9.  Configure languages and trigger skill recompilation.
10. Use negative examples to prevent misrouting.
