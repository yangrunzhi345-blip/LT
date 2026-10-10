# P0 — Core Business Reliability & Integration Recovery

Status: ACCEPTED (Integrated Single-Agent Full-Cycle)
Acceptance Mode: Integrated Single-Agent Full-Cycle (user requested one continuous
audit → reproduce → fix → verify run).
Real device validation: REAL DEVICE NOT VERIFIED (no Android device / device DB / live
LLM credentials supplied). No push, tag, release, version bump or database migration is
performed by this task.

## 1. BASELINE

- Working tree at start: clean (`git status --short` empty).
- Branch: `main`; `HEAD = bbb0028c157f67113d29e30acbdee94ff237a713`.
- `origin/main = bbb0028c157f67113d29e30acbdee94ff237a713` (synced; no ahead/behind).
- Toolchain: Flutter 3.44.8 / Dart 3.12.2 (stable), `sqflite_common_ffi` for real-SQLite
  tests.
- Baseline full suite (before any change): `flutter test --no-pub` → **3 686 passed,
  2 skipped, 0 failed**.
- Historical context preserved (not overwritten): the reported failures were worked on in
  `fix/android-adventure-readiness` and merged to `main` via PR #4
  (`f7c1dd4` → `c155b9e`), documented in
  `docs/codex/android-adventure-start-regression.md`,
  `docs/codex/adventure-compression-budget-p0.md` and
  `docs/codex/character-generation-budget-regression.md`. This task treats those as
  history and independently re-verifies the current code rather than trusting the docs.

## 2. CALL CHAIN (verified against current source, not docs)

```
Studio/creation entry
  → ResourceCreationPipeline.create / createBatch / reuse branches
      lib/application/resources/resource_creation_pipeline.dart:180,204,236,393,497
  → AI generation: StreamingResourceGenerationService.generate
      → PartGenerationCoordinator.generateAllParts / retrySinglePart
          lib/application/resources/part_generation_coordinator.dart:265,775
          → remainingBudget + soft target (min(request, ≤3000 ceiling))
            lib/application/resources/resource_generation_task_repository.dart:419
            lib/domain/resources/resource_generation_protocol.dart:210
          → commitPartContent (atomic: budget + CAS body + revision + completion)
            lib/application/resources/resource_generation_task_repository.dart:447,525
      → on generation completed: _prepareAssemblyAfterCompletion
          lib/application/resources/streaming_resource_generation_service.dart:129,553,977
  → Readiness authority: AssemblyReadinessCoordinator.prepare
      lib/application/resources/assembly_readiness_coordinator.dart:177
      • normal/elastic head → build immutable assembly → publish → index → ready
      • overflow head → CompressionCoordinator.enqueueForResource(partOnly) →
        CompressionBackgroundWorker.process → _reconcileCompression
          lib/application/resources/assembly_readiness_coordinator.dart:246,283,457
          lib/application/resources/compression_worker.dart:66
      • retry / startup recovery → retryPreparation / recoverInterrupted
          lib/application/resources/assembly_readiness_coordinator.dart:434,558
  → Start gate: AdventureReadinessGate.resolve / enforceAndFreeze
      lib/application/adventure/adventure_readiness_gate.dart:187,387
  → Session: ChatProvider.startAdventureWithConfig → AdventureProvider.createAdventure
      lib/providers/chat_provider.dart:646
      lib/providers/adventure_provider.dart:302,436
```

Authority summary: the frozen revision/state is the sole content authority; the persisted
`resource_assembly_readiness` row (CAS by `attempt_token`) is the sole readiness authority;
`AdventureStartGuard` dedupes concurrent starts; the SQLite commit transaction is the sole
budget authority.

## 3. ROOT CAUSE (confirmed, code + reproduction)

### RC-1  Doomed compression jobs for targets above the bounded input window  (FIXED)

A single compression request is hard-bounded to
`ResourceLimits.maxCompressionInputCharacters = 12000`
(`lib/domain/resources/resource_limits.dart:87`,
`lib/application/resources/compression_prompt_builder.dart:113`). But
`CompressionCoordinator.enqueueForResource` queued **every** non-empty, non-archived Part
regardless of size (`compression_coordinator.dart:181`). For a Part larger than the window,
`_buildRequest` then called `CompressionPromptBuilder.assertWithinInputBudget` and threw
(`compression_coordinator.dart:534`).

