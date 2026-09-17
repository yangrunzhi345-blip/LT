# Phase 6.1 Audit Report

## 1. Overall Result

**FAIL.** Commit `4060063c0ed346abe7ccc836936b03e65459972d` adds the expected contracts, repository, coordinator hooks, controller and tests, and its normal sequential path passes. It does not make a lifecycle-safe runtime: it permits concurrent Parts while persisting only one mutable active Part/status, cannot reliably stop a running generation, and ships a new persistent table without a new schema version or migration for installed v36 databases.

Audit baseline: `main` at `4060063`; the worktree was clean before this report. `git diff --check 4060063^ 4060063` reports trailing whitespace in `docs/phase-06.1-implementation-report.md`.

## Remediation Status

This document records the baseline audit. The following remediation change set
addresses P6-A1 through P6-A4: runtime generation is intentionally serialized
to one Part per session; every lifecycle callback is ordered and awaited; each
session owns and drains its cancellation handle; v37 installs the session table
through a versioned migration; and session creation/progress/status updates now
enforce identity, lifecycle, and progress invariants. Regression coverage adds
independent-Part serialization, live pause/cancel, duplicate-session, invalid
progress, mismatched-resource, and v36-to-v37 migration cases.

The production composition-root observation remains a planned integration
concern outside this runtime-hardening change; this service is still a
foundation until a later UI/composition phase consumes it.

## 2. Architecture Findings

- The domain contracts are pure Dart and `PartGenerationCoordinator` continues to use Phase 5's parser, accumulator, validator and atomic task commit. Invalid patches cannot reach `commitPartContent` through the reviewed path.
- The service/controller are not wired into a production composition root: repository-wide search finds their only construction sites in tests. They are an unconsumed foundation, not an executable application runtime yet.
- `StreamingLifecycleStateMachine` is not a strict version of the specified state diagram. It permits, for example, `committing -> receiving_patch` and `validating -> receiving_patch` (`streaming_generation_runtime_contracts.dart:103-120`), masking rather than preventing inconsistent order.

## 3. Critical Issues

### P6-A1

- **Severity:** Critical
- **Location:** `streaming_resource_generation_service.dart:143-307`; `part_generation_coordinator.dart:141,261-286,502-510,652-659`; `streaming_generation_runtime_contracts.dart:83-121`.
- **Problem:** One session has one `status`, current Part/task/attempt and shared `activePartStatus`, while the coordinator schedules up to two ready tasks concurrently. Sibling callbacks overwrite those fields. Streaming `onPatchReceived` and `onPartCommitted` callbacks are invoked without `await`, so their database transitions can finish after later validation/commit transitions.
- **Root Cause:** The runtime was layered on a parallel Part scheduler without serialising it or modeling several active Parts and a deterministic aggregate state reducer.
- **Impact:** Event order and persisted lifecycle state are nondeterministic; progress can be inaccurate and recovery can name the wrong in-flight Part. Broad state-machine transitions permit the corruption.
- **Recommended Fix:** Choose one explicit model. For a single-active-Part session, require runtime concurrency one and await every lifecycle callback. For parallel execution, persist per-task runtime state and reduce it atomically into an aggregate with a session lease/version check. Restore only valid state transitions.
- **Verify:** Add a barrier-controlled test with two dependency-free Parts, interleave patch/validation/commit callbacks, and assert deterministic events, valid transitions, correct attempt IDs and exact reopened progress.

### P6-A2

- **Severity:** Critical
- **Location:** `streaming_resource_generation_service.dart:374-428`; `resource_generation_task_repository.dart:445-478`; `part_generation_coordinator.dart:406-667`.
- **Problem:** Pause/cancel only cancel a `GenerationTaskHandle` supplied by that caller. The service retains neither the handle nor worker future created by `startGeneration`, so ordinary `cancel(sessionId)` cannot stop an existing request. It then cancels every unfinished task for the resource, while the original worker can continue into callbacks and failure handling.
- **Root Cause:** No session-owned execution registry, cancellation token, worker drain or session ownership on generation tasks.
- **Impact:** A session can show cancelled/paused while an LLM request runs and emits late events; it can race retry/recovery. Two sessions for one resource can cancel each other's work.
- **Recommended Fix:** Retain a handle/worker per session; make pause/cancel target it and await a defined stop/drain point. Guard post-request transitions with a session generation/lease token. Scope task cancellation to the owning session, or enforce one active session per resource transactionally.
- **Verify:** Block a completer after attempt start; cancel and pause while blocked, release it, and assert no content commit or post-terminal event, defined task/attempt status, and no effect on another session.

