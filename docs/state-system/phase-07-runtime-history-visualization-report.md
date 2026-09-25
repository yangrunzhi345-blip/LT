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

`RuntimeEffectiveStateView` combines the frozen `AdventureConfig` baseline with
a replayed snapshot through `AdventureRuntimeStateResolver`. It is a read-only
presentation object and is never persisted. The comparison model is also pure
and read-only.

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

The State Hub can save the captured current revision, and timeline entries can
save historical revisions. Checkpoint list/detail navigation exposes metadata
editing, compare-current, delete-marker, and revert-preview actions.

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

## 15. Character History

The existing entity filter remains repository-side and can be reused by
character history navigation.

## 16. World History

World, location, and faction history use the same timeline query contract.

## 17. Initial / Current / Historical

Current is the runtime HEAD projection, historical is replay at a revision, and
the existing initial card remains the frozen adventure baseline summary.

## 18. Compare UI

Compare is navigation-first and displays grouped entity fields with an explicit
FROM → TO direction.

## 19. Snapshot UI

Save Snapshot is available from current State Hub and historical Timeline Detail.

## 20. Revert Integration

Timeline and checkpoint detail both open the same expected-revision CAS revert
preview; revert remains append-only.

## 21. Branch Isolation

Checkpoint reads and writes include both adventure and branch identifiers.

## 22. Pagination

Timeline uses `beforeRevision`; checkpoint reads are bounded and revision-sorted.
Filters are applied in SQL before the commit limit.

## 23. Performance

Timeline cells use already-loaded diffs/events and do not replay snapshots.
Checkpoint lists load metadata only.

## 24. Localization

New State History, Compare, Snapshot, HEAD, and Checkpoint labels were added to
all six ARB locales and generated through Flutter localization tooling.

## 25. Responsive

The existing 320px State Hub regression remains green; detail/list pages use
constrained columns and flexible text. Full matrix coverage remains follow-up.

## 26. Migration

Schema v45 → v46 creates `runtime_state_checkpoints` and indexes idempotently,
without rewriting existing history rows.

## 27. Tests

Pure comparison tests cover direction, grouping, no-op comparisons, and path
presence semantics.

## 28–33. Stress, guards, audits, and remaining debt

The existing bounded timeline query and replay APIs remain the performance and
authority guards. The 1000-revision stress fixture now verifies bounded timeline
and checkpoint pages plus a two-revision comparison. Full responsive viewport
matrix coverage remains follow-up work.

## Verdict

Phase 7 core history read model and named checkpoint contract are implemented,
but the full acceptance gate is not met. Remaining work includes the full
responsive viewport matrix and deeper integration coverage for all locales.

**Phase 7: FAILED**
