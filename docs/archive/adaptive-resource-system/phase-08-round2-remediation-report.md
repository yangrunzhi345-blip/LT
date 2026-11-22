# Phase 8 Round 2 Remediation Report

**Scope:** remediation of [phase-08-final-independent-acceptance.md](phase-08-final-independent-acceptance.md) (Round 2 verdict: FAILED).
**Executor:** executor-agent (CodeBuddy CLI), 2026-09-17.

## Git

Start HEAD: `03947be`
End HEAD: `8ce43a6`
Commits:
- `8c62105` `fix(phase8): add worker leases, atomic claims and resource-scoped drains`
- `8ce43a6` `docs(status): record phase 8 round 2 remediation and archive its reports`

## Fixed Findings

### BUG-001 / BUG-R2-001 — recovery stole a live job

**Root Cause**
`recoverInterruptedJobs()` selected every `running` row with no ownership test, and
`ResourceCapacityController._runBackgroundWorkflow` called it on **every** capacity load,
bypassing the `_recoveredThisInstance` latch (the method wrote the flag but never read it).
The design precondition "nothing of ours can be in `running` yet" was therefore false: a live
job was released to `queued` and a second drain re-claimed it.

**Fix**
- `CompressionJob` gains `workerId` / `claimedAt` / `leaseExpiresAt`; `ResourceLimits.compressionLeaseDuration = 5min`.
- `recoverStaleRunningJobs(now)` is one statement that reclaims only
  `status = 'running' AND (lease_expires_at IS NULL OR lease_expires_at < now)` — "no lease" means
  ownership cannot be proven, which is also how pre-lease legacy rows stay recoverable. A live
  lease is never touched. Budget-exhausted rows become `failed`, the rest return to `queued`
  (this is what keeps recovery bounded).
- The call site moved out of the UI: `drain` performs it before claiming, and the new
  `CompressionBackgroundWorker.start()` performs it at app startup (`main.dart`).
  `ResourceCapacityController.load()` no longer triggers any compression side effect at all.
- The `_recoveredThisInstance` latch was deleted; recovery is now safe to run often because it is
  stale-scoped rather than unconditional.

**Tests**
`compression_concurrency_test.dart` "TEST-2 a live worker is not recovered" (a running job with a
live lease is untouched and its owner completes normally, model calls == 1) and
"claim and ownership" (a worker that lost its lease cannot commit); TEST-3 covers the expired-lease
path; `resource_capacity_runtime_test.dart` "worker lifecycle, no Studio involved" proves
`worker.start()` recovers a stale row and leaves a live one alone; `database_migration_v40_test.dart`
proves a legacy `running` row without a lease is reclaimed rather than stuck.

### BUG-003 — automatic compression runtime

**Root Cause**
The threshold trigger was wired to the Studio *load* path and nothing consumed the queue: `drain`
had no production caller other than the manual button, so an auto-queued job stayed `queued`
forever. Phase 8's "离开编辑器后的后台 compression job" was not delivered.

**Fix**
`CompressionBackgroundWorker` is the runtime owner of the automatic path:
`onEditorLeave(resourceId)` = fresh `measure` → `evaluateResource` → `enqueueForResource` only when
warranted (or, below the threshold, adopt any job queued earlier) → `scheduleProcessing` which runs a
resource-scoped drain with `unawaited`, coalesced per resource. Every entry point catches its own
failure into `lastError`, so compression can never fail the editor action or navigation. The trigger
moved to the editor-leave boundary: `ResourceCapacityController.dispose()` and the Studio's
resource switch (`resource_studio_page.dart`), plus a startup hook in `main.dart`.
The manual "生成压缩候选" path is unchanged except that its drain is now resource scoped.

**Tests**
`resource_capacity_runtime_test.dart` "automatic compression lifecycle (production worker)":
over-budget resource → jobs queued and a candidate produced with the original untouched; a gated LLM
proves `onEditorLeave` returns while the model call is still blocked (non-blocking); an in-budget
resource enqueues nothing and calls no model; a repeated lifecycle event yields exactly one
candidate; a background model failure leaves the original untouched and reports per-job.
`compression_worker_test.dart` adds coalescing, "trigger failure never throws", and "leftover queued
jobs are processed below the threshold". `resource_capacity_runtime_test.dart` also proves recovery
runs through the worker lifecycle without opening any panel.

### BUG-R2-002 — retry hit the active-target unique index

**Root Cause**
`retryJob` was a read-then-write: it checked only `canRetry`, then wrote `failed → queued`
unconditionally. When the same target already had a new `queued` job (section edited after the
failure), the write violated `idx_compression_jobs_active_target` and surfaced a raw
`SqfliteFfiException`; `retryFailedJobs` aborted its loop, so later failures were never retried.

**Fix**
`retryFailedJob(jobId)` is a single statement whose `NOT EXISTS` predicate refuses the update when
the same `(resource_id, target_node_id)` already has a `queued`/`running` row, so the conflict is
unreachable by construction; a residual UNIQUE violation is additionally mapped to a business
`false`. `retryFailedJobs(resourceId)` returns `CompressionRetryOutcome(requeued,
skippedActiveTarget, skippedExhausted)` and attempts each job independently, so one conflict can no
longer abort the batch. The panel reports skipped conflicts next to the retries.