Consequences (all reproduced, see §4):
- A job that can **never** succeed was created and persisted.
- Its failure was classified as the **retryable** `compressionFailed`
  (`assembly_readiness_coordinator.dart:504`), so the UI invited retrying; each retry burned
  the attempt budget (`maxCompressionAttempts = 2`) and then ended in
  `compressionBudgetExhausted`. The resource could never reach `ready` without a manual
  edit, and the user was never told *why*.
- This is exactly the reported symptom class "冒险启动失败 / 无法确认资源就绪": a legitimate
  saved resource permanently blocked with a misleading retryable failure.

Historical introduction: the input-bound check exists only at request-build time; no
enqueue-time guard was ever added. `git log` shows the enqueue loop predates the bound;
`7c2d7d9`/`c155b9e` added the bound-side enforcement and the budget/readiness closure but
did not add an enqueue-time guard.

Reachability: a Part > 12 000 characters is not produced by AI generation (Part ceiling
3 000) nor by ≥24 000-rejecting import, but **is** reachable from pre-validation legacy data
(a single very long card field, e.g. `description`/`system_prompt`, inside a resource that
was saved above the absolute budget before the card-length validator existed — the reported
Android cards were ~25 200 characters). The bug is a legacy-data reliability gap, not the
primary generation path.

### RC-2  Re-verification of the previously reported defects (already fixed; confirmed)

- **Compression never closes / stuck `preparing`**: fixed by drain-all + reconcile with
  explicit terminal classification (`assembly_readiness_coordinator.dart:283,457,558`).
  Verified by reproduction and existing suites.
- **20 000-character budget cannot start**: fixed by per-Part soft target + atomic aggregate
  budget enforcement (`part_generation_coordinator.dart:988`,
  `resource_generation_task_repository.dart:525`). Verified: 20 000 actual ≤ 24 000 absolute
  → normal/elastic → ready.
- **Save/retry omitting readiness**: reuse/retry branches now run preparation
  (`resource_creation_pipeline.dart:204,236,497`;
  `streaming_resource_generation_service.dart:977`).

No reproducible BLOCKER/MAJOR defect was found in RC-2 beyond RC-1.

## 4. FAILURE REPRODUCTION

All reproductions use **real sqflite_common_ffi SQLite**, the production
`AssemblyReadinessCoordinator` + `CompressionCoordinator` + `CompressionBackgroundWorker` +
`CompressionPublisher` + `AdventureReadinessGate` (`test/helpers/phase10_fixture.dart`).
Only the external model boundary is a fixed fake.

### Before the fix (differential probe, then deleted)

Resource `huge_single_part`: two Parts of 12 001 characters each (total 24 002 > absolute
24 000 → overflow; every Part above the 12 000 window). `coordinator.prepare(id)` produced:

```
state = failed
failureReason.code = compressionFailed          (RETRYABLE)
jobs = [ failed:1/2 ]                            (a doomed job)
```

### After the fix

```
state = failed
failureReason.code = compressionNoTargets         (ACTIONABLE)
jobs = []                                          (no doomed job)
```

`compressionNoTargets` localizes to "没有可安全压缩的正文段落，请编辑资源以减少字数。"
(`lib/l10n/app_zh.arb:3946`), i.e. the user is told to edit/reduce instead of being invited
to retry forever.

### Why existing tests missed it

The existing compression suites (`compression_pipeline_test`, `compression_worker_test`,
`compression_concurrency_test`, `adventure_compression_lifecycle_sqlite_test`) exercise
targets **below** the 12 000 window (test fixtures split bodies at ≤2 800), and
`compression_pipeline_test:83` only asserts that `assertWithinInputBudget` rejects an
oversized window at the *builder* level. No test drove an oversized Part through
**enqueue → queue → readiness classification**, so the missing enqueue-time guard was never
observed. This is a *combination/cross-module* coverage gap (enqueue × model-bound ×
readiness classification), not a missing unit.

### Negative/mutation probe

Temporarily replacing the new guard with `if (false && …)` makes the new regression test
fail (`Expected: empty / Actual: [<a job>]`); restoring the guard makes it pass. All
mutations were reverted (`grep -n "if (false" lib/application/resources/compression_coordinator.dart`
→ none).

