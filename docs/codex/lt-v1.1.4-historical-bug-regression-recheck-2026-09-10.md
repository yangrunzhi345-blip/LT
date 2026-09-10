# LT Historical Bug Regression Recheck

## 1. Audit Baseline

- Repository: `yangrunzhi345-blip/LT`
- Branch: `main`
- HEAD / origin/main: `a678920b7e6e76b328613420f213cdb6c540b0a2`
- Version: `1.1.4+7` (`pubspec.yaml`)
- Latest tag/release: `v1.1.4` (tag `dc7893e`; current fixes are after the tag)
- Audit date: 2026-09-10
- Flutter/Dart: Flutter 3.47.2, Dart 3.13.2
- Database schema: current `DatabaseService` schema version as defined in the repository; runtime/scene tables use row `schema_version` 1. No migration was changed in this audit.
- Working tree before audit: clean; after audit: only this Markdown file is new.

`git fetch origin`, fast-forward pull, `flutter analyze`, and `flutter test --reporter compact` were run against this baseline.

## 2. Executive Summary

1. No confirmed P0 regression was found. Full tests pass (303/303) and analyzer is clean.
2. Detailed Character stage execution is now sequential and uses typed normalization before assembly; the former shared mutable stage context is absent from the production path.
3. Stage schema validation is wired through `DetailedCharacterStageNormalizer` into the detailed generation service, including scalar rejection and Stage2B legacy nesting normalization.
4. SceneBatch now assigns session-local `sourceId`, generates one candidate per request, isolates item failures, and checks cancellation before persistence.
5. SceneBatch relationship resolution is only partially closed: responses without `targetResourceId` still use exact display-name fallback, so name variants can still lose relationships.
6. SceneBatch identity itself is not persisted as a primary key; this is compatible with saved cards but means stable identity is limited to one import session.
7. Helper calls explicitly disable thinking in translation, TTS cleanup, summary, extraction, vision, and raw completion paths. The low-level `CompletionParams` default remains `true/high`, so unannotated future/direct callers remain a regression risk.
8. Adventure setup loading has generation/latest-wins and disposal guards; independent resource errors remain isolated.
9. CharacterCard row parsing and JSON/PNG import share the tolerant parser and row-level parse isolation.
10. Legacy settings metadata uses tolerant scalar readers.
11. Runtime entity, scene presence, and normal scene-state reads isolate malformed rows.
12. A new related defect remains in idempotent `commitSceneDialogueTurn`: it directly calls strict `SceneState.decode` on a persisted row, bypassing `getSceneState`/`tryDecode` isolation.
13. The same commit path strictly decodes runtime entity JSON while applying a commit; malformed rows can abort an otherwise valid runtime commit.
14. Release and PR quality-gate workflows run format/analyze/test, but branch-protection required checks could not be verified from repository contents.

## 3. Historical Bug Regression Matrix

