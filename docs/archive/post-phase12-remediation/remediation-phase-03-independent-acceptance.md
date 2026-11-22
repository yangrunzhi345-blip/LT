# R03 Independent Acceptance Report

## 1. Baseline

```text
Acceptance Date: 2026-09-19
Acceptance HEAD: 93ce815a9eb4357a99754c6fe828ede02099189e
origin/main: 93ce815a9eb4357a99754c6fe828ede02099189e
Branch: main
Ahead / Behind: 0 / 0
Working Tree Before Acceptance Docs: clean
R03 Start HEAD: 9566d3137433593ec7de93068eb4271f3fafbdb4 (R02 end)
R03 Implementation Commits:
  35c201fd6287814077041e44aa997f6410efd724  revision lifecycle gate
  e128b0e4a7577b83216ca5d9ab38ebc2f8dcbe9c  owned-state cascade + tests
  67c9a9b82206e611b44bd1c0ade7d5113bb1a36b  belongs-to guard restore
Schema: 43
Reviewer: R03 Independent Acceptance Agent
```

The implementation commits were reviewed independently from the later docs-only
commit `93ce815`.

## 2. Diff Reviewed

`9566d31 -> 67c9a9b` changes five production files and five test/fixture files:

- domain: `resource_revision.dart` (`ResourceLifecycleState`,
  `ResourceRevisionLifecycleException`);
- revision service: `resource_revision_service.dart` (canonical lifecycle gate
  before any restore write);
- trash service: `resource_trash_service.dart` (owned-state port call inside the
  purge transaction, fail-closed without the port, section-restore parent-live
  guard);
- new port: `resource_owned_state_purger.dart` (ownership classification +
  purge statements);
- tree repository: `resource_tree_repository_impl.dart` (CP-2 belongs-to guards
  for sections and parts inside `applyRevisionState`);
- production wiring: `database_service.dart`, `riverpod_providers.dart` (both
  construct `ResourceOwnedStatePurger`);
- regression coverage: `r03_lifecycle_integrity_test.dart` (TG9 + TG10, real
  SQLite), `resource_trash_service_test.dart` and `phase9_recovery_fixtures.dart`
  wiring.

No schema or migration file changed. The architecture guard "the tree repository
never touches legacy resource tables" still passes: the tree impl only reads its
own `_sections`/`_parts` tables for ownership checks.

## 3. Finding Verification

### M9 / CP-2 (revision as resurrection side door) - CLOSED

`restoreRevision` now reads the canonical row through `readNodesTimestamps`
(which deliberately does not filter `deleted_at`) before the pre-restore
capture. A trashed resource raises
`ResourceRevisionLifecycleException(state: trashed)`, a purged one
`state: gone`, both before a single write. The earlier implementation flipped
`deleted_at` back to null in `_upsertRevisionNode`, resurrecting a binned
resource while its trash entry stayed unresolved - now unreachable through this
path. TG9 proves: trashed refusal with zero writes, explicit trash restore
first, then the revision restore succeeds.

Note: after the R03 cascade, a purged resource's revisions are deleted with it,
so the `gone` gate is defence in depth behind a revision-not-found failure.
Verified acceptable - the resurrection path is closed either way.

### CP-2 (child belongs-to) - CLOSED

`applyRevisionState` verifies for every section that an existing row belongs to
the target resource, and for every part that (a) the existing row's owning
section resolves to the target resource and (b) the snapshot's parent section
resolves to the target resource. A revision snapshot can no longer hijack a
node from another resource or move a part across resource identities. TG9
covers all three refusal shapes against real SQLite.

### M11 / M12 / N4 / N6 / N14 (permanent-delete orphans) - CLOSED for resource-level purge

`permanentDelete` now discharges, in one transaction: revisions (+ nodes via
FK), autosaves, compression jobs (+ candidates via FK), generation sessions,
blueprints, generation tasks (+ attempts via FK), assembly readiness and
assembly entries. The purge of tree rows, auxiliary state, the linked legacy
row and the bin entry now commits or rolls back together. TG10 asserts every
table reaches zero, the creation-session tombstone survives, the sibling
resource is untouched, and an injected owned-purge failure rolls everything
back.

### N5 / N7 (dangling child restore) - CLOSED

Restoring a Section whose parent Resource is still soft deleted is refused with
a typed conflict; the entry stays unresolved and the resource-then-section
order is covered by TG9.

### Identity (R03-A) - VERIFIED, no code defect

The audit found no integer id-equality inference anywhere: legacy/tree identity
is carried by `resource_migration_records` (PK source_table+source_id+version,
indexed by resource_id), deterministic `res_legacy_` ids and the pipeline
fingerprint. TG10 proves re-running the migration is idempotent and that a
purged resource does not resurrect through a later migration run.

## 4. Lifecycle Contract

`live -> soft-deleted/trash -> restore -> live` and
`soft-deleted/trash -> permanent delete -> gone` are the only legal
transitions. Verified enforcement points:

- revision restore: refuses non-live targets (new gate);
- trash restore: refuses restored/purged targets, guarded `restored_at` claim,
  parent-live guard for sections;
