# LT Dirty Working Tree Reconciliation Plan

> 本方案是 Dirty Working Tree Reconciliation Plan，用于审计和整合当前未提交修改；它不替代任何已有 P0/P1 remediation 文档。

## 1. Audit Baseline

- Audit date: 2026-09-10 (Asia/Shanghai).
- Repository: `yangrunzhi345-blip/LT`; local `HEAD` and locally known `origin/main` are both `69f80cfe2461140ce16b03941fdd16868e9494f3` (`fix: canonical structured JSON, guard prompt, poisoned rows, and wizard resource isolation`). No `fetch` was performed by design, therefore this is not a claim that the remote server has no newer commit.
- User previously recorded about 47 modifications. At audit start there were **51 tracked modified, 7 untracked, 0 staged: 58 dirty paths**. The inventory is immutable evidence, not an instruction to preserve every hunk.
- `git diff --stat`: tracked diff is 1,415 additions / 1,162 deletions. Most unrelated UI/chat/settings changes are mechanical reflow; their breadth is nevertheless an integration risk.
- This planning task wrote no production/test/configuration file, did not stage, commit, merge, push, fetch, format, analyse, or run tests.

## 2. Relationship With Existing Remediation Plans

This document does not replace:

- `docs/codex/p0-character-import-adventure-loading-remediation.md`
- `docs/codex/p0-stability-hardening-followup-2026-09-10.md`

The latter remains source of truth for P0-1 through P1-10. A dirty hunk related to those items must be replayed/reworked under that plan, not redesigned here. Differences found here are recorded as plan dependencies: the current dirty code adds a typed stage normalizer and retry budget, which are candidate implementations of Follow-up P0-2/3/4/5; it also leaves one P0-2 path incomplete (DWT-001).

## 3. Dirty Worktree Inventory

All 58 paths were read as diffs; no path is assumed safe merely because it is a test, UI, or doc.

| Group | Paths | Audit conclusion |
|---|---|---|
| P0 implementation | `ai_generator_service.dart`, `api_error.dart`, `stage_schema_validator.dart`, `detailed_character_stage_normalizer.dart`, `llm_service.dart`, `adventure_wizard_screen.dart` | Mixed; keep only selected hunk logic after P0 rework/tests. |
| P0 tests | `detailed_generation_and_wizard_test.dart`, `p0_retry_budget_test.dart`, `p0_stage_payload_normalizer_test.dart`, `p0_structured_output_incomplete_test.dart`, `p0_adventure_wizard_start_boundary_test.dart` | Useful regression intent, but incomplete/partly false-confidence; retain selected tests and strengthen. |
| Debug artefact | `test/widget/zz_dbg_test.dart` | Drop; it is a manual debug probe with debug logging and no assertions. |
| Existing plan | `docs/codex/p0-stability-hardening-followup-2026-09-10.md` | KEEP WHOLE; independent existing plan, not implementation. |
| Scope-polluting reflow | all remaining paths in sections 8 and 11 | Drop/revert only their exact cosmetic hunks in a future approved phase; no production behaviour should be inferred from them. |

## 4. Architecture / Dependency Map

```text
Resource import UI/controller -> AiGeneratorService -> LLMService -> RetryManager/CompletionParams
                                      |                     |
                                      v                     v
                    raw JSON -> stage normalizer -> validator -> typed assembler

Wizard UI -> ResourceCrudController / repository -> AdventureSetupController -> AdventureConfig -> onStartAdventure

Settings/Chat/Adventure UI -> providers/controllers -> persistence/runtime state
```

The first chain has a single correctness contract only when raw JSON is normalized before validation and the assembler reads only typed payloads. The second chain requires one exception boundary around every operation after `_submitting=true`. Formatting changes in the third chain must not be mixed with either chain.

## 5. P0 Findings

### DWT-001 — LLMService still accepts repairable truncated structured data