## 4. Data Integrity Findings

### P6-A3

- **Severity:** High
- **Location:** `database_service.dart:43,404-408,494-521,1872-1887`; `streaming_generation_session_repository.dart:70-103,107-131`.
- **Problem:** `resource_generation_sessions` is added to `createV36Schema`, but schema version remains 36 and the only v35→v36 migration never creates it. An installed Phase 5 database is already v36, so `onUpgrade` does not run. Repository-local lazy `ensureSchema` repairs it only when that repository is first used and duplicates schema ownership.
- **Root Cause:** Phase 6.1 reused Phase 5's schema version.
- **Impact:** Database version state is inaccurate; deployment, backup and migration guarantees do not describe the actual schema.
- **Recommended Fix:** Bump the schema, add an idempotent migration which creates the table/indexes, update fresh install, and retain one schema definition. Add FK or application validation for resource/blueprint/session bindings.
- **Verify:** Open a real pre-change v36 fixture through `DatabaseService`, assert new version/table/indexes and preservation of tasks/attempts; assert table existence before session repository construction.

### P6-A4

- **Severity:** High
- **Location:** `streaming_generation_session_repository.dart:107-131,195-291`; `streaming_resource_generation_service.dart:48-72,116-128`.
- **Problem:** `createSession` uses `ConflictAlgorithm.replace`, deleting and reinserting a caller-supplied duplicate ID. `updateSession` and `updateProgress` bypass state-machine/optimistic-concurrency checks and do not enforce `0 <= completed <= total`. Session creation does not validate that its resource belongs to its blueprint.
- **Root Cause:** Lifecycle rows are treated as generic mutable CRUD rather than ownership-bound state.
- **Impact:** Retried calls or stale workers can erase history or persist a session describing a different resource from the one generated.
- **Recommended Fix:** Reject duplicate IDs or implement explicit idempotent creation; validate blueprint/resource before start; use compare-and-set revision/lease updates enforcing lifecycle and progress invariants.
- **Verify:** Test duplicate create, mismatched blueprint/resource, stale concurrent updates and invalid progress; each must fail without altering the persisted session.

## 5. Concurrency Findings

Phase 5's task-level `startAttempt` lease prevents two attempts for one task, and `commitPartContent` atomically rejects stale/cancelled attempts. It does not protect the Phase 6 aggregate session. Concurrent siblings and multiple sessions still race over the session row or bulk resource cancellation (P6-A1/P6-A2). A session-level owner/lease is required.

## 6. Recovery Findings

`recoverInterruptedGeneration` resets Phase 5 `generating`/`validating` tasks and restarts them, but it cannot distinguish a still-live worker in the same process and it does not automatically process all `findInterruptedSessions` rows. Recovery is unsafe until worker ownership and cancellation barriers exist.

## 7. Test Coverage Assessment

The following command passed, along with `flutter analyze`:

```text
flutter test test/application/resources/streaming_generation_session_repository_test.dart test/application/resources/streaming_resource_generation_service_test.dart test/application/resources/streaming_resource_generation_controller_test.dart test/application/resources/database_migration_v36_test.dart test/domain/resources/streaming_generation_runtime_contracts_test.dart
```

All 23 targeted tests passed. Coverage is still insufficient: normal fixtures use dependent Parts and never exercise `maxConcurrency = 2`; cancellation is pre-cancelled before a worker starts; pause happens before generation; recovery addresses one manually selected session; and the migration test never asserts `resource_generation_sessions` on fresh install or upgrade.

## 8. Performance Assessment

The usual single-Part path avoids a database write per patch, but P6-A1's unawaited callback writes can queue behind high-frequency streaming and reorder state changes. The broadcast event stream emits every patch without a delivery policy. After lifecycle ordering is fixed, define bounded observer/UI delivery so network consumption remains independent of UI refresh.

## 9. Recommended Next Actions

1. Fix P6-A1 and P6-A2 together: establish ownership, cancellation semantics and a lifecycle model compatible with the chosen concurrency.
2. Deliver a versioned schema migration for P6-A3 before release.
3. Harden repository invariants in P6-A4.
4. Add the race, live cancellation/pause, recovery, duplicate-session and pre-change-v36 migration regressions described above.
5. Wire the approved runtime through the production composition root, repeat this audit, and remove the implementation-report trailing whitespace.
