# Phase 8 Independent Audit

**Auditor:** independent audit agent (read-only)
**Date:** 2026-09-17
**Baseline:** `46c3e0f..752b440` (34 files, +6154 / −28)
**Audited HEAD:** `752b440` (`docs(status): pin phase 8 start and end HEAD`)
**Working tree at audit time:** clean except untracked `.codebuddy/` (pre-existing, untouched)
**Target spec:** `docs/adaptive-resource-system/phase-08-capacity-and-compression.md`
**Context read:** `STATUS.md`, `phase-07-final-independent-acceptance.md` (D2), `phase-09-revisions-autosave-trash.md`, `docs/architecture/adaptive-resource-system.md` 附录 E

## Audit Result

**FAILED**

Phase 8 delivers a well-bounded *library* (capacity measurement, candidate-only compression, strict protocol parsing, priority context packing) with a genuinely good migration and a real no-N+1 statement-count test. It does **not** deliver the phase's operational requirements: an interrupted compression job permanently deadlocks its target with no recovery path (contradicting the phase's own "应用重启后可恢复" acceptance line), failed jobs have no reachable retry, and neither the automatic trigger nor the "离开编辑器后的后台 compression job" is wired in production. Phase 9 must not be unlocked on this baseline.

## Summary

| # | Severity | Title |
| --- | --- | --- |
| A1 | **BLOCKER** | Interrupted `running` compression job is unrecoverable and permanently blocks its target |
| A2 | MAJOR | Failed compression jobs have no production retry path (transient failures are permanent) |
| A3 | MAJOR | Automatic threshold trigger and "leave the editor" background job are not wired |
| A4 | MAJOR | A shorter-but-over-target result is discarded; target boundary is untested |
| A5 | MINOR | `drain` is global, not resource-scoped; results are attributed to the wrong resource |
| A6 | MINOR | Cancelled / no-content outcomes are counted as failures and shown as errors |
| A7 | MINOR | No status CAS or claim in `drain`; concurrent drains corrupt status and attempt counts |
| A8 | MINOR | Cached capacity reports `historicalRevisionCount: 0` and stale characters; `capacity_status` never read |
| A9 | MINOR | Archived Sections/Parts are compression targets but excluded from context assembly |
| A10 | MINOR | `ResourceContextAssembler` "recent plot" doc/behavior mismatch; fail-closed on unknown current section |
| A11 | MINOR | Candidate `original_char_count` includes `\n\n` joiners → savings overstated vs. the measured count |
| A12 | MINOR | `insertJob` surfaces an internal `StateError` to the UI on a benign concurrent enqueue |
| I1–I6 | INFO | Dead API surface, self-attested retention, prompt-injection surface, orphan rows, section-candidate mapping, label scope expansion |

### What was verified and holds

- **No resource head can be modified by Phase 8.** (`I2` data-safety invariant holds.)
  `grep -nE "\.(update|insert|delete|execute)\(" lib/application/resources/compression_job_repository.dart lib/application/resources/compression_coordinator.dart` → writes only to `resource_compression_jobs` / `resource_compression_candidates`; no Phase 8 file writes `resource_parts`. No `apply` / `publish` code path exists; `applied_at` is always written as `null` (`compression_job_repository.dart:216`).
- **Frozen modules untouched.** `git diff --name-only 46c3e0f..752b440 -- lib/application/resources/part_generation_coordinator.dart part_generation_prompt_builder.dart resource_generation_task_repository.dart section_control_service.dart streaming_resource_generation_service.dart lib/domain/resources/resource_generation_protocol.dart resource_generation_patch.dart section_control.dart resource_contracts.dart lib/services/repositories/resource_tree_repository_impl.dart` → **empty**.
- **Capacity measurement is a bounded statement count.** Verified dynamically by the audited suite's `_CountingDatabase` (2-Part vs 400-Part tree must issue the same number of statements) and statically (no `SELECT * FROM`, aggregation in SQLite `GROUP BY`).
- **Migration v39 is idempotent and non-destructive.** `safeAddColumn` + `CREATE TABLE IF NOT EXISTS`; fresh-install and v38→v39 tests assert column defaults, preserved rows, and the pinned version `39`; the upgrade step is re-run explicitly in a test.
- **Phase 7 D2 closure is authorized and consistent.** The audit-mandated option B (disable + explain, no reset semantics) is implemented and registered in `STATUS.md`; the Phase 5 task state machine is untouched.

### Commands executed (real output)

```text
flutter analyze                 → No issues found! (ran in 1.7s)
flutter test (Phase 8 files)    → 121 passed
flutter test (full suite)       → 1145 passed
git diff --name-only (frozen)   → empty
```

## Findings

---

### BUG-001

**Severity: Blocker**

**Description**