- **File/hunk:** `lib/services/llm_service.dart`, `sendMessageStream` completion branch.
- **Category/severity:** MIXED, BUG-RISK P0, STALE-DIRTY relative to Follow-up P0-2.
- **Current intent/evidence:** the dirty condition adds `result.finishReason.isTruncated`, but inside that very condition a non-empty repairable object is parsed and `result.content` is returned. It returns damaged original content, rather than rejecting `length`/`maxTokens` or canonicalizing it.
- **Failure chain:** provider sends repairable prefix + `length`/`maxTokens` -> branch parses -> original truncated text is accepted -> consumer may persist/use incomplete fields or fail later on decode.
- **Action:** depend on Follow-up P0-2. Define one contract: structured calls with `length`, `maxTokens`, interrupted, or `responseCompleted=false` throw `StructuredOutputIncompleteException` before repair; a completed `stop` response may repair only to `jsonEncode(parsed)`. If this generic LLM API is intentionally raw-text only, remove the misleading structured repair branch and make callers use `AiGeneratorService` canonical resolution.
- **Tests/acceptance:** real `LLMStreamResult` cases for repairable `length` and `maxTokens`, both with `responseCompleted=false`; assert no original damaged string escapes, retry remains current-stage-only, and a completed trailing-comma response returns decodable canonical JSON. No DB migration; affects old data no; UI no; bounded LLM calls/token impact only as documented budget; independently committable with P0-2.

### DWT-002 — P0 stage/wizard tests do not yet prove the full stated contract

- **Files/hunks:** five P0 test files above plus modified `detailed_generation_and_wizard_test.dart`.
- **Category/severity:** KEEP-BUT-TEST, BUG-RISK P0 test gap.
- **Evidence:** `p0_structured_output_incomplete_test.dart` correctly uses real `LLMStreamResult` and tests `length`/`maxTokens`, but marks those two responses `responseCompleted:true`, contrary to the actual truncation contract requested by the follow-up plan. It does not exercise the faulty generic `LLMService` branch. The wizard test covers worldview save, load, character save, malformed custom attributes and callback; it does not independently force snapshot/config preparation failures nor assert all retryable UI states at 320px/common widths.
- **Action:** keep test scaffolding but add each missing production-path failure injection and assertions: Stage1/2A/2B counts including 1/1/2; preserved Stage1/2A assistant messages on Stage2B retry; `responseCompleted:false` for both `length` and `maxTokens`; canonical re-decode; no-progress semantics; all `_submitting` exits; empty/error/partial Wizard at 320/360/390/412.
- **Acceptance:** no helper-only substitute, no weak non-null assertion, no debug timeout; every expected call count and message boundary is asserted. Related plan: Follow-up P0-1..5. No migration/UI behaviour change beyond testing; independent test commits after their production commit.

### DWT-003 — Debug widget test is an accidental artefact

- **File/hunk:** untracked `test/widget/zz_dbg_test.dart`.
- **Category/severity:** REMOVE-AS-OBSOLETE, BUG-RISK P1.
- **Evidence/root cause:** test is named `debug`, emits `debugPrint`, manually invokes a Stepper callback, makes no correctness assertions, and has a swallowed cleanup catch. It creates database files and can provide false confidence.
- **Action/acceptance:** do not commit it. Transfer any useful setup to the named wizard regression test, with assertions and deterministic cleanup. No migration, UI, or LLM impact.

### DWT-004 — Wizard boundary hunk is directionally correct but not a complete transaction design

- **File/hunk:** `lib/features/adventure/presentation/wizard/screens/adventure_wizard_screen.dart`, `_handleStart`.
- **Category/severity:** REWORK SELECTED HUNKS, P0; RELATED-PLAN Follow-up P0-1.
- **Evidence:** the dirty `try/catch/finally` now encloses submitting, persistence, load, assembly/config, and callback, so it fixes the previously narrow callback-only boundary. However persistence/configuration remains a long UI transaction, and `debugPrint('$e\\n$st')` risks logging uncontrolled details.
- **Action:** retain one top-level boundary and guaranteed `finally` reset; use a user-safe error mapper/limited diagnostics; extract a result-returning start-preparation use case only if it can be introduced without duplicating repository ownership. Do not reintroduce nested callback-only try/catch or swallow errors.
- **Acceptance:** save worldview, load initial data, character save, snapshot/config preparation and `onStartAdventure` each fail independently; all leave `_submitting=false`, do not navigate, and expose retry. No migration; old data retained; UI error state affected; no extra LLM tokens; independently commit after DWT-002 tests.

