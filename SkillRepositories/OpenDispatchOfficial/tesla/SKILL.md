# Tesla Bridge

This skill routes Tesla actions through one bridge shortcut named `OpenDispatch - Tesla`.

Supported actions:
- `vehicle.climate.start`
- `vehicle.lock`
- `vehicle.unlock`

Shortcut contract:
- input type: `Text`
- input format: JSON
- required top-level fields: `skill_id`, `skill_version`, `action`, `params`

Recommended shortcut structure:
1. Parse the incoming JSON.
2. Read `action`.
3. Read `params.vehicle` when present.
4. Fall back to a default Tesla vehicle when `vehicle` is missing.
5. Branch to the corresponding Tesla app shortcut action.

Current limitation:
- OpenDispatch routes the Tesla action and passes JSON, but vehicle selection can still be handled inside the shortcut for now.
