# Adventure Runtime State

An Adventure has immutable source data and a branch-local runtime overlay.
Resource Library assets, `AdventureConfig` snapshots, selected character cards,
and worldview snapshots are frozen baseline; narrative output must not modify
them. `SceneState` remains short-lived scene truth and `GameState` remains RPG
mechanics only.

## Storage and writes

Database v28 adds `adventure_runtime_heads`, `adventure_runtime_entities`,
`adventure_state_commits`, and `adventure_state_changes`. A Runtime HEAD stores
the current revision and commit; entities store only changed fields. Commits
retain before/after values, request ID, context snapshot, assistant-message
reference, reason, parent commit and revision. The dialogue transaction writes
messages, RPG effects, SceneState, Runtime Commit, Overlay and HEAD together.
The request ID makes retries idempotent; expected revision prevents silent
last-write-wins conflicts.

Legacy affinity/death output is adapted to runtime proposals. Older saves keep
their current config as the upgrade boundary; no fictional historical commits
are created.

## Reads, branches and context

`AdventureRuntimeStateResolver` is the sole baseline-plus-overlay resolver for
effective character state. It exposes runtime death, affinity and relationship
to presentation while stripping overlays before a config edit is persisted.
Forking copies only the current HEAD/overlays; subsequent branches diverge.
Archive commits are retained when deleting a branch to preserve provenance.

`RuntimeMemoryProjector` passes relevant overlays only (at most eight entities
and 600 tokens) through the existing `ContextOrchestrator`. Runtime HEAD takes
priority over frozen facts. Archive lookup is only enabled for explicit history
or cause questions and is bounded to five facts. Conversation summaries may be
trimmed, but State Commit Archive is authoritative and is never summary-cleaned.

## Scope

Primary changes are direct narrative facts; derived changes require deterministic
rules and provenance. The first version intentionally excludes checkpoint UI,
merge/rebase/cherry-pick/rollback, graph/vector databases, a secret-knowledge
graph, and autonomous impact analysis. Visibility is stored as `internal` now
and is reserved for future extension.