### DWT-005 — Typed stage pipeline and retry budget are viable only as one atomic change

- **Files/hunks:** `ai_generator_service.dart`, `api_error.dart`, `stage_schema_validator.dart`, untracked `detailed_character_stage_normalizer.dart`.
- **Category/severity:** KEEP SELECTED HUNKS / REWORK SELECTED HUNKS, P0; RELATED-PLAN Follow-up P0-3/4/5.
- **Evidence:** raw maps are normalized to sealed payloads; Stage2B receives canonical Stage1+2A maps sequentially; validator now requires text; nested `world_profile` is normalized before the flat validator; transport attempt and stage-content attempt budgets are separately named. This removes the former post-validation casts and shared mutable Stage2 message risk.
- **Remaining risk/action:** document and enforce the maximum request product (3 content attempts × 2 transport attempts = 6 calls per stage; 18 across three stages, excluding separately governed no-progress supplements). Confirm all RetryManager call sites compile after `maxRetries` rename. Ensure `GenerationCancelledException` is excluded at every retry layer and generic `LLMService` does not defeat DWT-001. Keep compatibility aliases only in the normalizer, never in the assembler/validator.
- **Acceptance:** malformed String/num/bool/List/Map/null and aliases tests; nested-to-flat canonical output; unknown stage false; no `Future.wait`; Stage2B retry does not replay 1/2A; each return `jsonDecode`s. No DB migration; old LLM responses compatible through normalizer; limited, bounded token increase; one atomic commit.

## 6. P1 Findings

### DWT-006 — Scope pollution from a broad mechanical formatting patch

- **Category/severity:** MIXED at worktree level, P1 integration risk.
- **Evidence:** 45+ unrelated presentation, chat, settings, theme, data and test paths have only line wrapping/indentation in their visible hunks, while no formatter was authorized and no task ties them to P0.
- **Failure chain:** P0 review/merge becomes unreadable -> real behavioural hunk is missed -> a conflict or accidental rollback lands with unrelated UI/test change.
- **Action:** do not use `git add .`; future execution must compare `-w`, then drop only verified cosmetic hunks or move them to an isolated formatter commit approved separately. A formatter commit must not share a commit with functional changes. No migration/LLM/UI semantics intended; no independent P0 commit.

### DWT-007 — Existing tolerant-input risks are not repaired by cosmetic dirty hunks

- **Files:** `lib/models/model_context_capability.dart`, `lib/application/prompt_policies/adventure_context_policy.dart`, and presentation readers using `as String?`/casts.
- **Category/severity:** KEEP SELECTED cosmetic hunks only; P1 existing-plan dependency, not a dirty functional fix.
- **Evidence:** dirty changes merely reflow code; `ModelContextCapability.fromJson` still uses strict `as int?`/`as bool?`; adventure context still assumes selected values have String shape. These are persisted/LLM trust-boundary concerns, not fixed by reformatting.
- **Action:** do not claim remediation. Route to Follow-up P1-8 (normalizer/safe parser helpers) after classifying each source as external/historical versus canonical internal input. Required tests: strings/numbers/bools/maps/lists/null in legacy rows; one bad row isolation.

### DWT-008 — UI changes lack a feature-scoped responsive claim

- **Files:** all dirty settings, prompt-settings, dashboard, session, sidebar and widget paths listed in section 8.
- **Category/severity:** KEEP-BUT-TEST if a real behavioural hunk is later identified; otherwise DROP OBSOLETE HUNKS, P1.
- **Evidence:** review found reflow rather than an intentional responsive solution; existing widget changes cannot establish 320px, long text, error, partial-success, text-scale or mounted-after-await safety.
- **Action:** isolate semantics first. Any retained UI feature must get 320×568, 360×640, 390×844, 412×915 and a desktop widget check with `takeException()==null`; no bulk layout rewrite.

## 7. P2 / Cleanup Findings