| ID | Historical BUG | Previous Status | Current Status | Current Evidence | Test Evidence | Regression Risk | Agent |
|---|---|---|---|---|---|---|---|
| DC-01 | Detailed Character low success rate | CONFIRMED | VERIFIED_RESOLVED | bounded stage retries, typed pipeline, sequential stages | coordinator + stage tests; 303 full tests | Medium: provider-specific behavior not live-tested | A |
| DC-02 | Stage2 shared mutable messages | CONFIRMED | VERIFIED_RESOLVED | Stage2A then Stage2B, fresh message list per attempt | stage normalizer/generation tests | Low | A |
| SC-01 | Stage2A/B ordering | CONFIRMED | VERIFIED_RESOLVED | explicit await dependency | production inspection | Low | A |
| SC-02 | Stage schema bypass/scalar acceptance | CONFIRMED | VERIFIED_RESOLVED | normalizer → validator → typed DTO → assembler | `p0_stage_payload_normalizer_test.dart` | Low | A |
| RP-01 | Guard/prompt contract conflict | CONFIRMED | VERIFIED_RESOLVED | canonical guard and supplement state machine | coordinator tests | Medium: prompt/provider semantics | A |
| RP-02 | Supplement no-growth false failure | CONFIRMED | PARTIALLY_RESOLVED | two bounded no-growth retries, then explicit failure | coordinator tests | Medium | A |
| LL-01 | Fast mode not reaching provider | CONFIRMED | VERIFIED_RESOLVED | generation mode mapped at `_callText/_callMessages` | helper/policy tests | Low | C |
| LL-02 | DeepSeek empty/reasoning content | CONFIRMED | VERIFIED_RESOLVED | `_resolveContent` rejects incomplete/truncated responses; bounded transport/content retries | truncation/deepseek tests | Medium: live provider differences | C |
| LL-03 | Accidental thinking in helpers | CONFIRMED | PARTIALLY_RESOLVED | audited helpers explicit false; low-level default true | helper policy tests | Medium | C |
| JS-01 | Repair returned damaged original | CONFIRMED | VERIFIED_RESOLVED | incomplete responses rejected before repair acceptance | P0 truncation tests | Low | A |
| CC-01 | Bad CharacterCard row blocks list | CONFIRMED | VERIFIED_RESOLVED | `CharacterCardEntry.fromRow` row isolation | import/database tests | Low | B |
| CC-02 | JSON/PNG parser split | CONFIRMED | VERIFIED_RESOLVED | `_cardFromJson` delegates to `fromJson` | parser tests | Low | B |
| CC-03 | Legacy JSON strict casts | CONFIRMED | VERIFIED_RESOLVED | `JsonValueReader` in model settings boundaries | legacy JSON tests | Medium: other models remain strict | B |
| AS-01 | Wizard broad failure | CONFIRMED | VERIFIED_RESOLVED | independent loaders and start failure reset | wizard boundary tests | Low | A |
| AS-02 | Stale async setup result | CONFIRMED | VERIFIED_RESOLVED | monotonic `_loadGeneration`, reset/dispose guards | concurrency tests | Low | A |
| RT-01 | Bad runtime entity row | CONFIRMED | VERIFIED_RESOLVED | row-by-row skip in `getRuntimeEntities` | repository tests | Medium: write/commit path bypass remains (RT-03) | F |
| RT-02 | Bad scene presence/state row | CONFIRMED | PARTIALLY_RESOLVED | getters use tolerant decode | repository tests | High due commit bypass | F |
| SB-01 | Display name as cross-stage identity | CONFIRMED | PARTIALLY_RESOLVED | candidate/source ID used for candidate filtering; relationship no-ID fallback remains | identity tests | Medium | A |
| SB-02 | Giant batch response | CONFIRMED | VERIFIED_RESOLVED | one structured request per candidate with bounded budget | generation job tests | Medium: sequential latency/rate limits | B |
| SB-03 | One item failure aborts batch | CONFIRMED | VERIFIED_RESOLVED | per-item retry/failure isolation and one final batch save | generation job tests | Medium: final batch save is all-or-nothing | B |
| SB-04 | Cancel/stale result writes | CONFIRMED | VERIFIED_RESOLVED | controller generation + cancellation checked before save | controller/job tests | Low | B |
| DB-01 | Quest/database unawaited errors | CONFIRMED | VERIFIED_RESOLVED | guarded persistence awaits retained | analyzer/full tests | Low | F |
| CI-01 | Release lacked regression gate | CONFIRMED | PARTIALLY_RESOLVED | workflows contain checks; required branch status unknown | GitHub workflow inspection | Medium | D |

## 4. Detailed Character Audit

Production chain: resource-library UI → import controller/use case → `AiGeneratorLlmGateway` → `AiGeneratorService.textToDetailedCharacterCard` → `_generateDetailedCharacterCard` → `_runCharacterStage` → `_callMessages` → LLM service → `DetailedCharacterStageNormalizer` → `StageSchemaValidator` → typed payloads → assembler → bounded supplement coordinator → repository.

Stage2A is awaited before Stage2B. Each `_runCharacterStage` builds a new message list and replays immutable canonical prior results. No `Future.wait` or shared mutable `sessionMessages` remains in this path. `fastMode` reaches `_callText` and maps to `enableThinking: false` unless explicit deep mode is requested. Supplement uses bounded rounds and bounded no-growth retries; a no-growth result is still an explicit user-visible failure, not silently accepted.

