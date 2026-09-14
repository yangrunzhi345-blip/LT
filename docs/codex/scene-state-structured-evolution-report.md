# SceneState structured evolution report

## Root cause

Before this change, `ChatEngine` persisted the prompt-projected SceneState and
only replaced its location from `GameState.currentScene`; present characters
were intersected with pre-existing host presence. Time, character movement, and
goal lifecycle had no structured response-to-state path.

## Data flow and proposal

`scene_state_changes` is an optional payload object:

```json
{
  "location": "王宫",
  "time": "深夜",
  "characters_enter": ["boris"],
  "characters_leave": ["eileen"],
  "goals_add": [{"id":"audience","description":"拜见女王"}],
  "goals_update": [{"id":"audience","status":"resolved"}],
  "goals_remove": ["audience"]
}
```

The flow is: LLM payload → tolerant proposal parser → staged
`SceneDialogueCommit` → transaction applies Runtime draft → SceneState proposal
validator → GameState location synchronization + SceneState write. No parsing
step mutates the host. Duplicate requests return the persisted turn unchanged.

## Validation and ownership

The validator locally ignores malformed fields, bad IDs, unknown/dead/repeated
entrants, absent leavers, enter/leave conflicts, duplicate goals and missing
goal updates/removals, recording diagnostics in turn diagnostics. Frozen cards
are not writable through the proposal. Runtime HEAD remains owner of lifecycle;
after the transaction applies Runtime changes, dead character entry is refused.
SceneState owns only current location/time/presence/goals; GameState owns RPG
values and mirrors a successfully applied SceneState location.

## Compatibility and tests

The field is optional; old responses and saved SceneState rows remain valid and
need no migration. Added SQLite tests cover location sequence, time, multi-role
movement, goals, partial-invalid proposal handling, same-turn death conflict,
idempotency, and branch isolation. The existing 300-turn pressure test now
applies location/time/leave/goal changes through proposals, including the
death turn and branch divergence.

Validated targeted tests:

```text
flutter test test/unit/scene_state_structured_evolution_test.dart \
  test/unit/context_long_story_stress_test.dart
```

Remaining risk: a model can omit a delta even when prose describes a change;
the prompt now asks it to report genuine changes, but semantic prose extraction
is intentionally not added because it would create a second, non-deterministic
authority. Manual host presence updates remain a separate supported entry point.