- **DWT-009 (P2):** format-only changes in constants/data (`worldview_knowledge.dart`), theme/core widgets, chat widgets, dashboard/session/template widgets, settings/prompt widgets and most existing tests are not a functional deliverable. Future action: DROP OBSOLETE HUNKS or place in a separately approved `style:` commit after a clean-baseline formatter comparison.
- **DWT-010 (P2):** modified `resource_card_import_controller.dart`, `adventure_response.dart`, `custom_attribute_item.dart` and most unit/widget tests are whitespace/reflow only. They must not be represented as import/parser fixes. No functional test needed unless a semantic hunk is retained.

## 8. Per-file Decisions

Each path has one future disposition; `format-only` means inspect exact hunk before removal, not whole-file restore.

| File(s) | Decision | Reason / required test |
|---|---|---|
| `lib/services/ai_generator_service.dart` | REWORK SELECTED HUNKS | Keep typed sequential stages/content budget; repair DWT-001 integration; production-path 1/1/2, canonical JSON, cancellation tests. |
| `lib/services/api_error.dart` | KEEP-BUT-TEST | Keep explicit attempt budget/policy after all call sites and backoff/cancellation tests. |
| `lib/services/stage_schema_validator.dart` | KEEP SELECTED HUNKS | Must land atomically with normalizer/assembler; scalar/alias tests. |
| `lib/services/detailed_character_stage_normalizer.dart` | KEEP-BUT-TEST | Canonical DTO boundary; expand malformed/nested/root-precedence tests. |
| `lib/services/llm_service.dart` | REWORK SELECTED HUNKS | DWT-001 false truncation handling; direct generic-service tests. |
| `lib/features/adventure/presentation/wizard/screens/adventure_wizard_screen.dart` | REWORK SELECTED HUNKS | Keep unified finally boundary; safe diagnostics and all failure paths. |
| `test/unit/p0_retry_budget_test.dart`, `test/unit/p0_stage_payload_normalizer_test.dart`, `test/unit/p0_structured_output_incomplete_test.dart`, `test/widget/p0_adventure_wizard_start_boundary_test.dart`, `test/unit/detailed_generation_and_wizard_test.dart` | REWORK SELECTED HUNKS | Valid intent, DWT-002 gaps. |
| `test/widget/zz_dbg_test.dart` | DROP OBSOLETE HUNKS | Debug-only/no assertions. |
| `docs/codex/p0-stability-hardening-followup-2026-09-10.md` | KEEP WHOLE | Existing independent incremental plan; do not overwrite. |
| `lib/application/prompt_policies/adventure_context_policy.dart`, `lib/controllers/resource_card_import_controller.dart`, `lib/data/worldview_knowledge.dart`, `lib/models/adventure_response.dart`, `lib/models/custom_attribute_item.dart`, `lib/models/model_context_capability.dart` | DROP OBSOLETE HUNKS | Reflow only; model parser issue remains an existing-plan dependency. |
| `lib/core/theme/app_theme.dart`, `lib/core/widgets/app_dropdown.dart`, `lib/core/widgets/app_empty_state.dart`, `lib/core/widgets/app_text_field.dart`, `lib/core/widgets/custom_attribute_editor_section.dart`, `lib/widgets/app_dialogs.dart`, `lib/widgets/main_sidebar.dart` | DROP OBSOLETE HUNKS | Unrelated cosmetic reflow; no responsive feature or test claim. |
| `lib/features/adventure/presentation/home/screens/adventure_dashboard_screen.dart`, `lib/features/adventure/presentation/home/widgets/dashboard_action_cards.dart`, `lib/features/adventure/presentation/home/widgets/dashboard_hero_header.dart`, `lib/features/adventure/presentation/session/screens/adventure_session_screen.dart`, `lib/features/adventure/presentation/session/widgets/action_options_panel.dart`, `lib/features/adventure/presentation/session/widgets/session_message_list.dart`, `lib/features/adventure/presentation/templates/screens/preset_scenes_screen.dart` | DROP OBSOLETE HUNKS | Cosmetic reflow, not Wizard isolation/P0 implementation. |
| `lib/features/prompt_settings/presentation/screens/prompt_settings_screen.dart`, `lib/features/prompt_settings/presentation/widgets/prompt_preview_modal.dart`, `lib/features/settings/presentation/screens/settings_screen.dart`, `lib/features/settings/presentation/widgets/appearance_section.dart`, `lib/features/settings/presentation/widgets/data_management_section.dart`, `lib/features/settings/presentation/widgets/model_params_section.dart`, `lib/features/settings/presentation/widgets/provider_config_section.dart` | DROP OBSOLETE HUNKS | Broad unrelated Settings/Thinking UI reindent; do not mix with Follow-up P1-9 policy change. |
| `lib/engines/chat_engine_internals/summary_service.dart`, `lib/screens/chat_screen.dart`, `lib/screens/chat/widgets/character_sheet.dart`, `lib/screens/chat/widgets/chat_dialogs.dart`, `lib/screens/chat/widgets/message_bubble.dart`, `lib/screens/chat/widgets/scene_character_manager.dart`, `lib/screens/chat/widgets/status_dropdown.dart`, `lib/screens/chat/widgets/status_toast.dart`, `lib/screens/resource_library/npc_edit_page.dart`, `lib/widgets/adventure_message_card.dart` | DROP OBSOLETE HUNKS | Chat/resource runtime scope reflow; cannot be safely integrated into P0. |
| `test/unit/deepseek_reasoning_test.dart`, `test/unit/resource_import_semantics_test.dart`, `test/unit/riverpod_and_providers_test.dart`, `test/widget/app_dropdown_test.dart`, `test/widget/custom_attribute_test.dart`, `test/widget/session_message_list_scroll_test.dart`, `test/widget/settings_feature_test.dart`, `test/widget/ui_screens_and_sidebar_test.dart` | DROP OBSOLETE HUNKS | Existing test reflow does not add assertions. |

