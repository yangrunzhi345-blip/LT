# Phase 7 — Runtime State History Visualization

## 1. Baseline

Phase 7 started at `5b3293b673cbb2d4ddfe783e2a58e91559b5419d`, equal to
`origin/main`, with a clean worktree and schema v45.

## 2. Existing History Architecture

Runtime mutations append rows to `adventure_state_commits` and
`adventure_state_changes`. `adventure_runtime_heads` stores the branch HEAD.
`getRuntimeStateAtRevision` replays the archive into a read-only snapshot and
`getRuntimeTimeline` reads bounded, cursor-based commit pages.

## 3. History Authority

The Runtime HEAD remains the current-state authority and the commit archive
remains the history authority. No second state store was introduced.

## 4. Snapshot Semantics

Snapshots are replay projections. Runtime checkpoints contain only an id,
branch, revision, name, note, and timestamps; they never copy state JSON.

## 5. Effective State Projection

The existing runtime snapshot remains the projection consumed by the UI. The
new comparison model is pure and read-only.

## 6. Revision Comparison

`RuntimeStateComparison.fromSnapshots` provides a shared FROM → TO diff model,
grouped by entity and preserving absent paths separately from present values.
Revert preview now uses this model instead of a private diff algorithm.

## 7. Dynamic Character Historical Semantics

No baseline values are guessed. Dynamic membership remains governed by the
existing Phase 6 membership persistence and resolver.

## 8. Runtime Checkpoint Contract

Checkpoint creation validates branch, revision range, and replayability.
Rename and note updates do not move the immutable target revision; deletion
removes only the marker.

## 9. Checkpoint Persistence

Schema v46 adds `runtime_state_checkpoints` with branch/revision indexes and no
state payload columns. The v45 → v46 migration is idempotent.

## 10. Timeline Read Model

Timeline entries now expose the persisted `cause_type` for presentation.

## 11. Git-style Visualization

Timeline detail exposes revision comparison and snapshot creation actions while
retaining the existing cursor-paginated history list.

## 12. HEAD Presentation

The current revision is still read from `getCurrentRuntimeState`/HEAD; no UI
operation moves HEAD.

## 13. Importance Presentation

Existing typed event importance remains available on timeline events and is not
recomputed by the new read model.

## 14. Legacy History

Legacy entries remain readable through the existing `isLegacy` flag.

## 15–26. Presentation, branch isolation, pagination, and migration

Checkpoint queries are branch-local and bounded. Timeline pagination remains
`beforeRevision` based, with filters applied inside the SQL commit selection.
Runtime and resource revisions remain separate.

## 27. Tests

Pure comparison tests cover direction, grouping, no-op comparisons, and path
presence semantics.

## 28–33. Stress, guards, audits, and remaining debt

The existing bounded timeline query and replay APIs remain the performance and
authority guards. Full UI localization and long-history stress coverage remain
follow-up work.

## Verdict

Phase 7 core history read model and named checkpoint contract are implemented;
the remaining acceptance work is tracked explicitly above.
