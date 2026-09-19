# R05 - Independent Acceptance Report

> Phase: R05 - Runtime State, Production Wiring & Context Continuity
> Verdict: **ACCEPTED**
> Acceptance Date: 2026-09-19
> Reviewer: R05 Independent Acceptance Agent
> Baseline: Start `92916718c7a049c420e2d11562163fc64ee4b200`,
> Implementation HEAD `894bbc24103d6d1bbca7f7fc226cac757d0b9b93`
> Audit worktree: detached copy of `894bbc2` at `/tmp/LT-R05-AUDIT`
> (implementation worktree untouched)

## 1. Baseline

| Field | Value |
| --- | --- |
| Acceptance HEAD | `894bbc24103d6d1bbca7f7fc226cac757d0b9b93` |
| Implementation HEAD | `894bbc24103d6d1bbca7f7fc226cac757d0b9b93` |
| Start HEAD | `92916718c7a049c420e2d11562163fc64ee4b200` |
| Schema | 43 (unchanged; verified: `schemaVersion = 43`, no migration in diff) |
| Branch | `remediation/r05` |
| Working Tree | Clean (`git status --short` empty, `git diff` empty after mutations) |

## 2. Diff Reviewed

Five implementation commits reviewed via `git diff 9291671..894bbc2`
(36 files, +2857/−496; `git diff --check` PASS):

- `0d3425d` R05-A runtime state ownership (4 Studio controllers + CRUD serialisation, A1-A9)
- `fa7fafe` R05-B production wiring convergence (single pipeline, bridge required, C14 fail-fast, B3-B9)
- `b2f8412` R05-C bounded context assembly (history window, character bound, constraint budget, stable ordering, WorldviewPromptBudget, C1-C11)
- `dac25b9` R05-D summary continuity (boundary identity guard, branch-switch summary reload, D1-D10)
- `e9f7e5d` R05-E integration matrix E1-E5 (real repo + SQLite + ProviderContainer)
- `894bbc2` docs/status

No schema change, no R01/R02/R04 contract files rewritten, no transport
retry/timeout ownership changes (R04 invariants intact).

## 3. Contract Results

| Gate | Result | Evidence |
| --- | --- | --- |
| R05-A Async Ownership | PASS | All five controllers: success publish, error publish and dispose paths re-validate generation + target identity (static: 8/12/6 guard sites; A1-A9 barrier tests). CRUD mutations explicitly serialised through `_mutationQueue`; committed side effects reconciled, never faked back (A9). |
| R05-B Production Wiring | PASS | Only two `ResourceCreationPipeline` constructions remain: the streaming infrastructure provider (production owner) and `DatabaseService.entryCreationPipeline` — both with revision capture. Import use cases require the bridge; dead `repository`/`now` params removed. R01 shared ownership intact (`ownsService: false`, section runtime reuses Studio controller). |
| R05-C Context Budget | PASS | Constraint bypass removed (single `_selectWithinBudget`); character context truncated (≤2048); retained history window counted against budget; current turn protected; entry-id tie-breaks for stable ordering; surrogate-safe shared `truncateToTokens`; no second estimator; raw `$worldview` interpolation eliminated from `ai_generator_service.dart`. |
| R05-D Summary Continuity | PASS | `summaries.up_to_id` durable checkpoint (single row = atomic content+marker); boundary message identity validated before save; failure/cancel/stale never advance coverage; branch switch reloads branch-scoped summary. |
| R05-E Integration | PASS | E1-E5 drive the real `AdventureRepositoryImpl` over real SQLite, real `ContextOrchestrator`, real `ProviderContainer`; only LLM/clock faked; FK-seeded adventure rows make the write path genuine. |

## 4. Production Wiring

- Shared streaming ownership: intact (`streamingGenerationSessionRepositoryProvider`, `streamingResourceGenerationServiceProvider`, `resourceStudioRuntimeProvider` with `ownsService:false`, `sectionControlRuntimeProvider` reuse).
- Creation pipeline: one production contract; CRUD (`resourceCrudControllerProvider`) + 4 import use cases via `legacyCreationBridgeProvider`; legacy graph (CharacterManager/WorldEngine/ChatProvider default) via `DatabaseService.entryCreationPipeline`.
- Revision capture: present on every construction site; creation branch now records the initial head revision (previously a fresh resource had no head and could never pass the readiness gate).
- Import: bridge required, tree-only writes verified against the real DB (B5).
- Adventure: fail-closed for unprepared resources, ready start freezes bindings (B6/B7).
- Prompt: every prompt-declared key has a parser consumer; round-trip NDJSON patch contract (B8).
- Fallback: OVERFLOW without an attached compression link fails fast to a terminal `failed` record instead of a silent `preparing` dead-end; production link provider asserted attached (B9).