Status: `VERIFIED_RESOLVED` for the historical concurrency/schema/fast-mode failures. Live provider success-rate evidence is unavailable; provider truncation and malformed payload boundaries are covered by deterministic tests.

## 5. LLM / Thinking Audit

The final parameter mapping in `AiGeneratorService._callText` and `_callMessages` is `enableThinking == (generationMode == deepThinking)`. Translation, TTS cleanup, timeline summary, import extraction, visual extraction, and gateway raw completion construct `CompletionParams(... enableThinking: false)`. Chat uses settings through its normal provider path; deep generation passes its explicit mode.

The residual design risk is `CompletionParams()` and default parameters in `LlmService` still defaulting to `enableThinking=true, reasoningEffort=high`. A future direct caller that omits policy can unintentionally enable DeepSeek thinking. This is not a confirmed current user-path regression, hence `PARTIALLY_RESOLVED`; changing the global default could affect interactive chat and requires a product decision.

## 6. SceneBatch Audit

Chain: resource library page → `SceneBatchImportController` generation token → `SceneBatchImportUseCase.identify` → session-local `SceneBatchCandidate(sourceId, displayName)` → UI selection → `importSelected` → per-candidate gateway call → `_normalizeGeneratedItem` → relationship validation → integrity validator → one `saveCardBatch`.

The giant `items` request and fixed whole-batch 8192-token response are gone. Each candidate has bounded attempts and is independently discarded on failure. Cancellation/stale generation is checked between jobs and immediately before persistence.

Identity is still imperfect at the relationship boundary. `_validatedLinks` prefers `targetResourceId`, but if absent falls back to exact `targetName`; the generated prompt requires IDs, yet an LLM omission or display-name variation can silently drop a valid relationship. Duplicate display names are also ambiguous in the fallback map (last entry wins). This is a design/identity-contract residual, not merely a string comparison bug.

## 7. Adventure Setup / Async Audit

`AdventureSetupController.loadInitialData` increments `_loadGeneration`, waits for independent worldview/character/NPC loaders, and publishes only if its generation is current and the controller is not disposed. `reset` invalidates in-flight work; `_notify` suppresses post-dispose notifications. Dashboard/wizard/provider refreshes can share this controller without stale completion overwriting newer rows or errors. Boundary and concurrency tests exercise stale success/error, loading, reset, and dispose.

## 8. Persistence / Legacy JSON Audit

`CharacterCardEntry.fromRow` preserves row identity and marks parse errors instead of aborting the list. JSON and PNG card imports route through `CharacterCard.fromJson`; non-object top-level JSON is rejected safely. `ModelContextCapability` and `CompletionParams` use tolerant scalar readers for historical string/number/bool forms.

Residual trust-boundary risk exists in unrelated models such as `WorldEntry`, `GameState`, `AdventureConfig`, `SupportingCharacter`, and several `fromRow` methods that still use strict casts. This audit did not prove a currently reachable corrupt-row failure for each location; they should be treated as `UNVERIFIED` follow-up targets, not confirmed bugs.

## 9. Runtime / Scene Runtime Audit

Normal reads isolate malformed `adventure_runtime_entities`, `scene_presence`, and `scene_runtime_state` rows. Runtime heads and commits are branch-scoped and expected revisions are checked transactionally; runtime overlays remain deltas and do not mutate frozen source snapshots. Adventure deletion tables declare cascade for the inspected scene tables.

### RT-03 — confirmed related defect

In `AdventureRepositoryImpl.commitSceneDialogueTurn`, the idempotent-existing-turn branch reads `scene_runtime_state` and calls `SceneState.decode(sceneRows.single['state_json'])` directly (around line 295). In the normal commit path, runtime entity state is also decoded with `jsonDecode(...) as Map` (around line 673). These bypass the tolerant getters and can throw on a corrupt/non-object row.

Failure chain: duplicate request or runtime commit → transaction reads persisted malformed JSON → strict decode throws → valid idempotent response/commit aborts → scene context or retry surfaces a database/runtime error. Existing malformed-row tests cover getters only, so they do not fail against this bypass.

Status: `NEW_RELATED_DEFECT`, severity P1. Recommended owner: Runtime hardening agent. Preserve transactionality, revision checks, idempotency, and frozen snapshots; add tests through `commitSceneDialogueTurn` and runtime commit paths.

