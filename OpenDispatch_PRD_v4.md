# OpenDispatch --- Product Requirements Document (PRD)

Version: 0.1 MVP Project: OpenDispatch Website: https://opendispatch.ai
Status: MVP Specification

------------------------------------------------------------------------

# 1. Overview

OpenDispatch is a **local-first command router for iPhone** that
interprets natural language commands and dispatches structured actions
to apps.

Unlike AI chat assistants, OpenDispatch focuses on **deterministic
action routing**, not conversation.

Users trigger OpenDispatch primarily via the **iPhone Action Button**,
voice input, or text input.

The system converts an utterance into a **structured RouterPlan**,
selects the appropriate provider, executes the action safely, and logs
the event locally.

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

-   Add buy milk
-   Log coffee
-   Add task buy groceries
-   Create reminder call mom tomorrow
-   Open Notion inbox

The system interprets the request and dispatches the appropriate action.
If the user so chooses, complex requests and requests that cannot be matched
can still be routed to Apple Intelligence, or another cloud-based LLM provider (escalation).

OpenDispatch combines:

-   natural language input
-   deterministic capability routing
-   safe automation execution

------------------------------------------------------------------------

# 4. Goals

Primary goals for MVP:

1.  Enable natural language command routing.
2.  Work offline for core features.
3.  Execute actions through deterministic capabilities.
4.  Support extensibility through skill packs.
5.  Maintain App Store compliance.
6.  Provide clear debugging visibility.

Secondary goals:

-   support skill repositories
-   enable external integrations
-   provide safe execution policies

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
→ system interprets request\
→ router generates RouterPlan\
→ provider executes action\
→ result displayed\
→ event logged locally

Example:

User says: "add buy milk"

System resolves:

Capability: task.create\
Provider: Apple Reminders\
Executor: AppleRemindersExecutor

Action executed successfully.

------------------------------------------------------------------------

# 7. System Architecture

High-level pipeline:

User Input\
↓\
RouterRequest\
↓\
ModelRuntime (rule-based or AI backend)\
↓\
RouterPlan\
↓\
CapabilityRegistry\
↓\
Provider Selection\
↓\
Executor\
↓\
ExecutionResult\
↓\
Local Event Storage

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
- routing  

RouterPlan must support routing hints.

Example:

{
capability: "task.create",
parameters: {
title: "Buy milk"
},
routing: {
domain: "grocery",
list_hint: "groceries",
audience: "shared"
},
confidence: 0.93
}

Routing hints help the system select the correct provider.

--------

## Destination Resolver

Add a component:

DestinationResolver

Responsibilities:

- map routing hints to providers
- map routing hints to concrete destinations within a provider
- apply user preferences
- apply heuristic classification
- validate required destination parameters
- prompt user if ambiguous

Destination resolution must happen at two levels:

1. cross-provider resolution
2. intra-provider destination resolution

This is MVP-critical.

Examples:

- task.create → TickTickProvider → Groceries list
- task.create → AppleRemindersProvider → Personal list
- task.create → AppleRemindersProvider → Work list

Example resolution logic:

If routing.domain == "grocery"
→ TickTickProvider / Groceries list

Else if routing.domain == "personal"
→ AppleRemindersProvider / Personal list

Else
→ default provider + default destination for task.create


------------------------------------------------------------------------

## Capability

Capabilities represent the **type of action requested**.

Examples:

-   log.event
-   task.create
-   task.complete
-   note.create
-   calendar.event.create
-   shortcut.run
-   url.open

Capabilities are **stable, canonical identifiers**.

------------------------------------------------------------------------

## Provider

Providers implement capabilities.

Examples:

AppleRemindersProvider\
AppleNotesProvider\
TickTickProvider\
NotionProvider

Providers map capabilities to executors.

Providers may expose one or more concrete destinations/targets within the provider.

Examples:

- Apple Reminders → Personal, Work
- TickTick → Groceries, Household, Inbox

For MVP, providers that require a destination to execute an action must expose destination descriptors that the DestinationResolver can target.

------------------------------------------------------------------------

## Destination Descriptor

A destination is a concrete target inside a provider.

Examples:

- TickTick / Groceries
- TickTick / Shared Household
- Apple Reminders / Personal
- Apple Reminders / Work

Destination descriptor fields:

- destination_id
- destination_label
- provider_id
- capability
- required_parameters
- aliases
- is_default

Some actions cannot execute without a destination.