**Tests**
`compression_concurrency_test.dart` TEST-4 (busy target → `skippedActiveTarget == 1`, exactly one
active row, no exception) and TEST-5 (partial batch: one skipped, one requeued);
`resource_capacity_runtime_test.dart` retry group (visible failure reason, retry succeeds, budget
exhaustion stops retrying); `test/widget/resource_capacity_test.dart` pins the controller messages
including the combined "retried N; skipped M" case.

### A5 — drain must be resource scoped

**Fix**
`findJobsByStatus(status, {resourceId})` filters in SQL (`AND resource_id = ?`); `drain({
ResourceId? resourceId})` passes it through; production consumers
(`ResourceCapacityServiceRuntime.runQueuedCompression(resourceId)` and the background worker) always
scope to one resource. The `null` form exists only for tests.

**Tests**
`compression_concurrency_test.dart` TEST-6: A's two jobs succeed, B's two stay `queued`, model
calls == 2 (B never reached the model), and B is only processed by an explicit B drain.

### A7 — atomic claim and ownership CAS

**Fix**
- `claimJob` = `UPDATE ... SET status='running', worker_id=?, attempts=?, claimed_at=?,
  lease_expires_at=? ... WHERE job_id = ? AND status = 'queued'` → only `affected == 1` runs.
- `completeJob` = `UPDATE ... WHERE job_id = ? AND status = 'running' AND worker_id = ?`; a worker
  whose lease was reclaimed writes nothing, and because the coordinator only inserts a candidate
  after the CAS succeeds, a stale run cannot publish a result either.
- `updateJob` (the unguarded full-row write) was removed; every transition is now a guarded statement.

**Tests**
TEST-1 starts four concurrent drains on one queued job with a gated LLM: the winner is held inside
the model call while the others act, and the result is model calls == 1, `attempts == 1`,
candidates == 1. The "claim and ownership" test asserts a late finisher cannot overwrite the row.

## Worker Architecture

| Concern | Implementation |
| --- | --- |
| worker identity | `CompressionCoordinator.workerId` (injectable; defaults to `wkr_<micros>_<seq>`), one coordinator per process via `compressionCoordinatorProvider` (non-autoDispose). |
| claim | single `UPDATE ... WHERE status='queued'`; `affected == 1` wins, everyone else skips (not counted as processed or failed). |
| ownership / lease | claim writes `worker_id`, `claimed_at`, `lease_expires_at = claimed_at + ResourceLimits.compressionLeaseDuration`. |
| recovery | `recoverStaleRunningJobs(now)` touches only `running` rows with an expired or absent lease; `attempts < max_attempts → queued`, else `failed`; clears the lease. Idempotent, called by every `drain` and by the worker startup hook. |
| terminal CAS | `completeJob` requires `status='running' AND worker_id = caller`; the candidate is inserted only after the CAS succeeds. |
| background consumer | `CompressionBackgroundWorker.scheduleProcessing` (unawaited, coalesced per resource) → `drain(resourceId: ...)`. |
| clock | `CompressionCoordinator(clock:)` is injected; tests pass a fixed/advanceable clock so no test waits on real lease time. |

## Automatic Compression Lifecycle

**Where the trigger lives.** `ResourceCapacityController.dispose()` (the Studio page being left) and
the Studio's resource switch both call `notifyEditorLeft()`, which calls
`ResourceCapacityRuntime.onEditorLeave(resourceId)` and does not await it. `main.dart` starts the
worker once at app startup (recovery only). `load()` is now side-effect free.

**Why this satisfies "leaving the editor produces a non-blocking background compression job".**
Leaving the editor measures, evaluates and queues synchronously (no model call), then returns; the
resource-scoped drain runs in the background and produces candidates. Nothing on the editor path
awaits the model, and every worker entry point catches its own failure, so navigation, saving and
editing cannot fail because of compression. Candidates are never published — `applied_at` stays
`NULL` for Phase 9.

## Database Changes

**Schema:** v39 → **v40**. `resource_compression_jobs` gains `worker_id TEXT NOT NULL DEFAULT ''`,
`claimed_at TEXT`, `lease_expires_at TEXT` (`createV40Schema` = v39 + `addCompressionLeaseColumns`,
so fresh install and migration share one definition).

**Migration:** `migrateStepByStep` adds an `oldVersion < 40 && newVersion >= 40` step calling
`addCompressionLeaseColumns` (`safeAddColumn`, idempotent). No new index is required: recovery is
scoped by `status`, which `idx_compression_jobs_status` already covers, and the partial unique index
`idx_compression_jobs_active_target` is unchanged (recovery only moves `running → queued`, which
cannot collide because the index guarantees at most one active row per target).

