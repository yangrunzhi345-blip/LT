# R02 Independent Acceptance Report

## 1. Baseline

```text
Acceptance Date: 2026-09-19
Acceptance HEAD: 66ec9fa8bf417c1a6666efebef2173e1bc64a46f
origin/main: 66ec9fa8bf417c1a6666efebef2173e1bc64a46f
Branch: main
Ahead / Behind: 0 / 0
Working Tree Before Acceptance Docs: clean
R02 Start HEAD: e98cc94cc38b37855ed2b485c1b1eb69178b040c
R02 Implementation Commits:
  5a67a2ee472588456aa48a25a55c5662f96f17bc  dialogue commit boundary
  76d743f66009fbf226e44200a771473812caa033  part content source CAS
  45eb245e13786488e843e75ec53e83ec3b524ce0  autosave durability
Schema: 43
Reviewer: R02 Independent Acceptance Agent
Note: R02 acceptance was performed after R03/R04 had already been accepted;
the review therefore verified BOTH the historical implementation commits AND
the live state at the current HEAD.
```

## 2. Diff Reviewed

`e98cc94 -> 45eb245` changes seven production files and ten test files:

- dialogue: `lib/engines/chat_engine.dart` (pre-commit cancellation gate,
  `turnCommitted`/`memoryReconciled` state, catch-path split, transient
  `_cancelRequested` reset);
- generation: `part_generation_coordinator.dart` (source token captured with
  the lease via `PartGenerationAttempt`, conflict treated as terminal),
  `resource_generation_task_repository.dart` (`expectedSourceToken` CAS with
  two defence layers: explicit token compare before the revision snapshot and
  `WHERE id = ? AND deleted_at IS NULL AND updated_at = ?`);
- compression: `compression_job_repository.dart` (`findJobInTransaction`),
  `resource_compression_publisher.dart` + `resource_revision_service.dart`
  (publish validates the live Part token against the candidate's job
  `source_token` before any write);
- autosave: `resource_autosave_service.dart` (per-session flush
  serialization, monotonic edit sequence, failure requeue, honest dispose).

No schema or migration file changed; schema remained 43.

## 3. Post-R02 Drift Check (R03/R04 interaction)

`git diff 45eb245..HEAD` over the six R02-owned production files is **empty** —
R03 (lifecycle/trash) and R04 (LLM transport) touched adjacent code but never
the R02 contract surfaces:

- `resource_revision_service.dart` received R03's restore lifecycle gate in a
  different function than R02's `publishCompressedContentInTransaction` CAS;
- R03's owned-state purger deletes autosave drafts only on explicit permanent
  delete, which is the intended post-purge behaviour, not a durability
  regression;
- spot checks at HEAD: `turnCommitted` x6, `expectedSourceToken` x6 (repo) and
  x6 (revision service), `_requeueAfterFailure` present.

The R02 contracts are fully in force at the acceptance HEAD.

## 4. Contract Verification

### Race 1 - dialogue commit boundary (A1-A7) - CLOSED

`commitSceneDialogueTurn` is the irreversible boundary. A cancelled/superseded
request is refused entry by the final `_isRequestCurrent` gate; once the
transaction returns, `turnCommitted` makes the durable result authoritative -
a late cancellation may only complete memory reconciliation (best-effort,
logged, DB remains truth) and can never delete the committed user message or
restore the old GameState. Transient `_cancelRequested` is reset on both the
committed and rollback paths so a late cancel cannot poison the next request.
Tests A1-A7 are barrier-controlled (Completer gates, no wall clock).

Defence-in-depth note (verified during acceptance): the post-commit
`!turnCommitted` short-circuit and the catch-side `turnCommitted` branch are a
redundant defence PAIR - removing either alone is not observable through the
tests because the other still prevents the fake rollback. The original bug is
only restored by mutating both, which is exactly what MUT-R02-ACC-1 does.

### Race 2 - part content source CAS (B1-B10 + coordinator) - CLOSED

Every writer that replaces `resource_parts.content` commits under the observed
source version. Generation captures the Part's `updated_at` atomically with
the attempt lease (never re-read before commit); a mismatch rolls the whole
transaction back and raises `ResourceTreeConflictException`, leaving no
revision head, no section/task half-state. The coordinator treats a source
conflict as terminal instead of auto-retrying a regeneration that would
overwrite the user's edit. Compression publish validates the candidate's job
`source_token` against the live Part inside the publish transaction - a stale
candidate is refused with no half-committed `applied_at`. The double-layer CAS
(explicit compare + guarded UPDATE predicate) is redundant by design; both
layers must be disabled to observe the regression, which MUT-R02-ACC-2 does.

