# R01 Independent Acceptance Report

## 1. Baseline

```text
Acceptance Date: 2026-09-19
Acceptance HEAD: 3485fef1255f24089210fb27f8833c974df8c12b
origin/main: 3485fef1255f24089210fb27f8833c974df8c12b
Branch: main
Ahead / Behind: 0 / 0
Working Tree Before Acceptance Docs: clean
R01 Start HEAD: b412b8b780395e7339fd29bcf612d8c0438bfc1d
R01 Implementation Commit: 67ec88cc431cc8150f844b0397e72e1c0f201b9c
Schema: 43
Reviewer: R01 Independent Acceptance Agent
```

The implementation commit was reviewed separately from the later docs-only commits
`4ca946f` and `3485fef`.

## 2. Diff Reviewed

`b412b8b -> 67ec88c` changes five production and five test/fixture files:

- lifecycle: `streaming_generation_runtime_contracts.dart`;
- service: `streaming_resource_generation_service.dart`;
- ownership: `streaming_resource_generation_controller.dart`;
- production composition: `riverpod_providers.dart`, `main.dart`;
- regression coverage: lifecycle, completed-section regeneration, production recovery wiring,
  state-machine tests, and the R01 SQLite fixture.

No schema or migration file changed.

## 3. Finding Verification

### B1 - CLOSED

The state machine permits `completed -> generatingPart`. The verified production chain is:

```text
ResourceStudioPage
-> SectionControlController
-> SectionControlService.regenerateSection
-> beginLossyOperation
-> StreamingSectionRegenerationExecutor
-> shared StreamingResourceGenerationController.retryPart
-> StreamingResourceGenerationService.retryPart
-> SQLite session/task repositories
```

The real-SQLite success test starts with completed session/tasks/content, records the lossy-operation
revision, starts a new attempt, commits new content, returns the session to completed, and reads the old
content from the revision. The injected-failure test preserves that revision and leaves no
`session=completed + task=ready` split.

### M5 - CLOSED

`retryPart` catches coordinator failures and calls `_convergeAfterRegenerationFailure`. The helper
re-reads the session, checks `canTransition(current.status, failed)`, persists `error_message` when legal,
and emits `GenerationFailed` with the session id, resource id, failed part id, and original message.
Tests verify `failed`, persisted error text, event payload, and absence of a stuck in-flight session.

### M6 - CLOSED

`MainGate` reads `streamingGenerationRecoveryProvider`; that provider uses the production session
repository and shared service, calls `findInterruptedSessions`, and invokes
`recoverInterruptedGeneration(..., autoResume:false)` for every result. Task recovery precedes the
session transition to `recovering`, so task-repository failure leaves the original interrupted session
retryable. A fake completion counter remains zero until explicit `resumeGeneration`.

### N8 - CLOSED

Both no-active-run pause and cancel paths remove `_requestedStops` in `finally`. The subsequent run is
not poisoned by a stale stop request. MUT-A4 restores the leak and makes both regression tests fail.

## 4. Lifecycle Contract

`completed -> generatingPart` is the only R01 state-machine addition. Successful regeneration proceeds
through attempt/validation/commit and returns to `completed`. A thrown retry converges to `failed` when
that transition remains legal; a concurrently advanced state is not overwritten because convergence
re-reads current state and checks the state machine.

## 5. Failure Convergence

```text
retrySinglePart throws
-> re-read current session
-> legal current -> failed(error_message)
-> GenerationFailed(session/resource/part/message)
-> retryPart returns false
```

The completed-section failure test also verifies that the pre-operation revision remains readable.

## 6. Startup Recovery

The repository interrupted contract is based on `StreamingLifecycleStatus.isInFlight`: planning,
generatingPart, receivingPatch, validating, and committing. Recovery changes generating/validating tasks
to retryable state, then marks the session recovering. `autoResume:false` prevents `startGeneration` and
LLM calls. `ResourceStudioController` maps recovering to ready; the existing Continue action calls
`resumeGeneration`, which accepts recovering and explicitly starts the run.

## 7. Production Wiring

- Studio service: `streamingResourceGenerationServiceProvider`.
- Recovery service: the same provider instance.
- Studio session repository: `streamingGenerationSessionRepositoryProvider`.
- Recovery repository: the same provider instance.
- Section runtime: obtains `StreamingResourceStudioRuntime.controller` and `.sessionRepository`; it does
  not construct a second streaming service.

The production wiring test uses an unoverridden `ProviderContainer`, real SQLite, and the real MainGate.

## 8. Lifecycle Ownership