**Legacy running handling:** the migration does **not** rewrite business rows. Pre-lease `running`
rows keep their status and get `worker_id = ''`, `lease_expires_at = NULL`; because a row without a
lease cannot prove ownership, the ordinary stale-recovery rule reclaims them
(`attempts < max → queued`, else `failed`). No legacy `running` row is left unrecoverable.

**Tests:** new `database_migration_v40_test.dart` (fresh-install columns and defaults; v39 → v40
preserves the legacy row and proves it is recoverable; the upgrade step is idempotent). The schema
version pins in `database_migration_v36_test.dart`, `database_migration_v38_test.dart` and
`database_migration_v39_test.dart` were consciously updated 39 → 40 (the pins exist for exactly this
purpose; no assertion was weakened).

## Concurrency Verification

| Test | Method | Result |
| --- | --- | --- |
| two/four concurrent drains on one job | `Future.wait` over four coordinators + a gated LLM held inside the model call | model calls 1, `attempts` 1, candidates 1 |
| live worker must not be recovered | worker A mid-request (gated LLM) while worker B recovers and drains | B reclaims 0, A completes, model calls 1 |
| expired lease recovery | explicit expired lease + injected clock | reclaimed → `queued` → drained → `succeeded` |
| retry vs active queued target | failed job + new queued job on the same target | `skippedActiveTarget == 1`, no exception, one active row |
| retry batch partial conflict | two failed jobs, one target busy | `requeued == 1`, `skippedActiveTarget == 1`, batch continues |
| resource isolation | A and B each queued | A drained only; B stays `queued` and never reaches the model |
| lost lease cannot commit | lease forced expired mid-run, then recovery | the late worker writes nothing and publishes no candidate |

All concurrency tests overlap really (`Future.wait`, blocking LLM port, observed in-flight state via
`waitForCondition`); none is a sequential `await A; await B`.

## Regression Verification

**BUG-002:** failure visible with reason, retry reachable and resource scoped, `attempts` never reset
by a retry, `attempts >= maxAttempts` refuses further retries, and the conflict case is now a
business result. Covered by the retry groups of `resource_capacity_runtime_test.dart` plus the
widget controller tests.

**BUG-004:** `compressionTargetRatio == 0.6`, `nodeTargetCharacters(800) == 480`, a 560-char result
fails with the original/actual/target numbers, a ≤480 result becomes exactly one candidate, and the
original stays byte-for-byte unchanged. The band was **not** relaxed; the assertions in
`compression_pipeline_test.dart` / `resource_compression_test.dart` are unchanged except for the
`retryFailedJobs` return type.

## Phase Boundaries

- **Phase 5:** unchanged (`git diff --name-only 03947be..8ce43a6` over the frozen protocol files is empty).
- **Phase 6:** unchanged (streaming service/session/runtime contracts untouched).
- **Phase 7:** unchanged (section control service/events/repository, generation task repository untouched).
- **resource_parts.content:** zero writes anywhere in the compression path; the only writes are
  `resource_compression_jobs` / `resource_compression_candidates`, and tests assert the Part bodies
  are identical before and after.
- **candidate.applied_at:** still written as `NULL`; no apply / publish / promote / revision / head
  code exists.
- No Phase 9 capability was implemented.

## Remaining Findings

Not fixed (registered, unchanged): **A6** (cancelled/no-content counted as `failedJobs`),
**A8** (cached `historicalRevisionCount == 0`, `capacity_status` written but unread; the panel
prefers the cache — the trigger itself was verified to use a fresh measure), **A9** (archived nodes
are compression targets but excluded from context assembly), **A10** (`ResourceContextAssembler`
"recent" semantics vs documentation), **A11** (`original_char_count` includes `\n\n` separators),
**A12** (`insertJob` can still surface an internal `StateError` on concurrent enqueue — the retry
path no longer does), **BUG-R2-003** (`latestFailureReason` returns the oldest, not the most recent,
failure), **BUG-R2-004** (`CompressionBudget` / `compressionTargetRatio` documentation claims an
under-budget result is still a candidate while `CompressionValidator` rejects it), and
**INFO-001…006**.

Two Round-2 test premises were rewritten because they encoded the repudiated design: the widget
controller tests that asserted `load()` starts recovery + the threshold trigger now assert that
`load()` is side-effect free and that dispose triggers the automatic path, and the assertions about
enqueue-only behaviour moved to the worker tests where the background consumer is now exercised.
No assertion was dropped without a stronger replacement.

## Test Results

```text
dart format --output=none --set-exit-if-changed .
Formatted 431 files (0 changed)

flutter analyze
No issues found!

Phase 8 targeted tests (13 files)
+167: All tests passed!

flutter test (full suite)
+1186: All tests passed!

git diff --check
clean
```

Note: during one intermediate full run the pre-existing environment-sensitive
`test/unit/semantic_retrieval_performance_test.dart` timing benchmark failed under load (it is the
known benchmark already documented in STATUS.md); it passes in isolation and in the final full run,
and no Phase 8 code touches semantic retrieval.

## Final Status

Phase 8 remediation completed.

等待第三轮独立验收。