### Race 3 - autosave durability (C1-C12) - CLOSED

Entering a flush no longer counts as persisting. Flushes of one session are
serialized; buffered edits carry a monotonic sequence so a failed write is
re-queued only while it is still the newest edit - a late failure can neither
delete nor overwrite text typed during the flush (C3/C4). Journal failure
leaves the edit pending in memory; commit failure leaves the draft durable in
`resource_autosaves` - at least one authoritative recovery source always
survives (C1/C2). Retries succeed cleanly without duplicate drafts (C5/C6).
Dispose reports failure instead of faking success (C8). Unresolved conflicts
hold newer typing without overwriting external content (C9); sessions are
independent (C10); duplicate flushes are idempotent (C11); `onFlushed` reports
failures honestly (C12).

### Schema decision - VERIFIED

Schema 43 unchanged: `resource_compression_jobs` already carried
`source_token`, and generation uses `resource_parts.updated_at` captured at
lease time. No migration was needed or added.

## 5. Mutation Verification (isolated /tmp copy at the acceptance HEAD)

| Mutation | Result |
| --- | --- |
| MUT-R02-ACC-1 restore the post-commit cancellation throw + fake rollback (original bug pair) | DETECTED; A2 and A3 failed |
| MUT-R02-ACC-2 disable both source CAS layers (compare + guarded WHERE) | DETECTED; B1, B9/B10 and the coordinator no-auto-retry test failed |
| MUT-R02-ACC-3 disable the failure requeue after a flush snapshot | DETECTED; C1, C5 and C6 failed |

Probe notes: single-layer or single-side mutations are unobservable by design
(defence in depth); the acceptance used the minimal bug-equivalent pairs.
Implementer mutations were reviewed and match these findings.

## 6. Tests

```text
dart format --output=none --set-exit-if-changed .: PASS (502 files, 0 changed)
flutter analyze: PASS (No issues found)
R02 targeted files: PASS (101 passed, 0 failed; A1-A7, B1-B10 + coordinator,
  C1-C12, phase9 concurrency/revision-boundary, generation task repository,
  streaming lifecycle regression)
flutter test: PASS (1678 passed, 0 failed)
git diff --check: PASS
Schema: 43
```

## 7. Acceptance Criteria

```text
AC-R02-01 PASS  cancel before dialogue commit => no DB turn, no memory turn
AC-R02-02 PASS  cancel during/after successful commit => committed state authoritative
AC-R02-03 PASS  DB == memory == UI after commit; late cancel cannot fake rollback
AC-R02-04 PASS  duplicate cancellation idempotent; next request unpoisoned
AC-R02-05 PASS  stale generation overwrite refused (two CAS layers, typed conflict)
AC-R02-06 PASS  generation source token captured at lease, never re-read before commit
AC-R02-07 PASS  stale compression candidate refused; no half-committed applied_at
AC-R02-08 PASS  source conflict is terminal for generation retry
AC-R02-09 PASS  journal/commit failure keeps text in memory or durable journal
AC-R02-10 PASS  flush serialization + sequence requeue protect concurrent typing
AC-R02-11 PASS  dispose cannot fake durability
AC-R02-12 PASS  duplicate flush idempotent; onFlushed honest
AC-R02-13 PASS  schema remains 43
AC-R02-14 PASS  R02 targeted 101/101
AC-R02-15 PASS  full flutter test 1678/1678
AC-R02-16 PASS  independent mutations MUT-R02-ACC-1..3 detected
```

## 8. Findings

```text
BLOCKER: 0
MAJOR: 0
MINOR: 0
TEST-GAP: 0
INFO: 1
```

### R02-A-INFO-1 - Defence pairs are only observable as pairs

The post-commit `!turnCommitted` short-circuit and the catch-side
`turnCommitted` guard (and likewise the two source-CAS layers) are mutually
redundant defences. Single-point removal is not test-observable; the mutation
plan must always mutate the pair. Recorded as INFO for future acceptance
agents - no code change required, the redundancy is intentional.

## 9. Final Verdict

```text
ACCEPTED
```

## 10. Program Handoff

```text
R02 status: ACCEPTED
Milestone A: R01-R03 all ACCEPTED - the formal Milestone A acceptance gate
  is now COMPLETE (the previously outstanding R02 independent acceptance has
  been performed and passed)
Next recommended action: R05 - Runtime State, Production Wiring & Context
  Continuity
Carry-forward: R03-A-N1 (MINOR, R07) and R04-A-INFO-1 remain informational
```
