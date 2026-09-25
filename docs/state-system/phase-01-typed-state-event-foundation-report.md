# Character & World State Phase 1 Report

## 1. Baseline

- Start HEAD: `a7ee2147b2ff108bc7aa9382926e5dac0678c53b`
- `origin/main`: `27bec21e784284ea2be8867f9839a5f81abb9d9f`
- Branch: `main`; local HEAD is ahead of origin and was preserved.
- Database schema: v44. The worktree was clean at task start.

## 2. Existing runtime architecture

Runtime state is stored in `adventure_runtime_heads`, `adventure_runtime_entities`,
`adventure_state_commits`, and `adventure_state_changes`. Dialogue settlement
calls `_applyRuntimeDraft` inside the existing database transaction. Revision,
request ID, and expected revision already provide idempotency and stale-write
protection.

## 3. Authority decision

The runtime HEAD, commit archive, and entity overlay remain the sole current
state authority. Frozen Adventure/resource data remains the baseline. Events and
diffs are read models backed by committed changes.

## 4. Character state contract

`RuntimeStateSchemaRegistry` defines typed paths for numeric character values,
life/lifecycle state, relationships, faction and goals. Custom attributes remain
bounded by the existing AdventureConfig validator.

## 5. World state contract

The registry now covers `world`, `location`, `faction`, and `relationship`
entities with controlled paths such as `control`, `environment`, `condition`,
`influence`, `time`, and `global_flag`.

## 6. Typed value model

`RuntimeStatePathDefinition` validates integer, finite number, boolean, bounded
text, and stable enum values, including entity compatibility and numeric bounds.
Existing bounded JSON parsing remains fail-closed for untrusted proposals.

## 7. Event model

`RuntimeStateEvent` is immutable, schema-versioned, locale-neutral metadata bound
to a commit, revision, adventure, and branch. Event type IDs are derived by the
application from entity/path; model output cannot select the authoritative ID.

## 8. Diff model

`RuntimeStateDiff` exposes stable entity/path before/after values with commit,
revision, and source. No localized labels are persisted as identifiers.

## 9. Snapshot/projection model

The existing `AdventureRuntimeStateResolver` remains the read-only baseline plus
overlay projection. No current-state snapshot table or second resolver was added.

## 10. Persistence decision

Existing `adventure_state_changes.provenance_json` is extended with a typed event
object. This is append-only metadata and does not duplicate current state or
before/after storage.

## 11. Migration

No migration was required. Schema remains v44. Existing rows without typed event
metadata remain legacy records and are skipped by typed event/diff projections;
they are not guessed or reclassified.

## 12. Atomic transaction integration

Event metadata is generated while inserting each state change in `_applyRuntimeDraft`,
inside the same transaction that writes the commit, overlay, and HEAD.

## 13. Idempotency / stale-write

Existing unique `(adventure_id, branch_id, request_id)` and revision constraints,
plus expected-revision checks, remain in force. Retry and stale-write behavior is
unchanged and covered by existing runtime commit tests.

## 14. Branch isolation

Typed event and diff queries require adventure and branch IDs and use bounded
limits. They cannot read another Adventure or branch.

## 15. Tests

- `test/unit/typed_runtime_state_test.dart`: typed registry, validator, and event serialization.
- Existing runtime commit, custom overlay, and repository tests passed.
- `flutter analyze` passed for the changed implementation and tests.

## 16. Architecture guards

The implementation adds no current-state repository, event writer, resource
mutation path, UI dependency, or independent HEAD update path.

## 17. Audit Round 1

Authority review: passed. Runtime overlay/HEAD remains the only writable current
state model.

## 18. Audit Round 2

Atomicity review: passed. Event metadata is created with each committed change in
the existing transaction and carries the same commit/revision.

## 19. Audit Round 3

Long-term review: bounded typed values, stable IDs, bounded queries, branch scope,
and legacy provenance handling are in place.

## 20. Remaining debt

Phase 2 may add richer event grouping, revision snapshot replay, and user-facing
timeline/state pages. These are intentionally outside Phase 1.

## 21. Phase 2 readiness

The typed contracts and read APIs are ready for a timeline/read-model layer.

## Verdict

ACCEPTED for the Phase 1 typed state/event foundation. Full repository regression
should be run before publishing the final release commit.