## 5. FIX

One production file, +11 lines, behavior-preserving for every other path:

`lib/application/resources/compression_coordinator.dart:195`

```dart
// One compression request carries a bounded window
// (`ResourceLimits.maxCompressionInputCharacters`). A single Part above
// that bound cannot be compressed as one request and the builder would
// reject it, so it is deliberately never queued: a doomed job would
// otherwise be reported as a retryable failure and burn its attempt
// budget without any chance of success. Such content must be
// edited/reduced by the user (surfaced as `compressionNoTargets`).
if (part.content.length >
    ResourceLimits.maxCompressionInputCharacters) {
  continue;
}
```

Design rationale:
- The documented contract already requires such content to be *edited/reduced* rather than
  silently truncated or split (`docs/codex/adventure-compression-budget-p0.md`, "Remaining
  limits"). No split/guess is introduced, preserving the "one Part = one atomic
  compression" invariant.
- Because the oversized target is simply not a queueable target, the existing empty-queue
  path produces `compressionNoTargets`, an already-localized, actionable terminal state.
  No new diagnostic code or localization is needed.
- No check is deleted or weakened; `assertWithinInputBudget` remains as defence in depth.
- Section-scope jobs are unaffected (a section job is only created when the section is
  already ≤ the window). `enqueueNode` (Studio manual single-node entry) is intentionally
  left unchanged — it has no content in hand and its failure is already explicit; recorded
  as a residual limitation in §10.

## 6. TESTS

Added to `test/application/resources/adventure_compression_lifecycle_sqlite_test.dart`
(real SQLite, production wiring):

1. **`a Part above the bounded compression window is never queued and fails explicitly`**
   — asserts no job is created, readiness is a terminal `compressionNoTargets`, and the
   original oversized text is preserved unchanged. (Regression for RC-1.)
2. **`two overflowing resources prepare concurrently without cross-talk`** — two
   overflowing resources prepared concurrently via `Future.wait`; asserts each reaches its
   own `compressionApprovalRequired`, each drains all its own jobs, no job is left active,
   and every candidate is attributed to the resource that produced it. (Closes the
   enumeration gap "多资源同时准备 → 不发生竞态覆盖或错误关联".)
3. **`gate recovers a failed compression through retry, approval and re-resolve`** — through
   the real gate: first preparation fails (one bounded request fails) → gate refuses start;
   gate retry → `preparing`; approve candidates → gate resolves `ready` with a non-empty
   assembly revision. (Closes "失败后重试及恢复" through the user-facing boundary.)

Existing suites retained and re-run (no assertions removed or weakened).

**Existing-test fixture correction (with evidence).** The fix changed one pre-existing
fixture whose intent was *not* the oversized case:
`test/application/resources/phase10_index_and_compression_test.dart` →
`OVERFLOW queues proposals but missing worker fails explicitly`. It built its overflow from
a **single 61 000-character Part** (above the 12 000 window) and asserted
`resource_compression_jobs` is non-empty plus `compressionUnavailable`. Before the fix that
non-empty assertion only passed because a doomed job was created; the test's stated intent
("queues proposals") therefore depended on the very defect being fixed. The fixture now uses
six bounded Parts (~10 100 each; total 60 600 > worldview absolute 60 000 → overflow, every
Part ≤ the window), so proposals are genuinely queued and the missing-worker path still fails
closed with `compressionUnavailable`. No assertion was relaxed or removed. The sibling tests
that use a single 61 000-character Part
(`assembly_readiness_coordinator_test.dart:63`, `phase10_index_and_compression_test.dart:201`)
are unaffected because they attach **no** compression link, so they fail fast before enqueue.

## 7. INTEGRATION / CAPACITY / RECOVERY verification

Reproduced through the production chain (real SQLite; see §4 evidence and the new tests):

- **Capacity:** 8 000 → normal → ready, no compression; 20 000 → normal → ready, no
  compression; 21 000 → elastic → ready, no compression; 24 000 → elastic → ready;
  24 001 → overflow → compression, recoverable to ready via approval.
- **Concurrency:** two overflowing resources prepared concurrently do not share jobs,
  candidates or readiness rows (new test).
- **Failure / retry:** a failed compression is a terminal, retryable-looking failure; the
  gate retry + approval + re-resolve loop reaches `ready` (new test); retry exhaustion is a
  stable terminal with an actionable message.
- **Interrupt / restart:** `recoverInterrupted` + `worker.start()` resume queued compression
  and fail-closed any orphaned `preparing` row (existing
  `adventure_compression_lifecycle_sqlite_test` worker-restart case).
- **Edited head after failure:** editing an overflow resource below capacity and re-resolving
  through the gate yields ready (verified in the audit probe).

## 8. ENGINEERING VERIFICATION

- `dart format --output=none --set-exit-if-changed lib test`: PASS, 847 files, 0 changed.
- `flutter analyze --no-pub`: PASS, no issues.
- Targeted suites: `adventure_compression_lifecycle_sqlite_test` **21 passed**;
  compression/pipeline/worker/concurrency/readiness combined **64 passed**.
- Full `flutter test --no-pub`: **PASS — 3 689 passed, 2 skipped, 0 failed** (baseline was
  3 686 passed / 2 skipped; +3 new tests, one existing fixture corrected without weakening
  assertions). The 2 skips are the pre-existing opt-in real-TTS and Chrome-only cases.
- `git diff --check`: PASS.

## 9. REGRESSION

- No public interface, database schema, migration or persistence contract changed.
- The change only removes a guaranteed-useless job from a queue; every other enqueue path
  (section scope, normal prose, structured-JSON skip, min-node threshold, de-duplication by
  version/target) is untouched.
- All pre-existing compression, readiness, generation-budget and adventure-start suites pass
  unchanged.

## 10. LIMITATIONS

- **REAL DEVICE NOT VERIFIED**: no Android device, no device database and no live LLM
  credentials were supplied. Real-model compression success rate, real device
  generation/start and on-device recovery remain unverified; this report does not claim
  otherwise.
- The reported user assets' exact counts, Part distribution and job rows are unknown; the
  reproductions are deterministic synthetic fixtures, not measurements of user data.
- A Part above the bounded window still requires the user to edit/reduce; the fix makes this
  explicit and immediate rather than silently retryable, but it does not make such content
  compressible.
- Studio manual single-node compression (`enqueueNode`) is not guarded at enqueue time.

### INFO (observed, deliberately not changed)

- The automatic compression trigger `CompressionTriggers.evaluateResource` classifies by
  `snapshot.totalCharacters` **including archived parts**
  (`lib/domain/resources/resource_compression.dart:484`), while the readiness authority
  classifies by **active** characters **excluding archived**
  (`assembly_readiness_coordinator.dart:780`). For a resource whose overflow depends on
  archived content, `onEditorLeave` can therefore queue an opportunistic compression the
  gate does not require. This is not a correctness defect: the readiness path explicitly
  self-heals such a legacy `preparing`/`compressionPending` row through a real `prepare`
  when current capacity is not overflow (`assembly_readiness_coordinator.dart:475`), and the
  total-based trigger is asserted by `test/application/resources/resource_capacity_service_test.dart:377`.
  It is recorded as a consistency observation only; changing it would alter tested trigger
  semantics and is outside the minimal-fix scope.

## 11. CHANGED FILES

Production (1 file, +11 lines, no interface/schema change):

- `lib/application/resources/compression_coordinator.dart` — skip queuing a Part target
  above the bounded compression input window.

Tests (2 files):

- `test/application/resources/adventure_compression_lifecycle_sqlite_test.dart` — 3 new
  integration/regression tests.
- `test/application/resources/phase10_index_and_compression_test.dart` — fixture corrected
  to a bounded multi-Part overflow (intent preserved, assertions unchanged).

Docs (1 file): this report.

## 12. FINAL STATUS

**ACCEPTED (Integrated Single-Agent Full-Cycle)**, scope-limited and with
**REAL DEVICE NOT VERIFIED**.

- Confirmed defect RC-1 reproduced, fixed, and covered by a failing-then-passing regression
  test with a mutation probe.
- The previously reported P0 failures (compression closure, 20 000-budget start, save/retry
  readiness hooks) were independently re-verified as already fixed at `HEAD`.
- BLOCKER = 0, MAJOR = 0 for the verified scope; the one confirmed residual reliability
  defect is fixed.
- Unverified items are listed in §10 and are not claimed as resolved.