## 9. Mixed-file Hunk Decisions

Never restore a whole MIXED file. In `ai_generator_service.dart`, retain only: canonical typed DTO assembly, sequential confirmed-result replay, stage-local bounded retries, and pre-repair incomplete guard; rework generic call integration. In `api_error.dart`, retain the naming/budget/policy hunk but verify every caller. In the wizard, retain the enclosing `try/finally`, not uncontrolled full exception logging. In tests, retain named fakes/assertions and delete debug scaffolding; make completion flags/messages/counts production-real.

## 10. Stale / Duplicate Implementations

- **STALE-DIRTY:** the `llm_service.dart` truncation hunk duplicates the structured-response concern but contradicts Follow-up P0-2 by accepting repairable truncated raw content. Rebase its intent on that plan rather than preserving code.
- **DUPLICATE-IMPLEMENTATION risk:** validator + normalizer + assembler must be one canonical path. Do not add a second `world_profile` parser in the assembler or another retry loop in an LLM helper.
- **STALE scope:** Settings/Chat/UI formatting is based on no current feature plan and must not shadow the P0 code review.

## 11. Test-file Audit

`p0_retry_budget_test.dart` is a valid regression direction: it asserts attempts/backoff and cancellation classification. `p0_stage_payload_normalizer_test.dart` exercises malformed types, aliases and final-card propagation; strengthen it with Stage2B message assertions. `p0_structured_output_incomplete_test.dart` is close but uses unrealistically completed truncation flags and misses direct `LLMService`. The wizard test has real repository/controller seams but must add snapshot/config-specific throws, retry after every error and responsive states. `zz_dbg_test.dart` is FALSE-CONFIDENCE and must not land. All other modified tests are OUTDATED/UNRELATED reflow unless a future hunk adds a behavioural assertion.

## 12. Existing Plan Dependencies

| Dirty ID | Related plan | Handling |
|---|---|---|
| DWT-001/002 | Follow-up P0-2 | rebase structured contract/tests there |
| DWT-004 | Follow-up P0-1 | complete wizard boundary there |
| DWT-005 | Follow-up P0-3, P0-4, P0/P1-5 | single atomic typed-stage/retry implementation |
| DWT-007 | Follow-up P1-7/P1-8 | do not mistake formatting for tolerant persistence work |
| Settings formatting | Follow-up P1-9 | no Thinking default change is present here |
| no dirty SceneBatch hunk | Follow-up P1-10 | deliberately separate |

## 13. Remediation Phases