- permanent delete: refuses live nodes, cascades owned state atomically;
- late bridge/migration after gone: mapping record is a tombstone, no
  resurrection (TG10).

## 5. Ownership / Cascade Classification

Confirmed against the purger implementation and the schema:

```text
owned, cascaded in the purge transaction:
  resources/sections/parts (tree), resource_trash entry, linked legacy row,
  resource_revisions (+revision_nodes FK), resource_autosaves,
  resource_compression_jobs (+candidates FK), resource_generation_sessions,
  resource_blueprints, resource_generation_tasks (+attempts FK),
  resource_assembly_readiness, resource_assembly_entries
explicit tombstone:
  resource_creation_sessions (UNIQUE idempotency_key keeps blocking reuse)
not owned (no cascade):
  world_entries + embeddings, adventure_runtime_entities (adventure aggregate)
```

## 6. Mutation Verification

All mutations were performed in an isolated `/tmp` repository copy at the
acceptance HEAD, separately from the implementer's verification.

| Mutation | Result |
| --- | --- |
| MUT-ACC-1 short-circuit the revision-restore lifecycle gate | DETECTED; TG9 trashed-refusal and restore-order tests failed |
| MUT-ACC-2 short-circuit the section-restore parent-live guard | DETECTED; TG9 child-restore test failed |
| MUT-ACC-3 cascade the creation-session tombstone away | DETECTED; TG10 tombstone assertion failed |
| MUT-ACC-4 probe: purge one SECTION, inspect residual rows | PROBE CONFIRMED FINDING (see R03-A-N1) |

The implementer's own mutations (gate removal, parent guard, omitted autosaves
cascade, split transaction, belongs-to removal) were re-checked by report and
are consistent with the code under review.

## 7. Tests

```text
dart format --output=none --set-exit-if-changed .: PASS (501 files, 0 changed)
flutter analyze: PASS (No issues found)
R03 + lifecycle targeted files: PASS (190 passed, 0 failed)
flutter test: PASS (1652 passed, 0 failed)
git diff --check: PASS
Schema: 43
```

## 8. Acceptance Criteria

```text
AC-R03-01 PASS  identity unique and traceable; no resurrection after purge
AC-R03-02 PASS  trash/gone cannot be bypassed by revision restore (typed, zero writes)
AC-R03-03 PASS  child restore cannot hijack across resource identities (CP-2)
AC-R03-04 PASS  explicit trash restore first; history remains usable afterwards
AC-R03-05 PASS  resource permanent delete discharges all owned auxiliary state
AC-R03-06 PASS  purge is one transaction; failure rolls back completely
AC-R03-07 PASS  retention purge is idempotent, transactional, cascade-consistent
AC-R03-08 PASS  section restore under a binned parent is refused (N5/N7)
AC-R03-09 PASS  TG9/TG10 drive production repository paths on real SQLite
AC-R03-10 PASS  schema remains 43
AC-R03-11 PASS  flutter analyze
AC-R03-12 PASS  targeted tests, 190/190
AC-R03-13 PASS  full flutter test, 1652/1652
AC-R03-14 PASS  independent mutations MUT-ACC-1..3 detected; MUT-ACC-4 probe recorded
```

## 9. Findings

```text
BLOCKER: 0
MAJOR: 0
MINOR: 1
TEST-GAP: 0
INFO: 0
```

### R03-A-N1 - Node-scoped purge leaves descendant auxiliary rows behind

Severity: MINOR (non-blocking).

Location: `ResourceOwnedStatePurger.purgeOwnedStateInTransaction`, node-scoped
branch.

Trigger: permanently delete a **Section** (not a whole resource) that had
generation tasks or autosave drafts on its Parts.

Observed: the purge removes only rows whose `node_id` equals the section id;
the purged Parts' `resource_generation_tasks` (and attempts) and
`resource_autosaves` rows survive. A probe at the acceptance HEAD measured
`tasks=1 autosaves=1` after purging one section.

Why non-blocking: no resurrection and no data loss path exists. An autosave
draft for a vanished node is dropped by the recovery classifier
(`resource_autosave_service_test.dart`: "a draft for a vanished node is
dropped"); a generation task against a purged Part fails closed at commit
(part-not-found). The resource-level purge - the primary target of
M11/M12/N4/N6/N14 - is fully covered. The residual rows are fail-closed
litter, not semantically live orphans in the acceptance-criteria sense.

Repair direction: extend the node-scoped branch to enumerate descendant Part
ids of the purged section (and the section itself) and delete their autosaves,
compression jobs and generation tasks in the same transaction. Small,
self-contained; can ride along with R08 cleanup or an earlier targeted fix.

## 10. Final Verdict

```text
ACCEPTED
```

## 11. Program Handoff

```text
R03 status: ACCEPTED
Milestone A: R01-R03 all ACCEPTED; Core Integrity exit gate reached pending the
  acceptance criteria of the program plan (BLOCKER=0 confirmed)
R03-A-N1: MINOR, repair direction recorded; not a dependency of Milestone B
Next recommended action: R04 - LLM Transport & Streaming Protocol Reliability
  (or R05/R06, all now technically unblocked)
```
