# Phase 5 Remediation Audit

Reviewed branch: `main`  
Reviewed baseline: `3d11ac20009f16383397989317d37fb2d00f2073`  
Remediation commit: `ff5c8b6`  
Scope: only the claimed P5-B1 through P5-M3 remediation changes and their direct call chain.  
Result: **REJECTED**

## Verified repairs

- Strict full-response allowlist, exact integer protocol version, and duplicate
  snake/camel alias rejection pass the pre-existing independent tests.
- The repository rejects a concurrent `startAttempt` for a `generating` task;
  response resource/part binding and write-count checks were added.
- The retry loop now persists `failed -> ready` before redispatch.
- Dependency context has an aggregate limit and reference selection is bounded.

## Remaining blocker: P5-B1

`GenerationPatchAccumulator.applyPatch` checks the cursor for `append_text`,
but not for `start_part`, `complete_part`, or `fail_part`. The retained
independent test supplies `start_part`, appends `text` (length 4), then sends
`complete_part` with `cursor: 0`; no `PatchCursorMismatchException` is thrown.
Thus the claimed cursor integrity is false and an invalid terminal patch can be
accepted.

Additionally, `PartGenerationCoordinator` still invokes the one-shot
`LlmGateway.rawCompletion` seam and only parses its fully collected string.
Although it can parse NDJSON after receipt, it does not immediately consume a
network stream, persist ordered patches, or resume from a persisted cursor as
required by Phase 5's implementation steps.

## Evidence

- `lib/application/resources/generation_patch_parser.dart`,
  `GenerationPatchAccumulator.applyPatch`: cursor comparison exists only in
  `appendText`.
- `lib/application/resources/part_generation_coordinator.dart`: `_completer`
  returns `Future<String>` and delegates to `rawCompletion` before parsing.
- `flutter test test/application/resources/phase5_independent_acceptance_test.dart`:
  4 existing checks pass; the added terminal-cursor contract assertion fails.
- The claimed remediation targeted suite was independently rerun and otherwise
  passed (36 tests).

## Required remediation direction

Validate cursor semantics for every operation with a cursor, in particular
require `complete_part.cursor == accumulatedLength`; define and enforce the
terminal operation ordering. Then integrate a streaming gateway/API that feeds
patches as they arrive and persistently associates sequence/cursor progress
with the task, including cancellation and restart recovery. Do not change the
independent assertion to accept the current behavior.

Phase 5 remains `REJECTED`; Phase 6 remains `BLOCKED`.