Example:

TickTick add task requires a list input. Therefore, `task.create` for TickTick is incomplete until a concrete list destination has been resolved.

RouterPlan and resolution state must be able to represent provider selection separately from destination selection.

------------------------------------------------------------------------

## Executor

Executors perform the actual action.

Executors are built into the app and cannot be extended with code.

Examples:

LocalLogExecutor\
ShortcutsExecutor\
URLSchemeExecutor


-----------

## Destination Resolution

Some capabilities may have multiple valid providers and multiple valid destinations inside a provider.

Example:

Capability:

task.create

Possible providers:

AppleRemindersProvider
TickTickProvider

Possible destinations:

Apple Reminders / Personal
Apple Reminders / Work
TickTick / Groceries

The system must resolve which destination the task belongs to.

Destination resolution occurs after RouterPlan generation but before provider execution.

This includes intra-provider destination selection. Provider-level resolution alone is not sufficient for MVP.

For example, selecting TickTickProvider without selecting a concrete list is incomplete if the underlying shortcut or app action requires a list parameter.

---------

## User Preferences

Users can configure destination rules.

Example: (capability + domain)

tasks.create.personal → Apple Reminders / Personal
tasks.create.grocery → TickTick / Groceries
tasks.create.work → Apple Reminders / Work

Preferences are stored locally.

Preferences must support both:

- default provider per capability/domain
- default destination within a provider

----

## Ambiguity Handling

If the router cannot determine a destination:

- prompt the user
- execute the selected provider/destination
- optionally learn the preference for future commands

Example:

"Add to Groceries or Personal?"

Example

Input:

add milk

RouterPlan:

capability: task.create
parameters.title: Buy milk
routing.domain: grocery

Resolver:

grocery → TickTick / Groceries

Execution:

TickTickProvider
destination: Groceries
URLSchemeExecutor

Ambiguity can happen at both levels:

- provider ambiguity
- destination ambiguity within a chosen provider

------------------------------------------------------------------------

# 9. Plugin System (Skill Packs)

Plugins are **content-only skill packs representing an integration/domain (e.g., Tesla, Hue, TickTick)**.

Each skill pack contains:

-   skill.json (machine manifest)
-   SKILL.md (human description)

Example manifest:

{
  "skill_id": "tesla",
  "version": "1.0.0",
  "bridge_shortcut": {
    "name": "OpenDispatch - Tesla",
    "version": "1.0.0",
    "install_url": "https://www.icloud.com/shortcuts/...",
    "input_format": "json"
  },
  "actions": [
    {
      "action": "vehicle.climate.start",
      "params_schema": {
        "vehicle": "string"
      }
    },
    {
      "action": "vehicle.lock",
      "params_schema": {
        "vehicle": "string"
      }
    }
  ]
}

Validation rules:

-   capability must exist
-   executor must exist
-   schema must validate

Skill packs may optionally include a bridge shortcut definition for third-party integrations executed through Shortcuts.

Bridge shortcuts operate as **execution runtimes for the skill integration**.

Each integration skill should expose **multiple actions**, and the bridge shortcut must accept a JSON payload describing the action to execute.

OpenDispatch serializes RouterPlan output into a JSON payload and sends it as the text input to the shortcut.

Example payload:

{
  "schema_version": 1,
  "skill_id": "tesla",
  "skill_version": "1.0.0",
  "action": "vehicle.climate.start",
  "params": {
    "vehicle": "default"
  }
}

Inside the shortcut, scripting actions parse the JSON and branch based on the `action` field to run the correct automation steps.


Bridge shortcut metadata must be versioned separately from the skill itself.

Required bridge shortcut metadata fields:

-   bridge_shortcut_required (boolean)
-   bridge_shortcut_name
-   bridge_shortcut_version
-   bridge_install_url
-   bridge_setup_instructions
-   bridge_input_template
-   upgrade_notes

The app must treat bridge shortcuts as user-installed runtime dependencies, not as app-managed code.

------------------------------------------------------------------------

# 10. Skill Repositories

Skills can be distributed through repositories.

Example repository index:

{ "repository": "OpenDispatch Official", "skills": \[ { "name":
"ticktick_add_task", "path": "ticktick/add-task" } \] }

Supported repository types:

-   HTTP index
-   GitHub repository
-   local folder

Users can add custom repositories.

Repository indexes should support version metadata for both skills and bridge shortcut artifacts so the app can detect updates and present guided migration flows.