## 10. Quest / DB / Async Exception Audit

The previously identified guarded persistence paths remain awaited. `flutter analyze` reports no unawaited-return issue. No new confirmed Quest defect was found. Database row conversion remains a mixed trust-boundary design and should be covered incrementally.

## 11. CI / Release Gate Audit

`quality-gate.yml` runs dependency install, format check, analyze, and compact tests on pushes to `main` and pull requests. `release-arm64.yml` repeats the same checks before tag/version validation, ARM64-only APK inspection, SHA256 generation, and release creation. Build success is therefore no longer the sole release signal. Branch protection and required status checks are repository settings not provable from the checked-in files: status `UNVERIFIED`. Node/action deprecation warnings were not blocking failures in this audit.

## 12. Test Coverage Audit

Full suite: `flutter test --reporter compact` — 303 passed, 0 failed. `flutter analyze` — no issues. `dart format --output=none --set-exit-if-changed .` — 0 changes.

High-value tests are production-path unit/widget tests for setup concurrency, stage normalization, truncation, helper thinking policy, SceneBatch identity/jobs, parser imports, and malformed runtime reads. Coverage remains incomplete for: duplicate SceneBatch display names; relationship links missing IDs with aliases; live DeepSeek empty-content/provider variants; malformed scene/runtime rows through idempotent dialogue and runtime commit transactions; historical malformed rows in strict legacy models; and branch-protection enforcement. Existing helper-only tests must not be treated as proof for these cases.

## 13. Newly Discovered Related Defects

1. `RT-03` strict scene/runtime decode bypass in transactional commit paths (`NEW_RELATED_DEFECT`, P1).
2. SceneBatch relationship fallback and duplicate-name ambiguity (`PARTIALLY_RESOLVED`, P1/P2 depending product impact).
3. Low-level thinking defaults remain opt-out (`PARTIALLY_RESOLVED`, P2 regression risk).

## 14. Root Cause Work Packages

### Agent A — Detailed Character and SceneBatch identity

Problem: close the remaining identity fallback and verify all detailed-stage contracts. Files: `import_use_cases.dart`, SceneBatch models/gateway, detailed normalizer/tests. Do not alter saved-card schema or prompt-only workaround. Add duplicate-name, missing-ID, alias, and relationship tests. Acceptance: all cross-stage and relationship identity uses stable IDs, with explicit legacy behavior documented.

### Agent B — SceneBatch orchestration

Problem: validate bounded per-item generation, cancellation, partial success, and persistence semantics under long/rate-limited batches. Preserve one-item failure isolation and compatibility of saved JSON. Add retry/cancel/idempotency tests. Suggested boundary: one orchestration commit.

### Agent C — LLM thinking policy

Problem: decide and enforce opt-in/opt-out policy without changing interactive chat semantics. Audit every direct `LlmService` default caller and provider mapping. Add call-site matrix tests. Do not silently change global defaults before product decision.

### Agent D — CI governance

Problem: verify and enforce required checks in GitHub branch protection. Preserve release tag/version and ARM64/SHA behavior. Add/maintain quality gate dependency and document repository settings.

### Agent E — Persistence trust boundaries

Problem: audit strict legacy row/model decoders and isolate bad rows where evidence shows a reachable list/Adventure failure. Preserve strict canonical DTO validation. Add historical fixture tests; do not blanket-coerce all internal models.

### Agent F — Runtime hardening

Problem: remove strict decode bypasses in `commitSceneDialogueTurn` and runtime commit while preserving transaction, expectedRevision, branch isolation, idempotency, and immutable snapshots. Add malformed-row tests through both production transaction paths. Suggested commit: `fix(runtime): isolate malformed state during commits`.

## 15. Final Verdict

No confirmed P0 regression found. Historical detailed-generation, setup concurrency, parser split, legacy settings casts, SceneBatch giant-request/isolation/cancel, helper-thinking call sites, and normal runtime row-read failures are verified resolved by code-path inspection plus tests. SceneBatch relationship identity, thinking defaults, CI required-check enforcement, and transactional runtime malformed-row handling are not fully closed.