1. **Phase 0 — immutable inventory:** copy this path list to the execution handoff; record status/diff before every action; no blanket Git operation.
2. **Phase 1 — P0 structured and Wizard:** DWT-001/002/004/005; implement/review only the six implementation files and their named tests; remove debug test.
3. **Phase 2 — parser/persisted compatibility:** Follow-up P1-7/8; audit trusted versus external JSON; no local ad-hoc `_asText` proliferation.
4. **Phase 3 — concurrency/Thinking:** Follow-up P1-6/9; decide controller ownership and explicit Thinking policy, with direct call-site tests.
5. **Phase 4 — separate feature work:** SceneBatch only under Follow-up P1-10; Chat/Settings/UI only after an approved feature specification.
6. **Phase 5 — test reconciliation/integration:** delete/replace false tests, run targeted matrix, then full gate. Cosmetic reflow is either intentionally isolated or not carried forward.

## 14. Git Preservation Strategy

**New rule:** every dirty hunk remains traceable; KEEP hunk is protected, REWORK hunk may be precisely changed after approval, OBSOLETE hunk may be precisely removed after approval, and UNKNOWN hunk is untouchable. This supersedes neither user ownership nor the prohibition on blind cleanup.

Future agents must not use `reset --hard`, `restore .`, `checkout -- .`, `clean`, `stash`, or `git add .`. For each phase: record `git status --short` and target-file diffs; edit/replay by hunk; inspect `git diff --check`, `git diff --cached`, and status; stage only reviewed paths/hunks; make one small reversible commit. For MIXED files, use patch-level review—not whole-file overwrite.

## 15. Test Matrix

| Area | Required evidence |
|---|---|
| Detailed generation | Stage1→2A→2B ordering, no shared mutable messages/Future.wait, counts 1/1/2, retries preserve confirmed messages, cancellation 1 call. |
| Structured JSON | empty/invalid/trailing comma/repairable truncated `length` and `maxTokens`, completed flags, canonical `jsonDecode`, no damaged original, bounded requests. |
| Retry | maximum attempts versus retries, 429/backoff/5xx/timeout, no cancellation/content retry, worst-case budget stated. |
| Wizard | five named throw sites; submitting reset; retry; no navigation; empty/error/partial resource states and 320/360/390/412 no-overflow. |
| Persisted rows | malformed field type isolates one row; legacy aliases/PNG/JSON/database paths. |
| Final gate | `git diff --check`, `flutter analyze`, P0 targeted tests, existing regressions, `flutter test`, Android build smoke. |

## 16. Commit Plan

1. `fix: reject incomplete structured model responses`
2. `fix: normalize detailed character stage payloads`
3. `fix: clarify transport and content retry budgets`
4. `fix: harden adventure start exception boundary`
5. `test: cover P0 structured generation and wizard failure paths`
6. `refactor: unify character card parsing` (Follow-up P1-7)
7. `fix: tolerate legacy persisted resource payloads` (P1-8)
8. `fix: serialize adventure asset loading state` (P1-6)
9. `fix: make thinking opt-in for helper requests` (P1-9)
10. `fix: harden scene batch import semantics` (P1-10)

Each commit must be independently buildable, testable, reviewable and revertible. Cosmetic reflow is explicitly excluded.

## 17. Definition of Done

All inventory paths are classified; no UNKNOWN high-risk hunk remains; DWT-001/002/004/005 are closed; no stale API call or duplicate parser/retry/state source remains; external persisted data has an explicit trust boundary; LLM schema/normalizer/consumer agree; async writes have defined ownership; retained tests assert production behaviour; every kept/deleted hunk has a reason; and the final gates in section 15 pass. The resulting tree must contain no unexplained dirty file.

## 18. Execution Agent Checklist

1. Read both existing remediation documents and this plan; treat the follow-up plan as source of truth for overlapping fixes.
2. Snapshot status/diffs; confirm no new user changes since this audit.
3. Start only Phase 1; do not stage any formatting-only UI/chat/settings file.
4. Fix DWT-001 before claiming truncated JSON resolved; strengthen DWT-002 tests before accepting the P0 implementation.
5. Handle each MIXED file by hunk; remove `zz_dbg_test.dart` only in an approved implementation phase.
6. Run the exact targeted tests first, then gates; distinguish pre-existing/environment failures.
7. Commit each listed logical unit separately and leave unrelated dirty content traceable.