------------------------------------------------------------------------

# 11. Storage

Local storage stores events and installed skills.

Entities:

DispatchEvent\
InstalledSkill\
RepositorySource\
BridgeShortcutInstall

BridgeShortcutInstall fields:

-   skill_id
-   installed_skill_version
-   expected_bridge_shortcut_name
-   expected_bridge_shortcut_version
-   install_status
-   last_verified_at
-   requires_manual_cleanup

DispatchEvent fields:

-   timestamp
-   raw_input
-   router_plan
-   provider
-   parameters
-   result

Queries supported:

-   recent events
-   search events

------------------------------------------------------------------------

# 12. Skill Versioning and Bridge Shortcut Lifecycle

Skills must be versioned.

Required skill versioning fields:

-   skill_id
-   version
-   min_app_version
-   upgrade_notes

Bridge shortcuts must also be versioned independently because bridge logic may change without a corresponding capability change.

Examples:

-   skill_id: tesla
-   skill version: 1.3.0
-   bridge shortcut version: 2.0.0

The app must track local install state for both skill packs and their bridge shortcuts.

Bridge shortcut install states:

-   not_installed
-   installed
-   update_available
-   requires_manual_cleanup

Update flow for shortcut-backed skills:

1.  OpenDispatch detects a newer skill version or bridge shortcut version.
2.  If the bridge shortcut version changed, the app marks the currently configured bridge as outdated.
3.  The app presents a guided update flow with:
    -   install updated bridge shortcut
    -   verify installed shortcut name/version
    -   switch active binding to the new shortcut
    -   show manual cleanup instructions for the old shortcut
4.  The app must not assume it can delete or replace user shortcuts automatically.

For bridge shortcut updates, the system may temporarily use versioned human-readable names to avoid ambiguity during migration.

Example:

-   OpenDispatch - Tesla Climate
-   OpenDispatch - Tesla Climate v2

The product must include a guided cleanup screen that helps users remove obsolete shortcuts manually in the Shortcuts app.

Shortcut-backed skills are considered user-approved bridge integrations, not native app integrations.


------------------------------------------------------------------------

# 13. Safety Model

Execution policies:

LocalLogExecutor → auto-run\
System providers → confirmation for destructive actions\
URL scheme execution → confirmation required\
Shortcuts execution → confirmation required

Provide dry-run mode for testing new skills.

Bridge shortcut installation and updates must always be user-approved through Shortcuts. OpenDispatch may guide the user, but must not silently install, overwrite, or remove shortcuts.

------------------------------------------------------------------------

# 14. UI Requirements

SwiftUI app screens:

Home

-   listen button
-   text input
-   recent history

Skill Manager

-   list installed skills
-   import skill packs
-   validation errors
-   bridge shortcut install/update status
-   guided setup and cleanup instructions

Settings

-   backend selection
-   escalation toggle
-   provider preferences
-   destination preferences

Debug Screen

-   RouterPlan JSON
-   execution logs

------------------------------------------------------------------------

# 15. Action Button Integration

Add AppIntent:

DispatchCommandIntent

Purpose:

Launch OpenDispatch capture screen from Action Button.

AppIntent must call RouterCore.

------------------------------------------------------------------------

# 16. Quality Requirements

Include:

-   SwiftLint configuration
-   swift-format configuration
-   unit tests

Test coverage required for:

-   RouterCore
-   CapabilityRegistry
-   SkillRegistry validation

------------------------------------------------------------------------

# 17. Privacy Model

OpenDispatch is **local-first by default**.

Guarantees:

-   no data leaves the device unless user enables escalation
-   all logs stored locally
-   plugins cannot execute code

------------------------------------------------------------------------

# 18. Future Iterations

Planned future capabilities:

-   MLX local model backend
-   llama.cpp runtime backend
-   advanced routing heuristics
-   multi-step plans
-   Mac version
-   richer integrations

------------------------------------------------------------------------

# 19. Success Criteria (MVP)

The MVP is successful if users can:

1.  Trigger OpenDispatch from Action Button.
2.  Speak a command.
3.  See a RouterPlan generated.
4.  Execute an action locally.
5.  Install a skill pack.
6.  View history of executed commands.
7.  Install or update a shortcut-backed skill with a guided bridge shortcut flow.
8.  Resolve commands that require a concrete destination within a provider, such as choosing the correct TickTick list or Reminders list.
