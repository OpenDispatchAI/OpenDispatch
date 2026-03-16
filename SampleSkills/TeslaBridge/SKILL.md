# Tesla Bridge

This sample shows the PRD-style shortcut-backed integration format.

What OpenDispatch does:
- classifies a command into one Tesla capability such as `vehicle.climate.start`
- selects the Tesla provider
- sends one JSON payload into the bridge shortcut `OpenDispatch - Tesla`

Expected shortcut input:

```json
{
  "schema_version": 1,
  "skill_id": "tesla",
  "skill_version": "1.0.0",
  "action": "vehicle.climate.start",
  "params": {
    "vehicle": "default"
  }
}
```

How to build the shortcut:
1. Create a shortcut named `OpenDispatch - Tesla`.
2. Set it to accept `Text` input.
3. Parse the incoming JSON into a dictionary.
4. Read `action`.
5. Read `params.vehicle` if present.
6. If `vehicle` is missing, fall back to a default vehicle stored in the shortcut.
7. Branch on `action` and call the corresponding Tesla app shortcut action.

Recommended first branches:
- `vehicle.climate.start`
- `vehicle.lock`
- `vehicle.unlock`

Notes:
- The app currently routes actions and passes JSON, but vehicle selection can still be handled inside the shortcut.
- Add more Tesla capabilities by appending new `actions` entries with distinct keywords and examples.