A compression job that is interrupted while in `running` (app killed, window closed, crash, OOM) stays `running` forever. There is no recovery routine, `drain` never selects it, and the partial unique index on active targets permanently prevents a replacement job for the same target. The resource's capacity UI then silently does nothing forever.

**Location**

- `lib/application/resources/compression_coordinator.dart:207-210` — `drain` reads only `CompressionJobStatus.queued`.
- `lib/application/resources/compression_coordinator.dart:242-244` — `retryJob` requires `status == failed`.
- `lib/application/resources/compression_coordinator.dart:466-471` — `_enqueue` returns the existing **active** job (`findActiveForTarget`) and never inserts.
- `lib/application/resources/compression_job_repository.dart:93-99` — `findActiveForTarget` treats `'running'` as active.
- `lib/services/database_service.dart:507-510` — `idx_compression_jobs_active_target ... WHERE status IN ('queued', 'running')`.
- `lib/application/resources/compression_coordinator.dart:279` (write `running`) / `:342` (terminal write) — the only writers of a job's status; both live inside an active call, so an orphaned `running` row has no writer.
- Contrast: Phase 5 provides `recoverInterruptedTasks` (`resource_generation_task_repository.dart:560`, wired at `streaming_resource_generation_service.dart:481`); Phase 8 has no equivalent (`grep -rn "Interrupted" lib/` → nothing in the compression path).

**Trigger conditions**

1. `requestCompression()` → `enqueueForResource` → `drain` → `_runJob` writes `status='running'` (`:279`).
2. The process dies while awaiting the LLM (`:297`) — closing the desktop window during a compression run, or a crash.
3. Restart, reopen the Studio, press 生成压缩候选 again.

**Actual impact**

- The job is `running` forever; `drain` processes 0 jobs for it.
- `idx_compression_jobs_active_target` blocks any new job for that `(resource, target)`, so the target can **never** be compressed again on that database.
- The failure is silent and user-invisible: `queueCompression` counts `isActive` jobs (`resource_capacity_runtime.dart:61`) so it returns ≥1, and `drain` returns `succeededJobs == 0, failedJobs == 0`, so the controller sets `lastMessage = ''` and `errorMessage = ''` (`resource_capacity_controller.dart:106-118`). The UI shows no success, no error, no change.
- Directly contradicts the phase acceptance line "网络失败、取消、部分成功、**应用重启后可恢复**，且无无限重试" (`phase-08-capacity-and-compression.md:35`).

**Root cause**

The job lifecycle was designed with terminal-state retry only (`failed → queued`) but without an interrupted-state recovery step, while the DB adds a uniqueness constraint that treats `running` as a lock. In-memory state machines cannot express "the process that owned this lock is gone", so a durable lease/claim or a startup recovery pass is required — exactly the pattern Phase 5 already uses.

**Recommended fix**

Add `recoverInterruptedJobs()` to `ICompressionJobRepository`/`CompressionCoordinator` that, on construction (or app start / Studio open), transitions stale `running` jobs to `failed` with a reason such as `'应用中断，已释放'` (or back to `queued` when `attempts < max_attempts`), and invoke it before the first `drain`. Optionally narrow `idx_compression_jobs_active_target` to `queued` and rely on a timestamp-based lease for `running`. Add a regression test: insert a job row with `status='running'`, then assert `drain`/`enqueueForResource` recovers it and a new job is possible.

**Verification method**

