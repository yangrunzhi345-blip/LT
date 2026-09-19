# R04 Independent Acceptance Report

## 1. Baseline

```text
Acceptance Date: 2026-09-19
Acceptance HEAD: 029f1ccc5c139d67aaa7ae2b85e96b2667b6a713
origin/main: 029f1ccc5c139d67aaa7ae2b85e96b2667b6a713
Branch: main
Ahead / Behind: 0 / 0
Working Tree Before Acceptance Docs: clean
R04 Start HEAD: bfc57f0e7820eb485f17f93a2b4c0183c31b5df3 (R03 end)
R04 Implementation Commits:
  ea1d721db0c4dbb9a92d8efe36e1245e9d7c1693  A/B/C/D production + tests
  b92a5694155f535f38d04c714ca2c9e613df8c71  B7/D11 probe strengthening
Schema: 43
Reviewer: R04 Independent Acceptance Agent
```

## 2. Diff Reviewed

`bfc57f0 -> ea1d721` changes exactly three production files:

- `lib/services/llm_service.dart`: timeout policy/exception/watchdog, decode vs
  consumer error ownership, `receivedAnyDelta` after-acceptance semantics,
  Anthropic symmetry, FIM deadline, test seams (`@visibleForTesting` only);
- `lib/services/ai_generator_service.dart`: nested transport retry removed
  from `_callText`/`_callMessages` (M2/M3);
- `lib/services/api_error.dart`: `RetryBudget.transportAttempts` removed.

R01 ownership verified UNTOUCHED: `riverpod_providers.dart`,
`streaming_generation_session_repository.dart`,
`streaming_resource_generation_service.dart`,
`streaming_resource_generation_controller.dart`, `main.dart` have a zero diff
against the R03 end. `RetryManager.withRetry` now has exactly ONE production
call site (`llm_service.dart:364`) - the single transport retry owner.

## 3. Contract Verification

### M2 / M3 (timeout, retry multiplication) - CLOSED

- Single timeout owner in the transport layer: connect 30s, first-event 90s,
  idle 120s, overall 10min; FIM bounded by overall. The watchdog resets on
  every transport event (keepalives included) while the overall deadline is
  what terminates a keepalive-only stream. Cancellation closes the client and
  surfaces as `GenerationCancelledException`, never as a timeout (A5/B6).
- Retry census: `RetryManager.withRetry` appears once in production. The
  3x3 nested multiplication and the transparent replay of already-streamed
  requests are gone; worst case per structured stage is an auditable
  3 content x 3 transport = 9 HTTP requests (B9).

### M10 (consumer exceptions swallowed by decode catch) - CLOSED

Provider decode/shape problems are counted (`malformedEventCount++`) and
skipped; consumer callbacks run OUTSIDE any decode catch. A consumer
exception propagates verbatim with its stack (`Error.throwWithStackTrace`)
and stops the subscription (C1/C2). The same contract is enforced on the
Anthropic branch (C6) - currently unreachable in production
(`usesAnthropicMessagesApi` is constant false), reached via a visible-for-
testing seam.

### N15 (streaming / fallback divergence) - VERIFIED CONVERGED

The fallback path already shares `PartGenerationParser` (strict allowlist),
`GenerationPatchParser.responseToPatches` (canonical 3-patch sequence),
`GenerationPatchAccumulator` (identity/sequence/cursor) and
`PartGenerationValidator`. D11 drives the real coordinator fallback with an
unauthorized structural field and asserts refusal + zero commit.

### TG1 / TG13 - CLOSED

TG13: B1-B9 assert exact attempt counts against a fake http client with an
injected delay seam - no wall-clock flakiness. TG1: A1-A6/D2/D3/D4 drive the
real production streaming path across split lines, trailing buffers,
keepalives, stalls, cancellation and healthy flows.

## 4. Mutation Verification (isolated /tmp copy at the acceptance HEAD)

| Mutation | Result |
| --- | --- |
| MUT-ACC-1 remove the overall-deadline loop check | DETECTED; A4 failed |
| MUT-ACC-2 let the text API accept a partial result | DETECTED; C5 failed |
| MUT-ACC-3 watchdog never resets on transport events | SURVIVED initially, DETECTED after strengthening A6 (see TEST-GAP below) |
| MUT-ACC-4 remove the shared parser allowlist | DETECTED; D11 failed |

The implementer's own mutations (idle-window removal, receivedAnyDelta retry,
onChunk-into-decode-catch, fallback bypass) were reviewed and are consistent.

## 5. TEST-GAP found and closed during acceptance

**R04-A-TG1 (closed in this acceptance)**: the original A6 delivered all
events synchronously, so a watchdog without event-reset survived it. The
acceptance strengthened A6: events now arrive every 300ms against 500ms
windows, which only a resetting watchdog keeps alive. Verified: correct
implementation passes, MUT-ACC-3 fails. Committed as part of the acceptance.

## 6. Tests

```text
dart format --output=none --set-exit-if-changed .: PASS (502 files, 0 changed)
flutter analyze: PASS (No issues found)
R04 targeted + R01 regression + protocol files: PASS (94 passed, 0 failed)
flutter test: PASS (1678 passed, 0 failed)
git diff --check: PASS
Schema: 43
```

## 7. Acceptance Criteria

```text
AC-R04-01 PASS  transport never hangs forever (connect/first-event/idle/overall)
AC-R04-02 PASS  cancellation terminates immediately as GenerationCancelledException
AC-R03-03 PASS  retry: single transport owner, bounded auditable budgets, no multiplication
AC-R04-04 PASS  no transparent replay after an accepted delta
AC-R04-05 PASS  consumer/parser/validator exceptions propagate verbatim
AC-R04-06 PASS  malformed provider events counted, never reach the consumer
AC-R04-07 PASS  incomplete streams cannot report success
AC-R04-08 PASS  usage/keepalive never become content deltas
AC-R04-09 PASS  streaming and fallback share the same protocol contract (D11)
AC-R04-10 PASS  R01 ownership and lifecycle untouched (zero diff)
AC-R04-11 PASS  schema remains 43
AC-R04-12 PASS  R04 targeted 35/35 (+strengthened A6 => 24/24 in file run)
AC-R04-13 PASS  R01 streaming regression 22/22
AC-R04-14 PASS  full flutter test 1678/1678
AC-R04-15 PASS  independent mutations MUT-ACC-1..4 detected
```

## 8. Findings

```text
BLOCKER: 0
MAJOR: 0
MINOR: 0
TEST-GAP: 0 (R04-A-TG1 found and closed during this acceptance)
INFO: 1
```

### R04-A-INFO-1 - Anthropic branch is production-unreachable

`LLMProvider.usesAnthropicMessagesApi` is constant false, so the Anthropic
messages branch cannot execute in production today. Its failure semantics
were fixed symmetrically and are covered through a visible-for-testing seam.
INFO only: if a future provider selects the Anthropic API, the branch enters
production with the R04 contract already enforced.

## 9. Final Verdict

```text
ACCEPTED
```

## 10. Program Handoff

```text
R04 status: ACCEPTED
R05 / R06 dependency: satisfied; both are technically unblocked
Next recommended action: R05 - Async State & Production Wiring Consistency
  (or R06 - Context Budgeting & Narrative Continuity)
Carry-forward: none from R04; R03-A-N1 (MINOR) remains open from R03
```
