# Character & World State Phase 4 Report

## Baseline

- Start HEAD: `a1712d0dd714b5da9f18326dc0434ff869e06d66`
- `origin/main` matched HEAD at start.
- Database schema remains v44.

## Authority and mutation contract

User edits and reverts use `RuntimeStateMutation` and
`RuntimeStateCommitDraft`. The repository validates proposals, checks
`expectedRevision`, and writes the commit archive, changes, overlay, and
Runtime HEAD in one SQLite transaction.

## Append-only revert

Revert computes the current-to-target revision diff and writes a new commit
with `cause_type = revert`. It never changes HEAD to an old revision, deletes
commits, or removes later changes. The historical timeline remains intact.

## UI

Runtime entity cards expose a small edit form. Timeline details expose a
confirmation flow for revert. Both flows are read through the repository and
refresh by returning to the state hub; no direct SQL or writable snapshot was
added to presentation.

## Conflict and idempotency

Stale expected revisions throw `RuntimeHeadConflict`. Repeated mutation request
IDs return the already persisted commit and revision. Timeline and state reads
remain branch-scoped.

## Verification

- `flutter analyze`: passed.
- Runtime mutation, projection, dialogue runtime commit, and state hub widget
  tests: passed.
- New regression test covers user edit, stale CAS rejection, append-only
  revert, current-state projection, and preserved timeline history.

## Final Convergence

### MAJOR-1 — Shared mutation primitive

Dialogue turns and user edits now call the same repository runtime mutation
primitive. User edits and reverts do not construct `SceneDialogueCommit`, write
`messages`, or write `scene_dialogue_turns`; their provenance may omit a source
message and uses the mutation cause directly.

### MAJOR-2 — GameState compatibility atomic sync

Runtime overlay writes, runtime HEAD changes, and the protagonist compatibility
projection into `game_state` execute in one SQLite transaction. A projection
failure rolls the complete mutation back. Reverts use the same path.

### MAJOR-3 — Navigation-first revert preview

Timeline detail now navigates to an independent revert preview page. The page
captures the current revision, shows the target revision and actual timeline
diffs, and confirms with the captured revision as a CAS. A stale confirmation
fails closed and offers reload.

### Regression tests

`runtime_mutation_test.dart` verifies CAS, append-only revert, GameState
projection, and the absence of dialogue artifacts. The runtime state hub widget
test continues to cover the 320 px layout.

### Final audit

Schema remains v44. The repository contains one runtime mutation implementation;
`commitRuntimeMutation` has no dialogue commit construction. Revert's main UI
flow contains no dialog or bottom sheet.

### Re-acceptance verdict

Phase 4 Status: ACCEPTED
Phase 5 readiness: READY