Static enumeration above; the "no writer exists" property is provable from the grep of all status writers. A dynamic crash reproduction was **not executed** (it requires killing a process mid-request or adding a fixture test, which is outside this audit's write scope). A reviewer can reproduce without a crash by inserting one `resource_compression_jobs` row with `status='running'` for a real section and then running `enqueueForResource` + `drain`.

**Affected files**

`compression_coordinator.dart`, `compression_job_repository.dart`, `database_service.dart`, `resource_capacity_runtime.dart`

**Recommended owner**

executor Agent (Phase 8 remediation); the lease/timeout design should be co-signed by the Phase 9 owner, since Phase 9 will schedule compression from a background/revision boundary.

---

### BUG-002

**Severity: Major**

**Description**

A compression job that fails (network error, timeout, validation failure, malformed response) can never be retried from production. `CompressionCoordinator.retryJob` exists but has **zero production callers**, and the de-duplication path actively prevents a replacement job from being created for the same source version.

**Location**

- `lib/application/resources/compression_coordinator.dart:242` — `retryJob`; `grep -rn "retryJob" lib/` → only the declaration (callers exist only in `test/application/resources/compression_pipeline_test.dart`).
- `lib/application/resources/compression_coordinator.dart:459-465` — `_enqueue` returns the existing job for `(resource, scope, target, sourceToken)` **regardless of status**, so a `failed` job is returned instead of a fresh one.
- `lib/application/resources/compression_coordinator.dart:467-471` — the `findActiveForTarget` fallback excludes `failed`, but `_enqueue` has already returned at `:465`.
- `lib/features/resource_studio/application/use_cases/resource_capacity_runtime.dart:61` — only `isActive` jobs are counted, so a failed job yields `queued == 0`.
- `lib/features/resource_studio/presentation/controllers/resource_capacity_controller.dart:86-92` — the user is told `'没有需要压缩的章节'`.

**Trigger conditions**

Run compression once with a transient failure: e.g. the LLM reply is unparseable (`compression_pipeline_test.dart` "malformed response" case) or the request errors (`StateError('网络中断')` case). The job becomes `failed`, `attempts = 1`, `canRetry == true`. Press 生成压缩候选 again.

**Actual impact**

- The job stays `failed`; `_enqueue` returns it; the UI says "没有需要压缩的章节" although a retryable job exists.
- There is no retry affordance anywhere in the Studio panel (`resource_capacity_panel.dart` exposes only 刷新容量 / 生成压缩候选), so the only recovery is manual DB editing.
- The configured retry budget (`ResourceLimits.maxCompressionAttempts = 2`) is therefore never usable in production: `attempts` can only ever reach 1 through the UI.
- Contradicts `phase-08-capacity-and-compression.md:19` ("失败保留原稿并**允许局部重试**") and `:35` ("网络失败…可恢复").

**Root cause**

Retry was modelled as an explicit coordinator command instead of being reachable from the only production entry point. The version de-dup key (`resource, scope, target, sourceToken`) is correct for avoiding duplicate *work*, but it is also applied to *terminal failures*, conflating "already done" with "already attempted".

**Recommended fix**

Either (a) surface failed jobs and a retry action in the Studio panel (list `findJobsForStatus(failed)` with `canRetry`, call `retryJob`), or (b) make `enqueueForResource` re-queue a `failed` job when `canRetry` and the node's current token equals the job's `sourceToken`. Add a test that goes UI-entry → failure → retry → success.

**Verification method**

`grep -rn "retryJob" lib/` returns only the declaration; `_enqueue`'s early return is at `:459-465`; the controller branch at `:86-92`. Confirmed by the audited test suite itself, which calls `retryJob` directly (bypassing every production path).

**Affected files**

`compression_coordinator.dart`, `resource_capacity_runtime.dart`, `resource_capacity_controller.dart`, `resource_capacity_panel.dart`

**Recommended owner**

executor Agent (Phase 8 remediation)

---

### BUG-003

**Severity: Major**

**Description**

The phase's automatic/background compression deliverable is not wired. Only the manual panel button queues jobs; the configurable threshold trigger and the "leave the editor" background job have no production caller.

**Location**

- `lib/features/resource_studio/presentation/pages/resource_studio_page.dart:197` — the **only** call site of `requestCompression()`.
- `grep -rn "evaluateResource\|evaluateContext\|compressionTargets\|measureAll\|measureReadOnly" lib/` → declarations only; all callers are under `test/`.
- `lib/features/resource_studio/presentation/controllers/resource_capacity_controller.dart:133-138` — `dispose()` marks `_disposed` and calls the (no-op) `_runtime.dispose()`; no enqueue on leave.
- `resource_capacity_controller.dart:93` — `unawaited(_runQueue(...))` runs while the user is still on the page; nothing queues on exit.

**Trigger conditions**

Any workflow that does not press 生成压缩候选: growing a resource past `worldviewNominalCharacters`, or leaving the Studio after editing. Also `ResourceLimits.compressionTriggerContextTokens` / `compressionTriggerFillRatio` are never consulted.

**Actual impact**

- `phase-08-capacity-and-compression.md:11` ("手动压缩**及离开编辑器后的后台 compression job**") is only half delivered.
- The user's goal items "Automatic Compression Trigger … 阈值可配置" and "Context Compression … 避免一次发送全部历史" have no runtime effect: `CompressionThresholds` is inert.
- Capacity tracking is effectively a read-only display; the "support very large resources" objective is not achieved automatically.

**Root cause**

The trigger policy was implemented as a pure, testable library (good) but no composition-root integration was written: no hook on Studio leave / resource switch / app start, and no scheduler owning `drain`.

**Recommended fix**

Add an explicit trigger on leaving the editor (or on Studio dispose/resource switch) that runs `evaluateResource(measuredSnapshot)` and, when `shouldCompress`, calls the non-blocking enqueue path; and/or a bounded background drain on app start. Keep it non-blocking (the enqueue path already is) and respect the dedup index. If Phase 8's scope is intentionally limited to manual + queued, the phase document and STATUS must be corrected instead — the current text claims the background job.

**Verification method**

Call-site enumeration (greps above). The non-blocking *property* of `enqueueForResource` is implemented and tested ("queueing never calls the model"); what is missing is any trigger, so the acceptance line "离开编辑器仅排队，不阻塞导航" has no production path to exercise.

**Affected files**

`resource_studio_page.dart`, `resource_capacity_controller.dart`, `riverpod_providers.dart`, `resource_capacity_service.dart` (unused trigger API)

**Recommended owner**

executor Agent + 方案 Agent (decide whether the trigger belongs to Phase 8 or Phase 9's revision boundary)

---

### BUG-004

**Severity: Major**

**Description**

A compression result that is genuinely shorter than the original but larger than the target budget is rejected as a validation failure and **discarded** — no candidate row is stored, the original is kept, and the attempt is consumed. Combined with `compressionTargetRatio = 0.6` and BUG-002, a realistic partial reduction produces a permanently failed job.

**Location**

- `lib/domain/resources/resource_compression.dart:528-533` — `overBudget` is added as a validation issue.
- `lib/application/resources/compression_coordinator.dart:319-326` — any issue ⇒ `_finish(running, failed, …)`; the compressed text is dropped (no `insertCandidate`).
- `lib/domain/resources/resource_limits.dart:83` — `compressionTargetRatio = 0.6` (and `maxCompressionAttempts = 2` at `:65`).
- Test blind spot: every positive fixture returns a trivially short string (`compression_pipeline_test.dart` uses `'压缩结果'`, `'压缩后的摘要正文'`, `'重启后压缩结果'` against 800-char originals), so the accept/reject boundary is never exercised with a realistic ratio. `resource_compression_test.dart`'s "fails when the result exceeds its budget" pins the rejecting behavior without asserting what happens to the work.

**Trigger conditions**

A model returns a faithful 25–35% reduction (e.g. 800 → 600 chars) for an 800-char source, where `nodeTargetCharacters(800) == 480`. Reproduced by any real summarization of dense content.

**Actual impact**

- Normal reductions yield no candidate; only aggressive ≤60% reductions can ever succeed.
- Each such "failure" consumes one of the two attempts, and the retry is unreachable (BUG-002), so the job ends permanently failed with a reason the user never sees.
- The spec's step 5 wording ("不满足目标时**报告原因**", `phase-08-capacity-and-compression.md:20`) implies the result should still be reported as a candidate with a reason, not deleted. The implementation reports the reason but throws away the output.

**Root cause**

The budget was modelled as a hard acceptance gate on a single pass rather than a soft goal with a recorded shortfall. The phase document separates "失败保留原稿" (hard failure) from "不满足目标时报告原因" (soft shortfall); the code collapses both into one failure path.

**Recommended fix**

Store the below-target result as a candidate flagged with `didNotReachTarget` / a `validation_message` stating the shortfall (keeping `validation_state = validated` only for the budget-met case, or adding a third state), and let the caller decide. Reserve hard rejection for the properties that must hold: strictly shorter than the original, non-empty, retention satisfied. Add a test for "0.7× of the original must still yield a candidate with a reported shortfall".

**Verification method**

`resource_compression.dart:528-533` + `compression_coordinator.dart:319-326`; fixture inspection of `compression_pipeline_test.dart` shows no realistic-ratio case.

**Affected files**

`resource_compression.dart`, `compression_coordinator.dart`, `resource_limits.dart`, `compression_job_repository.dart`

**Recommended owner**

executor Agent; the acceptance semantics should be re-confirmed with the 方案 Agent against `phase-08-capacity-and-compression.md:20`.

---

### BUG-005

**Severity: Minor**

**Description**

`drain` processes queued jobs **globally**, not for the resource the user acted on. A manual compression on resource A can consume the drain budget with resource B's jobs, and the resulting counts are displayed as A's.

**Location**

- `lib/application/resources/compression_coordinator.dart:207-210` — `findJobsByStatus(CompressionJobStatus.queued, limit: limit)`; no `resource_id` filter.
- `lib/application/resources/compression_job_repository.dart:177-190` — `findJobsByStatus` filters only by status, ordered `created_at ASC` globally.
- `lib/features/resource_studio/presentation/controllers/resource_capacity_controller.dart:104-114` — the message is built from the global progress and attached to resource A's state.

**Trigger conditions**

Queue jobs for resource B (e.g. by opening B's Studio and pressing 生成压缩候选, or any future automatic trigger), then press the button on resource A. `maxJobsPerDrain = 4` is shared.

**Actual impact**

- A's jobs may never run while B's jobs are reported as "已生成 N 个压缩候选" on A's panel.
- With BUG-003's background trigger this becomes routine rather than exceptional.

**Root cause**

`drain` was designed as a global queue worker, but the only production trigger is resource-scoped, so the two contracts disagree.

**Recommended fix**

Add an optional `resourceId` filter to `findJobsByStatus` / `drain`, and have the Studio's manual entry pass the resource it is operating on (a global worker can still be added later for the background case).

**Verification method**

`compression_coordinator.dart:207`, `compression_job_repository.dart:177-190`.

**Affected files**

`compression_coordinator.dart`, `compression_job_repository.dart`

**Recommended owner**

executor Agent

---

### BUG-006

**Severity: Minor**

**Description**

Cancelled jobs and "nothing to compress" jobs are counted as failures and surfaced to the user as errors.

**Location**

- `lib/application/resources/compression_coordinator.dart:214-222` — `final ok = await _runJob(...)`; `else failed++` regardless of the terminal status the job actually reached.
- `lib/application/resources/compression_coordinator.dart:281-284` and `:288-295` and `:303-306` — cancellation and "目标节点没有可压缩的正文" both return `false`.
- `lib/features/resource_studio/presentation/controllers/resource_capacity_controller.dart:107-117` — `failedJobs > 0` ⇒ `ResourceCapacityViewStatus.failed` + `'${failedJobs} 个压缩任务失败，原稿保持不变'`.

**Trigger conditions**

Cancel a run via `GenerationTaskHandle`, or enqueue a target whose content was emptied/removed before the drain (e.g. the section was edited between enqueue and drain, so `_buildRequest` returns null → the job is marked `cancelled` but counted as failed).

**Actual impact**

Benign cancellations are reported to the user as failures, and the panel enters the failed state (`isWorking` false but `status == failed`), which is misleading diagnostics for a normal user action.

**Root cause**

`CompressionRunProgress` has no cancelled bucket; `_runJob`'s boolean return conflates "did not succeed" with "job failed". `CompressionJobStatus.cancelled` exists but is not represented in the progress report.

**Recommended fix**

Add a `cancelledJobs` counter to `CompressionRunProgress` (and a `skippedJobs` counter if "no compressible content" should be distinct), and have the controller treat `failed > 0` as the only failure condition.

**Verification method**

`compression_coordinator.dart:214-222`; `resource_capacity_controller.dart:107-117`.

**Affected files**

`compression_coordinator.dart`, `resource_capacity_controller.dart`

**Recommended owner**

executor Agent

---

### BUG-007

**Severity: Minor**

**Description**

There is no status compare-and-set and no claim when `drain` picks up a job, so two overlapping drains can double-call the model, resurrect a `failed` job, and under-count attempts.

**Location**

- `lib/application/resources/compression_job_repository.dart:159-174` — `updateJob` writes `status`/`attempts` unconditionally `WHERE job_id = ?`.
- `lib/application/resources/compression_coordinator.dart:270-279` — `running` is derived from the caller's stale in-memory job copy and written blindly; there is no `WHERE status = 'queued'` guard.

**Trigger conditions**

Two drains overlapping on the same queued job: e.g. the button pressed while a `dispose`-surviving `_runQueue` from the previous page instance is still in flight. Because the second drain read the job before the first wrote `running`, it will write `running` again (overwriting a terminal `failed`/`succeeded`) and then write its own terminal state; `attempts` is written as `1` twice.

**Actual impact**

- Duplicate LLM calls (cost) for the same job.
- A failed job can be silently resurrected by a stale drain (the failure reason is lost).
- `attempts` can under-count, weakening the retry budget.
- Today: low reachability (one Studio page; `requestCompression` guards on `working` before its first `await`). It becomes reachable as soon as BUG-003 adds an app-start/background drain alongside the manual button.

**Root cause**

Job claiming is in-memory only; durability is a plain unconditional update. Phase 8's own invariant "同一目标同时只有一个未结束任务" is enforced by an index for *insertion* but not for *execution*.

**Recommended fix**

Claim atomically: `UPDATE resource_compression_jobs SET status='running', attempts=attempts+1, updated_at=? WHERE job_id=? AND status='queued'` and skip the job when 0 rows are affected; make `updateJob` transitions conditional on the expected source status.

**Verification method**

`compression_job_repository.dart:159-174`; `compression_coordinator.dart:270-279`. Not reproduced dynamically (requires two simultaneous drains, which the current single-page UI does not produce); reachability argument is based on the call graph.

**Affected files**

`compression_job_repository.dart`, `compression_coordinator.dart`

**Recommended owner**

executor Agent (before any background scheduler lands)

---

### BUG-008

**Severity: Minor**

**Description**

The cached-capacity read path returns a wrong revision count and recomputes status from stale characters, and the Studio prefers the cache over a fresh measurement — so the displayed 容量状态 can disagree with the database. `capacity_status` is written but never read (dead column).

**Location**

- `lib/application/resources/resource_capacity_repository.dart:309` — `historicalRevisionCount: 0` hardcoded in `readCachedResource` (a measured snapshot reports the real attempt count, `:163`).
- `lib/application/resources/resource_capacity_repository.dart:286,328` — `capacity_status` is written (`:328`) and selected (`:286`) but never consumed; `:310` recomputes the status from `measured_char_count`.
- `lib/features/resource_studio/application/use_cases/resource_capacity_runtime.dart:44-45` — `summarize()` returns the cache whenever it exists.
- `lib/application/resources/compression_job_repository.dart:221` — `'applied_at': null`, always.
- `lib/features/resource_studio/presentation/widgets/resource_capacity_panel.dart:128` — the panel renders `历史版本 ${snapshot.historicalRevisionCount}`, which is therefore always `0` after the first paint.
- No write path invalidates the cache; only the explicit 刷新容量 button calls `measure` (`resource_capacity_controller.dart:48-68`).

**Trigger conditions**

Open the Studio for a resource measured earlier, then edit/generate content, then reopen the Studio. The panel shows the previous character count, the previous section/part counts and `历史版本 0`.

**Actual impact**

User-visible incorrect state (wrong capacity chip band, wrong revision count) on a feature whose purpose is to display capacity state. No *trigger* mis-decision today, because the trigger API is unwired (BUG-003) and the coordinator measures sections fresh (`compression_coordinator.dart:117`); it becomes a real wrong-trigger bug the moment the cached snapshot is fed into `evaluateResource`.

**Root cause**

The cache is a projection with no invalidation contract; the read path reconstructs a partial snapshot (revision count defaulted) instead of marking unknown fields unknown.

**Recommended fix**

Either make the Studio measure (README: capacity is cheap — a bounded statement count) or invalidate the cache on content mutation and populate every field; remove `capacity_status` or consume it; and if `historicalRevisionCount` cannot be derived from a cached read, represent it as unknown rather than `0`.

**Verification method**

`resource_capacity_repository.dart:286,299-311,328`; `resource_capacity_runtime.dart:44-45`. The audited suite only asserts cache *staleness is expected* (`resource_capacity_service_test.dart` "a cached value is advisory and a re-measure sees new content"), never that the UI refreshes.

**Affected files**

`resource_capacity_repository.dart`, `resource_capacity_runtime.dart`, `resource_capacity_controller.dart`, `resource_capacity_panel.dart`

**Recommended owner**

executor Agent

---

### BUG-009

**Severity: Minor**

**Description**

`NodeStatus.archived` is handled inconsistently: compression treats archived Sections/Parts as in-scope targets, while context assembly excludes archived Sections.

**Location**

- `lib/application/resources/compression_coordinator.dart:129-170` — the section/part loops filter only `snapshot.isComplete`, size and `isDeleted`; no `status != archived` check. `readSections`/`readParts` filter `deleted_at` only.
- `lib/application/resources/resource_context_compressor.dart:206-207` — `sections.where((section) => section.status != NodeStatus.archived)`.
- `lib/application/resources/resource_capacity_repository.dart:84-86,128-130` — archived parts are counted into `totalCharacters` (so they also drive the overflow/elastic status and the trigger).

**Trigger conditions**

A resource containing an archived Section or archived Parts (frozen `NodeStatus.archived` semantics) is measured and compressed.

**Actual impact**

LLM cost and candidate rows are spent on non-canon content; two Phase 8 components disagree about which nodes are in scope, so a candidate can cover content that the context assembler would never send. No data corruption (candidates are not applied).

**Root cause**

No single written rule for "which nodes participate in compression". `archived` was interpreted differently in each component.

**Recommended fix**

Decide one rule (recommended: skip `archived` nodes for compression targets, keep counting them for capacity) and encode it in one place — e.g. a shared predicate or an explicit filter in `enqueueForResource`.

**Verification method**

`compression_coordinator.dart:129-170` vs `resource_context_compressor.dart:206-207`; no test covers archived nodes in the compression path.

**Affected files**

`compression_coordinator.dart`, `resource_context_compressor.dart`, `resource_capacity_repository.dart`

**Recommended owner**

executor Agent

---

### BUG-010

**Severity: Minor**

**Description**

`ResourceContextAssembler`'s documentation and behavior disagree about "recent plot", and an unknown current-section id fails closed with no signal.

**Location**

- `lib/application/resources/resource_context_compressor.dart:187-188` — docstring: "How many of the **newest** sections count as recent plot".
- `lib/application/resources/resource_context_compressor.dart:210-217` — the boundary is `currentIndex - recentSectionCount`, i.e. the sections immediately *preceding the current one*, not the newest; when `currentIndex < 0` the boundary becomes `list.length`, so **nothing** is `recentPlot` and every section degrades to `historicalSummary` (which only enters the context if a compressed summary exists).
- `lib/application/resources/resource_context_compressor.dart:233-239` — a section with no `candidateSummaries` entry is therefore offered as full text under `historicalSummary` and can only be packed if the budget still allows.

**Trigger conditions**

(a) `currentSectionId` is stale/unknown (e.g. the selected section was deleted, or an ad-hoc caller passes a part id) → all content reclassified; (b) the current section is near the start of the resource (index 0–1) → effectively the whole resource becomes "recent".

**Actual impact**

Silent priority degradation: the packer can drop the content it was supposed to prioritize, with no returned signal beyond `droppedLabels`. Currently no production impact — `ResourceContextAssembler` has no production caller (`grep -rn "ResourceContextAssembler" lib/` → only this file) — but it is a latent defect for the Phase 10 wiring this component was written for.

**Root cause**

"Recency" was defined relative to the current section rather than to the section order, and the missing-current-section case was handled by a fallback that inverts the intent instead of surfacing it.

**Recommended fix**

Either redefine recency as "the last N non-current sections in canonical order" (matching the docstring), or restate the docstring as "the N sections preceding the current one"; and when `currentIndex < 0`, return a distinguishable result (or throw) instead of silently classifying everything as history.

**Verification method**

`resource_context_compressor.dart:210-217,233-239`; the audited test only covers the case where the current section exists (`resource_context_compressor_test.dart` "tags the current section and the resource state").

**Affected files**

`resource_context_compressor.dart`

**Recommended owner**

executor Agent (before Phase 10 wires it)

---

### BUG-011

**Severity: Minor**

**Description**

`CompressionCandidate.originalCharacters` is computed from the concatenated node text including `'\n\n'` separators, so it disagrees with the measured character counts shown in the same panel and overstates savings.

**Location**

- `lib/application/resources/compression_coordinator.dart:309-310` — `originalContent = request.nodes.map((node) => node.content.trim()).join('\n\n')`.
- `lib/application/resources/compression_coordinator.dart:334` — `originalCharacters: originalContent.length`.
- `lib/application/resources/compression_job_repository.dart:270-281` — `sumSavedCharacters` sums `original_char_count - compressed_char_count`, i.e. the overstated baseline.
- `lib/features/resource_studio/presentation/widgets/resource_capacity_panel.dart:124,128,155` — the panel shows `正文 N 字` (from capacity, a plain sum), `历史版本 …` and `采纳候选后约可减少 M 字` (from candidates).

**Trigger conditions**

Any section-scope job with ≥2 non-empty Parts: the stored original is `Σlen + 2(n−1)` instead of `Σlen`.

**Actual impact**

The two numbers shown to the user use different baselines, and `potentialSavedCharacters` is inflated by `2(n−1)` per candidate. Numeric inconsistency, not data loss.

**Root cause**

The concatenation exists only to build the validator's comparison text; the stored baseline was taken from that artifact rather than from the source measurements.

**Recommended fix**

Store `Σ node.content.length` (or the section's measured `characters`) as `original_char_count`, and keep the joined text local to validation.

**Verification method**

`compression_coordinator.dart:309-310,334`; `resource_capacity_repository.dart:97` (the measured sum).

**Affected files**

`compression_coordinator.dart`

**Recommended owner**

executor Agent

---

### BUG-012

**Severity: Minor**

**Description**

`insertJob` can leak an internal `StateError` verbatim into the UI when an insert is suppressed by the active-target index.

**Location**

- `lib/application/resources/compression_job_repository.dart:145-156` — `ConflictAlgorithm.ignore` + read-back by version; if the suppressed insert collided on `idx_compression_jobs_active_target` for a **different** `source_token`, the version read-back returns `null` and `StateError('压缩任务写入后无法读回：…')` is thrown.
- `lib/features/resource_studio/presentation/controllers/resource_capacity_controller.dart:94-98` — `errorMessage: error.toString()` renders it to the user.

**Trigger conditions**

Two concurrent `enqueueForResource` calls for the same target where the section's token changed between them (e.g. double-trigger while a generation commit bumps the section token).

**Actual impact**

An internal invariant message is shown as a user-facing error; the surrounding logic treats it as a fatal failure of the whole queue action even though the target simply already has an active job.

**Root cause**

The read-back assumes the only possible conflict is the version key, while a second unique index (active target) can suppress the row for a different key.

**Recommended fix**

On a suppressed insert, fall back to `findActiveForTarget` and return that job; only throw if neither lookup yields a row, and map internal errors to a domain exception before they reach the controller.

**Verification method**

`compression_job_repository.dart:145-156` + `database_service.dart:498-501`. Not reproduced dynamically (requires concurrent enqueue with a token change).

**Affected files**

`compression_job_repository.dart`, `resource_capacity_controller.dart`

**Recommended owner**

executor Agent

---

### INFO-001 — Dead / unused API surface

`enqueueNode` (`compression_coordinator.dart:176`) has no caller anywhere; `ICompressionJobRepository.findCandidateForJob` (`compression_job_repository.dart:45,229`) has no caller; `ResourceCapacityRepositoryImpl.cacheColumns` (`:66`) is unused; `CompressionRunProgress.fraction` (`:62`) is unused; `ResourceCapacitySnapshot.needsCompression` / `averagePartCharacters` / `SectionCapacitySnapshot.isCompressionCandidate` are test-only. Grouped as one item because the root cause is the same (API surface written ahead of wiring) and the fix is either to consume or delete before Phase 9.

### INFO-002 — Retention validation is model-self-attested

`CompressionValidator` verifies the `retained` lists the **model itself** supplies (`resource_compression.dart:546-588`), so a model that declares `retained: {entities: [], relationships: [], timeline: []}` passes any lossy output. The only non-self-attesting checks are `requiredTerms` (resource name + node titles that were present in the original, `compression_coordinator.dart:437-450`), `notCompressed` and `overBudget`. This is documented as a deliberate limitation and semantic grading genuinely needs a model; the audit records it so the limitation is not mistaken for retention verification. A cheap improvement is to require at least one declared item per non-trivial node, or to count retention-list size against the original's token count.

### INFO-003 — Prompt-injection surface in the compression instruction

`CompressionPromptBuilder.buildInstruction` embeds node bodies verbatim between `--- 节点 [id]：title ---` markers (`compression_prompt_builder.dart:90-95`) without the explicit un-trusted-content fencing Phase 5 uses for user instructions. Blast radius is limited (the response is strictly parsed into a candidate that is never applied), so this is informational; a hostile/odd body could still steer the produced summary.

### INFO-004 — Compression rows are never cleaned up

`resource_compression_jobs.resource_id` / `candidates.resource_id` have no FK to `resources` and no retention policy. Soft-deleting a resource leaves its jobs/candidates behind forever; orphaned `queued` jobs are self-healing (they fail at `_buildRequest` → `findResource == null` → `cancelled`) but the rows remain. Phase 9's trash/revision work and Phase 12's legacy removal need to own the cleanup rule.

### INFO-005 — Section-scope candidate has no per-Part mapping

A section-scope candidate stores one `compressed_content` blob keyed by the Section (`compression_job_repository.dart:207-226`) with no mapping back to individual Parts. Part content lives only on `resource_parts.content` (`resource_contracts.dart:15`), so Phase 9 cannot apply a Section candidate deterministically without inventing an allocation rule. Either the Phase 9 design must define the distribution (or forbid Section-scope application), or Phase 8 should prefer Part-scope candidates for anything that will be applied.

### INFO-006 — Generation-label change exceeds the D2 minimum

`_generateLabel` (`resource_studio_section_controls.dart:340-352`) changed from "重新生成 only when completed" to "重新生成 when the section has content". Only the *gating* change (`_canRegenerate`, `:353-356`) was required by Phase 7's D2 (option B); the label semantics change is additional, unrequested UI scope. It is defensible, but it is a Phase 7 UI behavior change beyond the mandate.

## Final Verdict

**Phase 8 is NOT accepted; Phase 9 remains BLOCKED.**

Reason:

- One BLOCKER: an interrupted compression job permanently deadlocks its target with no recovery path, and the phase's own acceptance criterion "应用重启后可恢复" is not met (BUG-001).
- Three MAJOR gaps against the phase's stated deliverables: no reachable retry for failed jobs (BUG-002), the automatic/background trigger is unwired (BUG-003), and realistic partial reductions are discarded with an untested boundary (BUG-004).
- The candidate-only safety boundary, the capacity measurement cost, and the v39 migration are genuinely correct and should be preserved by any remediation.

Recommended next step: a Phase 8 remediation pass (executor Agent) covering A1–A4 with regression tests for (a) recovery of a persisted `running` job, (b) UI-reachable retry after a failed job, (c) a non-blocking enqueue trigger on leaving the editor, and (d) a candidate produced from a realistic 0.7× compression ratio. A1–A4 should be re-verified independently; A5–A12 and INFO-001…006 can be scheduled but should be recorded in the remediation report rather than silently dropped.

**Audit scope note.** This audit was read-only. No code, test, configuration or documentation other than this report was written; no commit was created (HEAD remains `752b440`). Two claims are based on static call-graph/DDL evidence rather than dynamic reproduction and are marked as such in their findings: BUG-001 (interrupted-job deadlock, needs a process kill or a new fixture) and BUG-012 (concurrent-enqueue `StateError`). Everything else is backed by the commands listed under "Commands executed" and by file/line citations.