The Riverpod service provider creates the production service and owns its sole `ref.onDispose` call.
`StreamingResourceStudioRuntime.dispose` delegates to a controller configured with `ownsService:false`,
so invalidating/disposal of Studio runtime does not close the shared stream. Section runtime owns only
its `SectionControlService`, not the streaming service. No production constructor creates a second
streaming service. Container disposal is the terminal service owner; no reuse follows provider disposal.

## 9. Late Attempt Safety

`PartGenerationTaskRepositoryImpl.commitPartContent` reads `current_attempt_id` inside the transaction and
rejects a mismatched attempt before content commit. The T1/T2 late-response regression passes; MUT-A5
removes this guard and the regression fails.

## 10. Mutation Verification

All mutations were performed in an isolated `/tmp` repository copy.

| Mutation | Result |
| --- | --- |
| MUT-A1 remove `completed -> generatingPart` | DETECTED; state-machine and regeneration tests failed |
| MUT-A2 remove retry failure convergence | DETECTED; lifecycle and failure-path tests failed |
| MUT-A3 remove MainGate recovery read | DETECTED; production MainGate wiring test failed |
| MUT-A4 restore no-active-run stop leak | DETECTED; pause and cancel restart tests failed |
| MUT-A5 disable late-attempt token rejection | DETECTED; T1/T2 regression failed |
| MUT-A6 make Section runtime construct an independent service | SURVIVED; non-blocking TEST-GAP R01-A-TG1 |

MUT-A6 does not establish a production defect: the current provider code was independently traced and
does reuse the Studio controller/repository. It establishes missing regression sensitivity. R05 owns the
next production-wiring convergence work and must add an assertion that mutation-equivalent service
splitting fails.

## 11. Tests

```text
dart format --output=none --set-exit-if-changed .: PASS (497 files, 0 changed)
flutter analyze: PASS (No issues found)
R01 + existing targeted files: PASS (35 passed, 0 failed)
flutter test: PASS (1610 passed, 0 failed)
git diff --check: PASS
Schema: 43
```

## 12. Acceptance Criteria

```text
AC-R01-01 PASS  completed session regenerates
AC-R01-02 PASS  failed regeneration has no session/task half-state
AC-R01-03 PASS  exception converges and emits GenerationFailed
AC-R01-04 PASS  startup discovers interrupted sessions
AC-R01-05 PASS  startup uses autoResume:false
AC-R01-06 PASS  startup recovery makes zero LLM calls
AC-R01-07 PASS  recovering maps to ready and explicit resume works
AC-R01-08 PASS  no-active-run pause/cancel clears stale stop requests
AC-R01-09 PASS  superseded attempt cannot commit
AC-R01-10 PASS  Studio/Section use the same production service
AC-R01-11 PASS  provider owns disposal; Studio cannot prematurely close service
AC-R01-12 PASS  schema remains 43
AC-R01-13 PASS  flutter analyze
AC-R01-14 PASS  targeted tests, 35/35
AC-R01-15 PASS  full flutter test, 1610/1610
AC-R01-16 PASS  critical MUT-A1...MUT-A5 detected; optional A6 recorded
```

## 13. Findings

```text
BLOCKER: 0
MAJOR: 0
MINOR: 0
TEST-GAP: 1
INFO: 0
```

### R01-A-TG1 - Section/Studio single-service ownership lacks mutation protection

Severity: TEST-GAP (non-blocking).

Location: `production_streaming_recovery_wiring_test.dart` and
`sectionControlRuntimeProvider` in `riverpod_providers.dart`.

Trigger: change Section runtime to construct a separate session repository/service/controller while
leaving Studio and recovery providers unchanged.

Observed: all three production wiring tests still pass. Expected: a wiring test should fail because the
Section runtime no longer shares active-run maps, stop requests, or event stream with Studio/recovery.

Root cause: the tests verify service provider identity, startup activation, DB recovery, UI mapping, and
Studio disposal, but never exercise Section regeneration through the production provider or assert its
shared controller/event stream behavior.

Why current tests miss it: Section runtime is not read in this test file. Repair direction: in R05, add a
production ProviderContainer test that performs Section regeneration and observes the same Studio service
event stream, or expose a narrow diagnostic identity solely for composition tests. Required regression:
MUT-A6 must fail without overriding the streaming service/session/recovery providers.

This gap does not block R01 because current production composition was directly verified and the optional
mutation did not reveal an implementation defect; it is explicitly handed to R05, whose scope includes
production/test wiring convergence.

## 14. Final Verdict

```text
ACCEPTED
```

## 15. Program Handoff

```text
R01 status: ACCEPTED
R04/R05 R01 dependency: satisfied; status may become PLANNED
Next recommended action: R02 - Atomic Commit & Content Write Integrity
```
