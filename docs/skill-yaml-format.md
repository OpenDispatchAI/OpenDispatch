# Skill YAML Format

OpenDispatch skills are defined as YAML files. Each file describes a single integration (e.g., Tesla, TickTick, Hue) with one or more actions that users can trigger via natural language.

## File Location

Skills are loaded from:
- **App bundle** — bundled `.yaml` files included in the Xcode target
- **SampleSkills directory** — `SampleSkills/<SkillName>/skill.yaml` during development

## Minimal Example

```yaml
skill_id: tesla
name: Tesla
version: 1.0.0
bridge_shortcut: "OpenDispatch - Tesla"

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
```

## Top-Level Fields

| Field | Required | Type | Description |
|---|---|---|---|
| `skill_id` | Yes | string | Unique identifier for the skill. Used as the provider ID throughout the system. |
| `name` | No | string | Human-readable display name. Defaults to `skill_id` if omitted. |
| `version` | No | string | Semantic version. Defaults to `0.0.0`. |
| `built_in` | No | bool | `true` for core capabilities shipped with the app (Apple Reminders, Notes, etc.). Defaults to `false`. |
| `bridge_shortcut` | No | string | Name of the Apple Shortcut that executes this skill's actions. Required for external (non-built-in) skills. |
| `bridge_shortcut_share_url` | No | string | iCloud share URL for installing the bridge shortcut. |

## Actions

Each skill has one or more actions. An action represents a single thing the user can do.

```yaml
actions:
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
      - set cabin temperature to 22
```

### Action Fields

| Field | Required | Type | Description |
|---|---|---|---|
| `id` | Yes | string | Unique action identifier within the skill. Also used as the capability ID for routing. |
| `title` | No | string | Human-readable action name (e.g., "Unlock", "Start Climate"). Defaults to `id`. |
| `description` | No | string | What this action does. Used for display and potentially for AI-assisted example generation in the future. |
| `shortcut_arguments` | No | map | Literal JSON payload sent to the bridge shortcut when this action executes. Keys with `{{placeholder}}` values indicate fields that need runtime extraction. |
| `parameters` | No | list | Parameters that need to be extracted from user input at runtime (Phase 2). If absent or empty, the action executes immediately without LLM extraction. |
| `examples` | Yes | list | Natural language phrases that should trigger this action. These are the core of the routing system — they get embedded as vectors during compilation. **At least one example is required.** |

### Parameters

Parameters define values that must be extracted from user input before execution. Actions without parameters skip the extraction step entirely (faster execution).

```yaml
parameters:
  - name: temperature
    type: number
    description: "Target temperature in degrees"
    required: true
  - name: unit
    type: string
    description: "Temperature unit (celsius or fahrenheit)"
    required: false
```

| Field | Required | Type | Description |
|---|---|---|---|
| `name` | Yes | string | Parameter name, used as the key in the extracted values. |
| `type` | No | string | Parameter type (`string`, `number`, `date`). Defaults to `string`. |
| `description` | No | string | Describes the parameter for the extraction model. |
| `required` | No | bool | Whether this parameter must be present for execution. Defaults to `true`. |

### Shortcut Arguments

The `shortcut_arguments` field is the literal JSON payload sent to the bridge shortcut. For actions without parameters, this is sent as-is:

```yaml
shortcut_arguments:
  action: vehicle.unlock
  vehicle: default
```

For actions with parameters, use `{{placeholder}}` syntax to indicate values that get filled in from extracted parameters:

```yaml
shortcut_arguments:
  action: vehicle.climate.set_temperature
  vehicle: default
  temperature: "{{temperature}}"
```

## Writing Good Examples

Examples are the most important part of a skill definition. They determine how accurately the compiled embedding router matches user commands to actions.

### Guidelines

- **Write 3-8 examples per action.** More examples improve matching accuracy, but diminishing returns after ~10.
- **Vary the phrasing.** Include different ways a real person might say the same thing: "unlock my car", "open the car", "unlock the tesla".
- **Include brand-specific phrases** if the skill is for a specific product. "Unlock the tesla" helps disambiguate from a competing "Polestar" skill.
- **Keep examples short.** These mirror spoken commands — "unlock my car" not "I would like you to please unlock my car for me".
- **Don't overlap with other actions.** If both "Start Climate" and "Stop Climate" exist, make sure examples are distinct. "Turn on the AC" vs "turn off the AC".
- **Think multilingual.** If your users speak multiple languages, the compile step can translate examples. But starting with good native-language examples produces the best results.

### What Happens to Examples

During compilation, each example gets converted into a numerical vector (embedding) using Apple's NLEmbedding framework. At runtime, the user's spoken command is also converted to a vector, and the system finds the closest match using cosine similarity.

This means:
- Examples don't need to match exactly — "open my car" will match "unlock the car" because they're semantically similar.
- More diverse examples create better coverage of the semantic space around an action.
- Brand names and specific nouns ("tesla", "frunk") are powerful disambiguators.

## Built-in Skills

Core capabilities ship as YAML with `built_in: true`. They use native code execution paths instead of bridge shortcuts, so they don't have `bridge_shortcut` or `shortcut_arguments` fields:

```yaml
skill_id: apple_reminders
name: Apple Reminders
version: 1.0.0
built_in: true

actions:
  - id: task.create
    title: "Create Task"
    description: "Create a new reminder in Apple Reminders"
    parameters:
      - name: title
        type: string
        required: true
    examples:
      - add milk
      - remind me to call mom
      - buy groceries tomorrow
```

## Validation Rules

The YAML parser enforces:
- `skill_id` must be present and non-empty.
- `actions` must be a non-empty list.
- Each action must have a non-empty `id`.
- Each action must have at least one example.

Invalid files are skipped during compilation with a log message.

## Full Example: Tesla Skill

See `SampleSkills/TeslaBridge/skill.yaml` for a complete 16-action skill covering vehicle unlock/lock, climate control, charging, sentry mode, trunk/frunk, horn, lights, and windows.
