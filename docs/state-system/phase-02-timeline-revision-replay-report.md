# Character & World State Phase 2 Report

## 1. Baseline

- Start HEAD: `02a62d4060d21518f43daa5f1ea5ec5c1f20ae43`
- `origin/main` matched HEAD at start.
- Database schema remains v44; worktree was clean.

## 2. Phase 1 contracts reused

Phase 2 reuses `RuntimeStateEvent`, `RuntimeStateDiff`,
`RuntimeEntityState`, stable entity/path IDs, typed provenance, and the existing
Runtime HEAD/overlay authority.

## 3. Runtime archive audit

The archive stores commit revision/parent ordering and each change's operation,
path, before, after, entity, and commit identity. This is sufficient for
deterministic replay without copying current overlays.

## 4. Replay contract

Replay applies the committed `after_json` value in ascending revision/change
order. A null after value removes the path. This deliberately does not reapply
the operation, preventing increment double-application. Lifecycle status is
derived from lifecycle and life status changes.

## 5. State-at-revision API

`getRuntimeStateAtRevision` reads only the requested Adventure/branch and changes
at or before the target revision. Optional entity type and entity ID filters are
applied in SQL. The returned `RuntimeStateSnapshot` is a read-only projection.

## 6. Timeline grouping

`RuntimeTimelineEntry` groups all changes belonging to one commit. The commit ID
and revision are the stable group identity; typed events and typed diffs remain
children of the group.

## 7. Timeline query API

`getRuntimeTimeline` supports Adventure, branch, revision cursor, entity filters,
event type filtering, and a bounded limit capped at 200.

## 8. Pagination

Timeline uses `beforeRevision` and descending revision order. SQL first selects a
bounded set of commit IDs, then loads all changes for those commits so one group
cannot be truncated by a per-change limit.

## 9. Diff projection

`getRuntimeStateDiffsForCommit` returns deterministic change-index ordered diffs.
Existing entity diff queries remain bounded and branch-scoped.

## 10. Snapshot projection

Snapshots contain Adventure, branch, target revision, and reconstructed overlay
entities. They never write the Runtime HEAD, overlay, resources, or baseline.

## 11. Legacy compatibility

Rows without valid typed event metadata remain readable by replay. Timeline marks
their commit group as `isLegacy` and does not invent an event type or event source.

## 12. Branch isolation

All replay, timeline, and diff SQL predicates include Adventure and branch. Tests
cover the same entity ID at the same revision on two branches.

## 13. Performance / indexes

Queries use existing commit revision and change commit indexes, SQL-side limits,
and revision cursors. No OFFSET or unbounded default query was added. No
checkpoint table is needed at this stage.

## 14. Migration

No schema changes were required; schema remains v44.

## 15. Tests

- `test/unit/runtime_projection_test.dart`: replay, remove, timeline grouping,
  cursor pagination, branch isolation, and legacy rows.
- Existing Phase 1 contract and runtime commit tests remain applicable.

## 16. Architecture guards

New APIs are read-only. No Timeline/Snapshot/Replay writer exists, and no read
model mutates Runtime HEAD, overlays, CharacterCard, or Worldview resources.

## 17. Audit Round 1

Authority audit passed: all new models are derived from the existing archive and
runtime authority.

## 18. Audit Round 2

Historical correctness audit passed for baseline-to-revision replay, removal,
typed event grouping, and legacy fallback.

## 19. Audit Round 3

Scale/isolation audit passed for bounded SQL, cursor pagination, Adventure/branch
scope, and schema-compatible legacy handling.

## 20. Remaining debt

Future work may add a richer baseline-aware effective-state read model and UI;
restore and timeline presentation remain out of scope.

## 21. Phase 3 readiness

The read APIs are ready for a Phase 3 presentation layer.

## Verdict

ACCEPTED for Phase 2 timeline projection, revision replay, and state read model.