## 5. Context Contract

- Budget: hard input limit enforced end-to-end (C11); history window counts (fixed during implementation; verified).
- Worldview: bounded, constraints included in the same hard budget (C1/C7).
- Character: truncated, recorded as `truncated` in the trace (C2).
- History: drop-oldest only until the window fits; never silently dropped to zero by fixed context (C3).
- Current turn: always preserved as the last message (C4).
- Dedup: duplicate content filtered as `duplicate` (C5).
- Ordering: stable score/id ordering across repeated assemblies (C6).
- Estimator: single `TokenEstimator` + shared surrogate-safe `truncateToTokens`; Chinese/emoji/extended-Unicode consistency (C8/C9); line-boundary trimming (C10).

## 6. Summary Contract

- Checkpoint: `summaries.up_to_id` durable, schema 43 unchanged.
- Boundary identity: `toSummarize.last.id` captured at trigger; `messages[upToIndex-1].id` re-validated before commit.
- Failure: no save on LLM failure (D2). Cancel/stale: ownership closure consulted before save (D3).
- Stale: boundary moved / list shrunk ⇒ summary dropped (D4/D5/E2).
- Branch: `switchBranch` reloads the branch-scoped summary (facade path; no production UI callers yet — INFO).
- Restart: durable marker resumes coverage exactly, no gap and no re-covering (D7/D8).

## 7. Targeted Verification

| Suite | Result |
| --- | --- |
| R05 targeted (A1-A9, B3-B9, C1-C11, D1-D10, E1-E5) | 46 passed / 0 failed |
| R01 (production streaming ownership/recovery) | PASS |
| R02 (cancellation commit boundary, part source CAS, autosave durability) | PASS |
| R04 (llm streaming reliability) | PASS |

## 8. Independent Mutations

| Mutation | Target | Result |
| --- | --- | --- |
| MUT-ACC-R05-1: remove `isCurrent` ownership guards in `SummaryService.generateSummary` | E1 | **DETECTED** (E1 FAILED — late A wrote a row) |
| MUT-ACC-R05-2: restore constraint bypass in `_selectWithinBudget` | C7 | **DETECTED** (C7 FAILED) |
| MUT-ACC-R05-3: remove boundary message identity guard | D4 + E2 | **DETECTED** (both FAILED) |

All mutations reverted; `git status --short` / `git diff` clean afterwards.

## 9. Full Verification

- `dart format --output=none --set-exit-if-changed .`: PASS (508 files, 0 changed)
- `flutter analyze`: PASS (No issues found)
- `flutter test` (full): first acceptance run 1723 passed / 1 failed
  (B4, load-dependent observation timing — see Finding R05-ACC-MINOR-1);
  **re-run after the test-only strengthening: 1724 passed / 0 failed**
  (`grep Failing` = 0), matching the implementation baseline.
- `git diff --check`: PASS

## 10. Findings

- **BLOCKER:** none
- **MAJOR:** none
- **MINOR:**
  - R05-ACC-MINOR-1 — `r05_production_wiring_test.dart` B4 observed the
    revision rows strictly after awaiting the save future; under full-suite
    load the read can outrun the async DB write observation. Test-only
    strengthening applied in the acceptance commit (bounded event-queue
    settle before the assertion). No production risk: the capture rides the
    same committed transaction as the save result.
- **INFO:**
  - `app_config.dart` setup-context section is dead in production (single
    call site passes `includeSetupContext=false`); reachability cleanup
    belongs to the final cleanup phase.
  - `switchBranch`/`switchToMainBranch` currently have no production UI
    callers; the branch summary reload added by R05-D is latent but correct
    and test-covered.

## 11. Verdict

BLOCKER = 0, MAJOR = 0, targeted suite PASS, 3/3 independent mutations
DETECTED, analyze PASS, full regression 1724 passed / 0 failed.

# R05 ACCEPTED

Handoff: Milestone B (Runtime Reliability) exit gate reached — R04 + R05
both `ACCEPTED`. Next phase per the 7-phase program: R06.
