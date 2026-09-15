# P1 Custom Status Runtime Overlay Unification

## Git / code baseline

- Start HEAD: `670bd5e3efb4c87a7f3444a5966fc74ee67b2399`
- `origin/main`: `670bd5e3efb4c87a7f3444a5966fc74ee67b2399`
- Worktree at audit start: clean
- Baseline `flutter analyze`: no issues

## Confirmed root cause

`ChatEngine` parses `custom_status_evaluations` (authoritative) and legacy
`custom_status_changes`, then `_projectPendingCustomStatus` uses
`CustomStatusMerger` to produce an effective `AdventureConfig`. The dialogue
transaction persists messages, effects, scene state and the existing runtime
draft, but after that transaction succeeds `_commitPendingCustomStatus` calls
`updateAdventureConfig`. `baselineForPersistence` strips only affinity,
relationship and life status overlays, so the custom attribute values are
written into `adventures.config`.

Consequences:

- narrative turns mutate the frozen baseline;
- all branches observe the same persisted custom values;
- custom changes have no Runtime HEAD revision, before/after record, parent or
  request provenance;
- a restart restores the mutated config rather than branch-local runtime state.

## Design

Custom attribute definitions and initial values remain in the frozen
`AdventureConfig`. Current values live in the existing character runtime
entity overlay under the validated path
`custom_attributes.<attribute identity>`. The entity ID is the stable
supporting-character ID or the adventure protagonist ID (falling back to the
reserved `protagonist` identity for legacy adventures).

The character entity is used instead of one entity per attribute because it
already owns affinity, relationship and life status; it is already copied at
fork, restored from HEAD, and persisted atomically. No table or database
version change is required.

Dynamic paths are accepted only through a dedicated namespace parser. The
repository validates the path against the target character's frozen custom
attribute definitions, validates numeric/text type and bounds, and applies the
operation through `RuntimeStateValidator`. A wildcard is not added to the
static allow-list.

Legacy saves need no eager rewrite. If an overlay value is absent, the
resolver uses the frozen legacy `value/currentValue` as the initial value. The
first real change creates or updates the character runtime entity.

## Commit flow

```text
LLM response
  -> evaluation / legacy delta parse and deduplication
  -> CustomStatusMerger validation and effective projection
  -> custom runtime proposals with reason
  -> RuntimeStateCommitDraft
  -> SceneDialogueCommit transaction
  -> State Commit + changes + character overlay + Runtime HEAD
```

The assistant message custom-status snapshot is derived from the projected
effective config before the transaction, but remains historical display data.
The transaction is the only state mutation. Provider refresh reloads runtime
entities and `AdventureRuntimeStateResolver` supplies effective values to the
prompt and current-state UI.

## Modification scope

- Runtime path model and validator.
- Baseline/overlay resolver.
- ChatEngine custom status projection to runtime draft conversion.
- Repository atomic runtime application and provenance.
- Provider/runtime effective reads where required.
- Focused unit/integration regression tests and runtime architecture docs.

## Forbidden scope

- No custom-status table or unrelated schema migration.
- No Narrative Beat, length budget, Resource Library, or broad UI redesign.
- No removal of evaluation diagnostics or legacy protocols.
- No commit-log replay for normal current-state reads.

## Required verification

- Frozen config unchanged after repeated and 50+ turn updates.
- Overlay and prompt effective values advance across turns.
- Runtime commit before/after, reason, request, parent and revision are correct.
- Forked branches diverge without baseline or sibling pollution.
- Repository/provider recreation restores the branch HEAD value.
- Evaluation protocol remains authoritative; legacy delta/snapshot remains
  compatible; no-visible-change and invalid targets keep diagnostics.
- Existing atomicity tests, focused runtime/custom-status tests,
  `flutter analyze`, full `flutter test`, formatting and diff checks pass.
