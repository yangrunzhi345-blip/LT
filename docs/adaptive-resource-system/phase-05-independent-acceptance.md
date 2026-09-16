# Phase 5 Independent Acceptance Report

Reviewed Branch: `main`  
Reviewed HEAD: `99c56ab31e59b1f7e05c163040fe198bbdcc974a`  
Implementation Commit: `27a0498`  
Working Tree at review start: clean  
Reviewer: Codex independent reviewer  
FINAL RESULT: **REJECTED**

## 1. Git Baseline

`main` and the reviewed HEAD match the executor's claimed baseline. `git diff
--check` was clean before reviewer artifacts were added. The implementation
commit changes the listed Phase 5 files; `99c56ab` only changes status docs.

## 2. Incremental Protocol Audit

Rejected. The formal contract requires ordered `start_part`, `append_text`,
`complete_part`, and `fail_part` patches with a monotonic sequence and cursor.
No `resource_generation_patch.dart`, patch parser, sequence, cursor, or patch
operation exists. `PartGenerationCoordinator` instead obtains one complete
string through `LlmGateway.rawCompletion` and commits one final JSON response.

## 3. Single-Part Boundary Audit

Rejected. The independent database-backed test supplied a valid target response
plus `"parts": [{...}]`; `generateAllParts` returned `true` and committed the
target Part. This violates the rule that a response attempting multiple Parts
must be rejected before any commit.

## 4. Parser Strictness Audit

Rejected. `part_generation_parser.dart` extracts from the first `{` to the
last `}`, permits prose/fences, converts numeric strings, and silently selects
snake_case over camelCase. Independent tests demonstrate accepting `"1"` for
the version and accepting conflicting `part_id`/`partId`. The two-object input
was rejected only because concatenation makes invalid JSON, not because the
parser has an ambiguity policy.

## 5. Validator Audit

Rejected. The validator has a blacklist, not an allowlist; aliases such as
`newParts`, `section_updates`, `resource`, and arbitrary unknown fields are not
rejected. More importantly, the coordinator calls `validate` without
`rawDecodedMap`, so even the finite blacklist is never applied to production
LLM output.

## 6. Protocol Version Audit

The validator checks the resulting integer, but the parser accepts numeric
strings and arbitrary `num.toInt()` values. Strict wire typing required by the
review is absent (independent test fails for `"1"`).

## 7. ID / Attempt Boundary Audit

Coordinator-level validation checks all five identities before its normal
commit. However, `commitPartContent` itself only checks the task/attempt lease
and writes `response.partId` and `response.resourceId`; it does not bind the
response IDs to the task row. The missing raw payload validation already makes
the production boundary insufficient for the one-Part contract.

## 8. Content Capacity Audit

`ResourceLimits.maxPartCharacters` is a UTF-16 `String.length` limit of 8000.
It is not tied to the Part's `estimatedLength` and therefore does not enforce a
blueprint budget or a minimum/target completion policy. Unicode code points
outside the BMP count as two code units.

## 9. Token Budget Audit

`resourcePartGeneration` uses `maxTokens: 4096` while a Part may plan up to
8000 UTF-16 code units. There is no model-specific output-ratio proof, no
per-Part upper planning limit, and no continuation protocol. The requested
maximum cannot be shown reachable.

## 10. Continuation / Retry Audit

No continuation exists; a retry creates a new full completion. That is not the
contractual cursor-based continuation. Moreover, the automatic retry branch
adds a failed task only to a local list and never changes its persisted status
from `failed` to `ready`; a failed task below its retry limit can reschedule the
outer loop without dispatching work.

## 11. State Machine Audit

The pure transition table prevents `completed` from moving to generating.
Repository methods do not consistently enforce it: `startAttempt` accepts any
status except `completed`, including an already `generating` task.

## 12. DAG Scheduler Audit

Basic dependency readiness and completed-unlock paths are covered by executor
tests. Pending-without-ready produces a deadlock error. Failed dependencies do
not dispatch downstream tasks, but the broken automatic retry path prevents
acceptance of scheduler recovery.

## 13. Concurrency Audit

The coordinator's local in-flight cap is exercised by its test. Lease
exclusivity is not: `startAttempt` permits a second attempt while the first is
generating, replacing `current_attempt_id`; the executor test explicitly uses
this behavior to model a retry. This is not a valid duplicate-start lease.

## 14. Bounded Context Audit

Rejected. Prompt construction truncates *each* dependency to 1500 characters;
there is no aggregate dependency bound. N dependencies can therefore add
`1500 × N` characters, plus reference text and metadata.

## 15. ReferenceSource Audit

The reference body is always passed as `referenceExcerpt` and truncated from
its prefix to 2000 characters. There is no relevance selection/retrieval.

## 16. Atomic Commit Audit

`commitPartContent` uses one SQLite transaction for content, resource timestamp,
task and attempt status. This is a positive property, but cannot cure a payload
accepted through the broken structural boundary. It also does not check update
counts for the resource, task, or attempt rows.

## 17. Cancellation Race Audit

Late commit after database cancellation is rejected by existing repository
tests. The handle is passed to the gateway, but the coordinator uses a complete
completion future rather than immediately consuming and cancelling a patch
stream.

## 18. Retry / Late Response Race Audit

An old attempt is rejected once a new `current_attempt_id` is stored. This does
not establish valid retry behavior because concurrent starts are allowed and no
sequence/operation identity exists.

## 19. Operation Idempotency Audit

Rejected. `generationId` is created from a timestamp for every
`generateAllParts` call and attempts are timestamp IDs. There is no stable
generation-operation record/unique key to make repeated clicks, restart, or
network retry idempotent.

## 20. Crash Recovery Audit

`recoverInterruptedTasks` resets `generating`/`validating` to ready or pending
and marks a started attempt interrupted. Existing unit coverage passes. It has
no cursor/confirmed partial text to resume, as required by the formal protocol.

## 21. Generation Completion Audit

`areAllTasksCompleted` returns false for empty, failed, generating, cancelled,
or pending sets. This narrow condition is correct.

## 22. Blueprint Immutability Audit

The normal content commit does not update blueprint rows. This positive finding
does not override the structural-response failure in sections 3–5.

## 23. Confirm Boundary Audit

`generateAllParts` rejects a non-confirmed blueprint before scheduling. This is
covered by source control flow and existing tests.

## 24. Database v36 Migration Audit

The fresh/v35-upgrade executor test passes and v36 creates the attempts table
plus task columns. The schema has a task FK and indexes, but no foreign keys
from task resource/section/part IDs, no unique operation key, and no enforced
attempt lease constraint.

## 25. Legacy Double-Write Audit

Phase 5 files do not write `worldview_presets`, `character_cards`, or
`npc_cards`; legacy table references found under `lib/` are pre-existing
compatibility/migration paths.

## 26. Privacy / Logging Audit

No Phase 5 application/domain source logs raw prompt, reference body, response,
or Part content. Database migration logs contain schema metadata only.

## 27. LLM Policy Audit

The policy requests JSON mode when provider capabilities support it and passes
the task handle. `thinking` follows user settings, temperature is 0.7, and the
unproven 4096-token/8000-character mismatch remains a material capacity risk.

## 28. Phase 6 Scope Leakage Audit

No Resource Studio, UI generation control, rewrite UI, or persistent streaming
feature was found. The absence of the Phase 5 patch stream is a missing Phase 5
requirement, not Phase 6 leakage.

## 29. Phase 3/4 Regression

`phase3_independent_acceptance_test.dart` and
`phase4_independent_acceptance_test.dart` passed in the reviewer run.

## 30. Independent Acceptance Tests

Added `test/application/resources/phase5_independent_acceptance_test.dart`.
It deliberately asserts the published strict contract. It fails three
meaningful checks: canonical wire type, duplicate semantic alias rejection,
and no commit for a multi-Part payload. The failures are retained as evidence.

## 31. Full Test Results

Executor targeted tests passed: parser (8), validator (10), prompt (4), task
repository, coordinator, migration v36, and Phase 3/4 independent acceptance.
The reviewer acceptance test fails 3 checks. The reviewer ran full
`flutter test`; it therefore fails at those same independent contract checks.
The required full-test gate is not met; no claim of a green full suite is made.

## 32. Findings Matrix

| ID | Severity | Location | Contract violation |
| --- | --- | --- | --- |
| P5-B1 | BLOCKER | `part_generation_coordinator.dart`, protocol files | No patch operations/sequence/cursor; final whole-response flow replaces the specified incremental protocol. |
| P5-H1 | HIGH | `part_generation_parser.dart:27-165`, coordinator validation call | Multi-Part/structural response is accepted and committed; raw-map structural guard is not invoked. |
| P5-H2 | HIGH | `part_generation_parser.dart:62-65, 127-128` | Wire types and duplicate semantic aliases are silently coerced/selected. |
| P5-H3 | HIGH | `resource_generation_task_repository.dart:187-236` | A generating task can receive another attempt; no exclusive lease. |
| P5-H4 | HIGH | `part_generation_coordinator.dart:173-190` | Automatic retry does not persist a valid retry transition. |
| P5-M1 | MEDIUM | `part_generation_prompt_builder.dart:58-75` | Dependency bound is per item, not global; references are prefix truncation. |
| P5-M2 | MEDIUM | limits/policy/blueprint validator | 4096 output tokens cannot be proven sufficient for permitted 8000-character Parts. |
| P5-M3 | MEDIUM | coordinator/repository | No stable operation identity/idempotency across calls/restart. |

## 33. Remaining Findings

All matrix findings remain open. Required remediation direction: implement the
formal patch DTO/parser/state persistence and sequence/cursor rules; make the
parser an exact allowlisted schema decoder; pass raw data to validation or make
parsing itself enforce the schema; enforce one live lease transactionally;
persist retry transitions; add global context and compatible output budgets;
then replace these failing acceptance assertions only by compliant behavior.

## 34. STATUS.md Update

`STATUS.md` is updated to record Phase 5 as `REJECTED` and leave Phase 6
`BLOCKED`.

## 35. Phase 6 Unlock Decision

Phase 6 remains **BLOCKED**. It is not unlocked because there is one BLOCKER,
four HIGH findings, failing independent tests, and the core incremental JSON
contract is not established.
