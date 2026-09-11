# LT v1.1.4 P1 Root Cause Audit

> **文档状态**：✅ **已完成 (Completed)**（审计结论已整改并验证：`1ee0eac` / v1.1.5）
> **参考策略**：本文档已归档，仅作历史记录。后续任务默认不再参考或遵循本文件内容，除非用户明确要求。

## 1. Audit Baseline

- Audit date: 2026-09-10
- Repository: `yangrunzhi345-blip/LT`
- Branch: `main`
- HEAD: `dc7893e693c642a04d83454422e451a20a739657`
- origin/main: `dc7893e693c642a04d83454422e451a20a739657`
- Version: `1.1.4+7`
- Latest tag: `v1.1.4`
- Latest release: `LT Dialogue v1.1.4`
- Release URL: `https://github.com/yangrunzhi345-blip/LT/releases/tag/v1.1.4`
- Working tree at baseline: clean
- Database schema version: `28` (`lib/services/database_service.dart`)
- Flutter: `3.47.2`
- Dart: `3.13.2`

Validation commands:

```text
git fetch origin
git checkout main
git pull --ff-only
git status
git rev-parse HEAD
git rev-parse origin/main
git log -15 --oneline
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --reporter compact
```

Results:

- `dart format --output=none --set-exit-if-changed .`: `Formatted 266 files (0 changed)`
- `flutter analyze`: `No issues found`
- `flutter test --reporter compact`: `284 passed`

Important constraint: this audit did not modify production code, tests, workflows, pubspec, schema, or prompts. It only writes this Markdown report.

## 2. Executive Summary

1. No confirmed P0 regression was found in v1.1.4.
2. SceneBatch still has a confirmed P1 identity-contract defect: display name is used as cross-stage identity.
3. SceneBatch still has a confirmed P1 scaling defect: all selected characters are generated in one structured response with `maximumOutputTokens: 8192`.
4. SceneBatch relationship binding has the same identity defect: `targetName` exact-match is used to recover `targetResourceId`.
5. SceneBatch has no direct regression tests for renamed generated items, duplicate names, relation-name variants, truncation, partial success, or per-item failure isolation.
6. `CompletionParams` default remains `enableThinking=true`, `reasoningEffort=high`.
7. Normal resource import paths now explicitly pass `generationMode` and the core `AiGeneratorService._callText/_callMessages` maps non-deep modes to `enableThinking=false`; this part is resolved for the audited import flows.
8. Several helper calls still instantiate `CompletionParams(...)` without explicit `enableThinking:false`, causing confirmed latency/cost risk under DeepSeek-capable providers.
9. GitHub release workflow creates APKs and releases but does not run format, analyze, or tests.
10. `main` branch is not protected and has no required status checks.
11. Release success therefore proves buildability and ARM64 ABI filtering, not regression validation.
12. Runtime State Versioning v28 is materially improved and current core tests cover immutability, branch isolation, idempotent scene commits, expected revision, and malformed runtime entity row isolation.
13. Runtime still has a lower-priority trust-boundary gap in scene runtime reads: malformed `scene_presence.participant_ids_json` or `scene_runtime_state.state_json` can still throw during read.
14. Trust-boundary hardening added in v1.1.4 covers `ModelContextCapability`, `CompletionParams`, `CharacterCard` import parser split, and runtime entity row isolation, but it is not yet a project-wide persisted JSON contract.
15. Highest remediation priority should be SceneBatch identity, SceneBatch generation orchestration, then CI quality gates.

## 3. Issue Matrix

| ID | Severity | Status | Root Cause | Affected Layer | Regression Risk | Recommended Agent |
| -- | -------- | ------ | ---------- | -------------- | --------------- | ----------------- |
| SB-01 SceneBatch identity | P1 | CONFIRMED | Display text is used as entity identity across independent LLM stages | UI, Controller, UseCase, Gateway, LLM prompt, persistence | High: valid generated items can be dropped | Agent A |
| SB-02 SceneBatch giant response | P1 | CONFIRMED | Batch orchestration is one LLM request and one JSON response instead of per-character jobs | UseCase, Gateway, LLM, retry, persistence | High: truncation/failure wastes successful items | Agent B |
| SB-03 SceneBatch relationship identity | P1 | CONFIRMED | Relationship target recovery uses exact `targetName` matching | UseCase, DTO, persistence | Medium-high: relation links silently disappear | Agent A |
| LLM-01 Thinking helper policy | P2 | PARTIALLY_RESOLVED | Product policy exists at some entry points, but helper calls still inherit `CompletionParams` thinking default | LLM params, helper services, Settings | Medium: latency/cost regression | Agent C |
| CI-01 Missing regression gate | P1 | CONFIRMED | Release workflow validates APK build, not code quality; branch has no required checks | GitHub Actions, branch governance | High: logical regression can ship | Agent D |
| TB-01 Persisted JSON scalar settings | P1 | RESOLVED | Prior strict casts at settings/model metadata boundary were replaced by tolerant readers | Models, settings metadata | Low after v1.1.4 | None |
| TB-02 CharacterCard parser split | P1 | RESOLVED | PNG/JSON import now routes through tolerant `CharacterCard.fromJson` contract | Import parser, model | Low after v1.1.4 | None |
| TB-03 Scene runtime row isolation | P2 | NEW | Scene runtime reads still assume valid persisted JSON for scene presence/state | Repository, SQLite | Medium: one corrupt row can block scene context | Agent E |
| ASYNC-01 AdventureSetup stale load | P1 | RESOLVED | Controller now uses request generation and dispose guards | Controller, Provider, UI | Low after v1.1.4 | None |
| RUNTIME-01 Runtime entity bad row | P1 | RESOLVED | Runtime entity reads now skip malformed rows | Repository, SQLite, Runtime overlay | Low after v1.1.4 | None |

## 4. SB-01 SceneBatch Identity

Status: CONFIRMED
Severity: P1
Category: DTO design + LLM identity contract + matching algorithm

### User-visible symptom

User selects `林月` after identification. Generation succeeds but returns a display variant such as:

```text
林月·玄霜剑主
林月（少女时期）
林 月
```

The generated item is filtered out. If every item changes display name, the user sees:

```text
未识别到可导入的角色卡
```

### Direct cause

`SceneBatchImportUseCase.importSelected()` filters generated items with exact display-name equality:

```dart
selectedNames.contains(item['name']?.toString().trim())
```

Evidence:

- `lib/application/resource_library/import_use_cases.dart:405-410`
- `lib/services/ai_generator_service.dart:1953-1995`
- `lib/services/ai_generator_service.dart:1999-2026`
- `lib/screens/resource_library/scene_batch_import_page.dart:205-234`

### Root cause

SceneBatch has no stable identity contract between identify and generation stages. A human-facing name string is being used as the primary key across two independent LLM calls and a user selection dialog. The prompt asks the LLM to generate selected names, but the DTO has no immutable `source_id`/candidate ID that must round-trip through generation.

### Relevant call chain

```text
ResourceLibraryScreen batch button
→ showSceneBatchImportPage()
→ _SceneBatchImportPage._identify()
→ SceneBatchImportController.identify()
→ SceneBatchImportUseCase.identify()
→ LlmGateway.identifyCharacterNames()
→ AiGeneratorService.identifyCharacterNames()
→ List<String> display names
→ dialog stores selected Set<String>
→ _SceneBatchImportPage._import(selectedNames)
→ SceneBatchImportController.importSelected()
→ SceneBatchImportUseCase.importSelected()
→ LlmGateway.generateSceneBatchCharacters(selectedNames)
→ AiGeneratorService.generateSceneBatchCharacters()
→ LLM returns items
→ UseCase filters by item['name'] exact match
→ repository.saveCardBatch()
```

### Failure chain

```text
Trigger: user starts SceneBatch import and chooses “林月”
→ identify stage emits only display string “林月”
→ user selection stores Set<String>{“林月”}
→ generation prompt allows full character fields including `name`
→ model returns valid richer display name “林月·玄霜剑主”
→ UseCase compares generated `name.trim()` to selectedNames
→ exact match fails
→ item is dropped before validation/persistence
→ if no item remains, ImportValidationException is thrown
→ UI reports no importable card even though generation succeeded
```

### Why existing safeguards fail

- `identifyCharacterNames()` deduplicates names after whitespace removal only inside the identify result set; this does not create a stable identity.
- `ResourceIntegrityValidator` runs after filtering, so it never sees dropped items.
- `AiAdventureUtils.parseJson()` only checks JSON parseability; it does not validate identity round-trip.
- Controller generation guards avoid stale UI updates but do not address DTO identity.

### Existing tests

No direct unit test covers `SceneBatchImportUseCase.importSelected()` with generated `name` variants.

Search evidence:

- `rg "SceneBatch|selectedNames|relationship_links" test -n` only found a static widget fixture containing `relationship_links`.

### Missing tests

- Identify returns `林月`; generation returns `林月·玄霜剑主`; item must still map to selected candidate by stable ID.
- Identify returns duplicate display names from different source spans; selecting one must not import the other.
- Generated item missing stable ID must be rejected before persistence.
- Stable ID mismatch must not be silently saved.

### Data compatibility impact

Existing persisted cards do not require migration if the fix keeps generated card JSON compatible. The new identity should be an import-session DTO concern and may optionally be omitted from final persisted character JSON or recorded as provenance.

### Migration impact

No database schema migration should be required for the minimal design if IDs are session-local and saved cards still receive repository IDs.

### LLM/token impact

Adding stable IDs increases prompt and output size minimally. It materially reduces wasted generation caused by dropped results.

### Concurrency impact

No additional concurrency risk if IDs are immutable and scoped to one import request.

### Recommended design

- Replace `List<String>` candidates with a `SceneBatchCandidate` DTO:

```text
source_id: character_001
display_name: 林月
source_span/source_hint: optional
confidence/facts/fuzzy: optional
```

- The dialog should select `source_id`, not display name.
- Generation prompt must include selected candidates and require each item to return the original `source_id`.
- Filtering, validation, duplicate handling, relationship binding, and save summary should use `source_id`.
- `name` should remain a display field and may be changed by the LLM only if validation keeps the identity.

### Acceptance criteria

- Display name variants do not drop valid selected characters.
- Duplicate names are distinguishable by stable ID.
- Generated item without selected `source_id` is rejected with a clear validation error.
- Existing UI still displays human names.
- Existing repository save format remains compatible.

### Recommended owner agent

Agent A — SceneBatch Identity.

## 5. SB-02 SceneBatch Giant Structured Response

Status: CONFIRMED
Severity: P1
Category: LLM orchestration + retry/cost scaling defect

### User-visible symptom

When importing multiple long cards, the LLM may successfully generate early items but truncate or corrupt the tail JSON. The whole batch is rejected or retried, causing:

- “批量资料生成结果格式无效”
- “未识别到可导入的角色卡”
- long latency
- high token cost
- loss of partial successful items

### Direct cause

`AiGeneratorService.generateSceneBatchCharacters()` makes one `_callText()` call with `maximumOutputTokens: 8192` and expects one JSON object containing all items.

Evidence:

- `lib/services/ai_generator_service.dart:1999-2026`
- `lib/application/resource_library/import_use_cases.dart:395-467`

### Root cause

SceneBatch treats a batch as a single atomic LLM generation unit. It lacks per-character job orchestration, per-item validation, checkpointing, per-item retry, and partial success semantics.

### Relevant call chain

```text
UI selected N names
→ SceneBatchImportUseCase.importSelected()
→ LlmGateway.generateSceneBatchCharacters(selectedNames: N)
→ AiGeneratorService.generateSceneBatchCharacters()
→ one prompt includes source, worldview, relatedCharacters, selectedNames, detailInstruction
→ one `_callText(maximumOutputTokens: 8192)`
→ one JSON object: {"items":[...N cards...]}
→ UseCase validates and saves one batch
```

### Failure chain

```text
Trigger: user selects 5–10 characters with 3000–5000 target chars each
→ one prompt requests every selected card in one response
→ required visible text alone can reach 25k–50k Chinese chars
→ output budget is fixed at 8192 tokens
→ model truncates or compresses response
→ JSON tail becomes incomplete/malformed or items become under-length
→ parse/validation fails
→ successful earlier items are discarded
→ retry, if any, repeats the whole batch instead of failed item only
```

### Scaling estimate

The UI initializes character imports with:

```text
minimum: 3000
maximum: 5000
```

The UseCase enforces max per card:

```text
character: 5000
npc: 3000
```

The service output cap is:

```text
maximumOutputTokens: 8192
```

Rough feasibility:

| Selection | Target visible characters | Risk |
| --------- | ------------------------- | ---- |
| 1 × 5000 | 5000 chars + JSON overhead | borderline but plausible |
| 3 × 5000 | 15000 chars + JSON overhead | high truncation risk |
| 5 × 5000 | 25000 chars + JSON overhead | not suitable for one response |
| 10 × 5000 | 50000 chars + JSON overhead | structurally unsuitable |

### Why existing safeguards fail

- `_resolveContent()` only protects detailed generation paths that pass `expectJsonObject:true`; SceneBatch calls `_callText()` without `expectJsonObject:true`.
- Generic `LLMService.sendMessageStream()` rejects incomplete stream results, but it cannot convert a giant valid-but-underfilled JSON into per-item retry.
- `ResourceIntegrityValidator` runs only after the whole response is parsed and filtered.
- Repository `saveCardBatch()` is atomic at save time, but no partial generated item is preserved before that.

### Existing tests

No SceneBatch-specific test covers:

- output truncation
- selected count scaling
- one item malformed with others valid
- retry boundaries
- partial success/resume

### Missing tests

- 5 selected characters should schedule 5 generation jobs, not one giant request.
- One failed item should not discard successful generated items.
- Cancel/resume should not regenerate already committed successful items.
- Retry should be per-item and bounded.
- Batch commit should be idempotent.

### Data compatibility impact

Moving to per-character jobs should not require DB migration if final cards still save through `ILibraryRepository.saveCardBatch()` or equivalent repository methods. A checkpoint model may need new storage, but it can start as in-memory if persistence is out of scope.

### Migration impact

No required schema change for minimal per-character generation. Persistent resume/checkpoints may require a future migration if durable across app restarts.

### LLM/token impact

Per-character jobs reduce wasted output tokens. Total successful token use may be similar, but failed/retry cost becomes proportional to failed items instead of the whole batch. Concurrency must be capped to avoid rate-limit amplification.

### Concurrency impact

Recommended limited concurrency:

```text
1–2 concurrent jobs by default
provider-aware concurrency cap
429/5xx use transport retry only
content retry per item
user cancellation cancels pending jobs and stops new starts
```

### Recommended design

```text
identify
→ stable candidate IDs
→ create per-character generation jobs
→ generate each selected candidate independently
→ validate each item independently
→ per-item retry with bounded content attempts
→ checkpoint successful items
→ final batch commit / summary
```

### Acceptance criteria

- No call to `generateSceneBatchCharacters()` asks the model for multiple 5000-character cards in one response.
- One item failure does not lose already successful items.
- Retry count is bounded and observable.
- Cancellation does not persist half-validated rows.
- Duplicate request IDs do not save duplicate cards.

### Recommended owner agent

Agent B — SceneBatch Generation Orchestration.

## 6. SB-03 SceneBatch Relationship Identity

Status: CONFIRMED
Severity: P1
Category: DTO identity contract

### User-visible symptom

Generated character cards can lose relationship links even when the model described valid relationships, if `targetName` differs from the existing related resource display name.

### Direct cause

`_validatedLinks()` maps relationships by exact `targetName`:

```dart
final target = relatedByName[targetName];
```

Evidence:

- `lib/application/resource_library/import_use_cases.dart:416-418`
- `lib/application/resource_library/import_use_cases.dart:470-498`

### Root cause

Related resources include stable `id`, but the LLM contract asks it to return `targetName`, not `targetResourceId`. The stable ID exists in the input context but is not the authoritative join key.

### Failure chain

```text
UI selects related resource with id=char_1, name=林月
→ relationshipContextOf sends {"id":"char_1","name":"林月",...}
→ prompt asks relationship_links to contain targetName
→ model outputs targetName=林月小姐 or 林 月
→ `_validatedLinks` searches relatedByName[targetName]
→ no exact match
→ relation link is silently dropped
→ saved card lacks relationship summary/details
```

### Why existing safeguards fail

The dedupe key uses `target['id']`, but only after an exact display-name lookup succeeds. `targetResourceId` is not accepted from the model or validated against allowed IDs.

### Existing tests

No direct test covers `_validatedLinks()` with display-name variants or stable target IDs.

### Recommended design

- Prompt and DTO should require `targetResourceId`.
- Validate `targetResourceId` against the allowed related resource ID set.
- Keep `targetName` as display only.
- If both ID and name are present, ID wins; name mismatch should become a diagnostic, not a drop.

### Acceptance criteria

- Relationship links survive target display-name variants.
- Unknown target IDs are rejected.
- Duplicate links are deduped by stable target ID, relation type, and normalized description.

### Recommended owner agent

Agent A — SceneBatch Identity.

## 7. LLM-01 CompletionParams Thinking Policy

Status: PARTIALLY_RESOLVED
Severity: P2
Category: LLM policy + product semantics

### User-visible symptom

Short helper calls can be slower and more expensive on DeepSeek-style providers because they inherit:

```dart
enableThinking = true
reasoningEffort = 'high'
```

### Direct cause

`CompletionParams` defaults to thinking enabled:

- `lib/models/completion_params.dart:15-23`

Several helper call sites instantiate `CompletionParams(...)` without explicit `enableThinking:false`:

| Call Site | Use | Current thinking behavior | Explicit control | Recommended strategy |
| --------- | --- | ------------------------- | ---------------- | -------------------- |
| `lib/services/translation_service.dart:41-46` | Translation | inherits default `true/high` | No | `enableThinking:false` |
| `lib/services/tts_service.dart:90-95` | TTS text cleanup | inherits default `true/high` | No | `enableThinking:false` |
| `lib/engines/chat_engine_internals/summary_service.dart:200-205` | Adventure timeline summary | inherits default `true/high` | No | `enableThinking:false` unless user explicitly chooses |
| `lib/services/ai_import_service.dart:90` | AI import helper | inherits default `true/high` | No | `enableThinking:false` for normal extraction |
| `lib/services/ai_generator_service.dart:2113` | Vision generation helper | inherits default `true/high` | No | explicit mode-dependent setting |
| `lib/application/llm/ai_generator_llm_gateway.dart:224-228` | raw JSON completion/helper | inherits default `true/high` | No | `enableThinking:false` for JSON/helper |
| `lib/services/llm_service.dart:133,164,195,253,439` | API defaults | default fallback | No | acceptable only as low-level API default if caller owns policy |
| `lib/providers/settings_provider.dart:106,314` | User settings default | default `true/high` | Indirect UI setting | product decision; do not change blindly |
| `lib/services/ai_generator_service.dart:_callText/_callMessages` | Resource generation | `enableThinking: generationMode == deepThinking` | Yes | mostly resolved |
| `ChatEngine` main response | Interactive chat | uses user settings via host completion params | Yes | preserve user control |
| `NarrativeLengthGuard` supplement | Length supplement | copies params but forces `enableThinking:false` | Yes | resolved |

### Root cause

The codebase mixes two meanings into one default:

1. User-facing interactive chat preference.
2. Low-level helper/extraction default.

Interactive chat may legitimately use user-configured thinking. Helper calls should be opt-in because they are deterministic, short, latency-sensitive, and usually structured.

### Failure chain

```text
Trigger: Translation/TTS/Summary/helper calls LLMService
→ caller passes const CompletionParams(maxTokens..., temperature...)
→ enableThinking omitted
→ CompletionParams default sets thinking enabled/high
→ DeepSeek request map includes thinking enabled and reasoning_effort high
→ helper task incurs extra reasoning latency/cost
→ user sees slow non-chat operation or higher token cost
```

### Why existing safeguards fail

`LlmGenerationMode.fast/deepThinking` only protects paths that use `AiGeneratorService._callText/_callMessages` or explicit resource import requests. Direct `LLMService.sendMessageStream()` helper calls bypass that policy.

### Existing tests

- `test/unit/p0_detailed_character_generation_test.dart` verifies fast/deepThinking for detailed generation.
- `test/unit/chat_engine_and_prompt_test.dart` verifies length supplement disables thinking while preserving main chat params.
- `test/unit/deepseek_reasoning_test.dart` verifies request-map behavior.

Missing:

- No inventory-style tests assert translation/TTS/summary/rawCompletion use non-thinking params.

### Data compatibility impact

Changing global default can alter existing user settings and interactive chat semantics. This is why a direct global default flip is risky.

### Recommended design

Use explicit call-site policy first:

```text
interactive chat → use user settings
deep resource generation → explicit thinking=true
normal resource generation → explicit false
translation → false
summary → false
TTS helper → false
classification → false
JSON extraction/repair → false
metadata extraction → false
```

Longer term, split defaults:

- `CompletionParams.chatDefault()`
- `CompletionParams.helperDefault()`
- `CompletionParams.structuredDefault()`
- `CompletionParams.deepReasoning()`

### Acceptance criteria

- No short helper call inherits thinking accidentally.
- Chat continues to respect user settings.
- Deep resource generation remains opt-in and tested.
- DeepSeek request maps show `thinking:{type:"disabled"}` for helper paths.

### Recommended owner agent

Agent C — LLM Thinking Policy.

## 8. CI-01 GitHub CI Missing Regression Gate

Status: CONFIRMED
Severity: P1
Category: engineering governance

### User-visible symptom

A release can be successfully published even when Dart format, analyzer, or tests would fail, because release workflow only validates build/release mechanics.

### Direct cause

`.github/workflows/release-arm64.yml` contains:

```text
flutter pub get
read pubspec version
flutter build apk --release --target-platform android-arm64
verify ARM64 native libs
upload artifact
gh release create
```

It does not contain:

```text
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --reporter compact
```

Evidence:

- `.github/workflows/release-arm64.yml:38-88`
- GitHub API: `main.protected=false`, `required_status_checks=[]`

### Root cause

Build/release automation and quality gate automation are conflated. There is no required check preventing direct push/tag release of untested logic.

### Failure chain

```text
Developer does not run local tests
→ push to main or tag release
→ release workflow builds APK successfully
→ ABI verification passes
→ GitHub Release is created
→ release artifact can include logical regression
```

### Why existing safeguards fail

Build success only proves the app compiles into an APK. It does not validate unit/widget behavior, parser contracts, retry budgets, SceneBatch identity, runtime isolation, or regressions.

### Existing tests

The repository has meaningful tests, including P0 regression tests. They are not required by GitHub before release.

### Missing tests / checks

- CI workflow running format/analyze/test on push/PR.
- Required status checks on `main`.
- Release workflow dependency on a quality gate.

### Recommended design

Option A:

```text
quality-gate workflow:
  dart format --output=none --set-exit-if-changed .
  flutter analyze
  flutter test --reporter compact

release workflow:
  requires quality-gate success for the tagged commit
  then build/release
```

Option B:

```text
release-arm64 workflow:
  flutter pub get
  dart format --output=none --set-exit-if-changed .
  flutter analyze
  flutter test --reporter compact
  flutter build apk ...
```

Also:

- Enable branch protection for `main`.
- Require quality-gate status checks.
- Disallow direct unreviewed force pushes.
- Update actions to Node 24-compatible majors when available. Current v1.1.4 release showed a non-blocking Node.js 20 deprecation annotation for `actions/checkout@v4` and `actions/upload-artifact@v4`.

### Acceptance criteria

- A commit with failing test cannot be merged to protected `main`.
- A release tag cannot create a published APK unless format/analyze/test pass for that exact commit.
- Release notes/tag version match `pubspec.yaml`.
- ARM64-only APK and SHA256 artifact remain preserved.

### Recommended owner agent

Agent D — CI Quality Gate.

## 9. TB-01 / TB-02 Trust Boundary Review

Status: mixed; key v1.1.4 items RESOLVED, new lower-priority issues remain.

### Resolved items

`CharacterCard` import parser split is resolved:

- `_cardFromJson()` now delegates to the tolerant `fromJson()` path.
- `fromJsonString()` tolerates non-object top-level JSON.
- Relevant tests: `test/unit/character_card_import_parser_test.dart`.

`ModelContextCapability` and `CompletionParams` persisted scalar variants are resolved:

- New helper: `lib/core/utils/json_value_reader.dart`
- `ModelContextCapability.fromJson()` uses tolerant scalar readers.
- `CompletionParams.fromJson()` uses tolerant scalar readers.
- Relevant tests: `test/unit/legacy_json_settings_boundary_test.dart`.

### Remaining trust-boundary pattern

Search still finds many strict casts. Most are internal DTOs or current SQLite row contracts and are not automatically bugs. The relevant unresolved cases are persisted/external boundaries where one bad row can block a wider feature.

### TB-03 Scene runtime row isolation

Status: NEW
Severity: P2

Direct cause:

- `getScenePresence()` decodes `participant_ids_json` with `jsonDecode(...) as List` and casts `actor_id as String`.
- `getSceneState()` decodes `scene_runtime_state.state_json` through `SceneState.decode(rows.single['state_json'] as String)`.

Evidence:

- `lib/services/repositories/adventure_repository_impl.dart:795-831`

Root cause:

Runtime entity row isolation was added for `adventure_runtime_entities`, but the older scene runtime tables still use strict single-row decode semantics. They are persisted state and should follow the same isolation/default contract.

Failure chain:

```text
SQLite row scene_presence or scene_runtime_state becomes malformed
→ repository read decodes with strict cast
→ FormatException/TypeError propagates
→ scene context/runtime resolver cannot read state
→ adventure screen or next generation context may fail despite other data being valid
```

Why existing safeguards fail:

- `getRuntimeEntities()` has row isolation; `getScenePresence()` and `getSceneState()` do not.
- Current tests cover valid scene state round-trip, not malformed row isolation.

Recommended design:

- Treat `scene_presence` and `scene_runtime_state` as persisted legacy boundaries.
- On malformed scene presence, return `null` and log diagnostic.
- On malformed scene state, return `null` or a safe empty `SceneState` according to resolver semantics.
- Do not mutate or delete bad rows in the read path.

Acceptance criteria:

- One corrupt scene presence/state row cannot block Adventure loading or next context construction.
- Existing valid scene state round-trip behavior remains unchanged.
- Malformed row tests cover bad JSON, non-list participants, non-string actor, non-object scene state.

Recommended owner agent:

Agent E — Additional Trust-Boundary / Async Findings.

## 10. Async Lifecycle Review

### Resolved: ASYNC-01 AdventureSetup stale load

Status: RESOLVED
Severity: previously P1

Evidence:

- `AdventureSetupController` now uses monotonic generation guards and `_disposed`.
- Tests in `test/unit/adventure_setup_controller_concurrency_test.dart` cover:
  - older load cannot overwrite newer load
  - stale error cannot overwrite newer success
  - stale success cannot clear newer error
  - loading remains true until newest load completes
  - reset invalidates in-flight loads
  - dispose during in-flight load does not notify

No confirmed remaining stale-load issue was found in this controller.

### Additional async notes

No new confirmed P0/P1 async lifecycle regression was found during this pass. There are still broad UI `setState` and `mounted` patterns, but the audited key resource import pages generally guard `mounted` after awaits.

## 11. Runtime State Versioning Review

Status: largely RESOLVED for v1.1.4 core runtime goals.

### Verified properties

1. Frozen `AdventureConfig` snapshots are preserved.
   - Test: `runtime commits preserve frozen config and are idempotent`.
2. Runtime records deltas/overlays in `adventure_runtime_entities` and state commits.
3. Branch overlays are copied at branch creation and isolated afterward.
4. `revision` increments only when valid runtime changes apply.
5. `expectedRevision` prevents stale runtime commits.
   - Evidence: `_applyRuntimeDraft()` checks `draft.expectedRevision != currentRevision`.
6. Scene dialogue commit and runtime state commit occur in one SQLite transaction.
   - Evidence: `commitSceneDialogueTurn()` wraps all inserts/updates in `db.transaction`.
7. Duplicate `request_id` is idempotent at `scene_dialogue_turns`.
8. Runtime entities are read back through `getRuntimeEntities()`.
9. Bad `adventure_runtime_entities` rows are isolated.
10. Runtime tables define `ON DELETE CASCADE` for `adventure_id`.

### Remaining runtime concerns

#### Runtime delete coverage

The schema defines cascade for v28 runtime tables, but `deleteAdventure()` manually deletes older tables and then deletes `adventures`; it does not explicitly delete runtime tables. This is acceptable if SQLite foreign keys are always enabled. The audit did not find a failing test specifically asserting `deleteAdventure()` removes runtime tables.

Recommended test for future hardening:

```text
create adventure
seed runtime head/entities/commits/changes
delete adventure
assert runtime tables have no rows for that adventure
```

Status: INSUFFICIENT_EVIDENCE, not filed as confirmed bug.

#### Scene runtime bad row

Covered as TB-03. It is adjacent to runtime but not the new v28 adventure runtime entity table.

## 12. LLM Structured Output Review

Status: no confirmed P0 regression found.

Evidence:

- `LLMService.sendMessageStream()` rejects incomplete detailed stream results before returning content.
- `AiGeneratorService._resolveContent(expectJsonObject:true)` rejects `!responseCompleted`, disallowed finish reasons, and truncation before JSON repair.
- Existing tests:
  - `test/unit/p0_structured_output_incomplete_test.dart`
  - `test/unit/p0_llm_service_truncation_test.dart`
  - `test/unit/p0_stage_payload_normalizer_test.dart`
  - `test/unit/p0_retry_budget_test.dart`

Gap:

- SceneBatch does not use `expectJsonObject:true`, and it does not have per-item structured validation. This is already captured by SB-02.

## 13. Test Quality Review

| Area | Classification | Notes |
| ---- | -------------- | ----- |
| AdventureSetup concurrency | REAL REGRESSION | Direct controller tests force completion order and state checks. |
| Wizard submit deadlock | REAL REGRESSION | Widget tests exercise production wizard screen and failure boundaries. |
| CharacterCard import parser | REAL REGRESSION | Tests cover JSON/PNG import variants and tolerant parser behavior. |
| Legacy JSON settings | REAL REGRESSION | Tests cover numeric/string/bool persisted variants. |
| Runtime entity bad row | REAL REGRESSION | Repository test inserts malformed rows into real test DB and asserts isolation. |
| Structured output truncation | REAL REGRESSION | Tests assert incomplete results are rejected despite repairable prefixes. |
| Stage schema scalar bug | REAL REGRESSION | Tests assert malformed scalar stage values do not pass canonical pipeline. |
| Resource import generation modes | PARTIAL | Verifies explicit fast/deep mode in key paths; helper calls remain uncovered. |
| SceneBatch identity | MISSING | No production-path test for renamed generated item or stable identity. |
| SceneBatch scaling | MISSING | No test for batch size, truncation, partial success, or per-item retry. |
| CI release workflow | MISSING | No workflow quality gate exists. |
| Scene runtime bad rows | MISSING | Valid round-trip exists; malformed persisted rows are not covered. |

## 14. Newly Discovered Problems

### TB-03 Scene runtime bad row can block scene state/presence read

See section 9. This is the main newly discovered non-P0 problem outside the requested four focus areas.

### Release workflow Node.js 20 deprecation annotation

Status: NEW
Severity: P3
Category: engineering governance

The v1.1.4 release workflow completed successfully but GitHub emitted:

```text
Node.js 20 is deprecated. actions/checkout@v4, actions/upload-artifact@v4 are being forced to run on Node.js 24.
```

This is not blocking today, but it is future runner compatibility risk. It should be addressed as part of CI work, not as an emergency fix.

## 15. Root Cause Dependency Graph

```text
No stable SceneBatch candidate identity
├─ SB-01 generated item display-name mismatch drops cards
└─ SB-03 relationship targetName mismatch drops links

Single atomic SceneBatch generation request
├─ SB-02 truncation/malformed tail fails whole batch
├─ no partial success
├─ no per-item retry
└─ token/cost amplification

CompletionParams default mixes chat and helper semantics
├─ helper calls inherit thinking=true
└─ chat settings cannot be globally changed safely without policy split

No GitHub quality gate
├─ release build can succeed without tests
├─ main has no required checks
└─ formal release can carry logical regressions

Persisted runtime row isolation incomplete
├─ v28 runtime entities now isolated
└─ older scene runtime rows still strict
```

## 16. Recommended Remediation Order

1. Agent A — SceneBatch stable identity and relationship identity.
2. Agent B — SceneBatch per-character generation orchestration.
3. Agent D — CI quality gate and branch protection recommendations.
4. Agent C — explicit helper Thinking policy.
5. Agent E — scene runtime persisted row isolation and any additional trust-boundary follow-up.

Rationale:

- Agent B depends on Agent A’s stable candidate IDs.
- CI can run independently and should be added before or alongside larger SceneBatch changes.
- Thinking policy is lower risk but broad; it should not be mixed with SceneBatch changes.
- TB-03 is isolated and should not block SceneBatch remediation.

## 17. Recommended Agent Work Packages

### Agent A — SceneBatch Identity

Problem:

SceneBatch uses display names as cross-stage identity and relationship join keys.

Root cause:

No stable candidate/resource identity contract exists between identify, selection, generation, validation, and persistence.

Exact files:

- `lib/application/resource_library/import_models.dart`
- `lib/application/resource_library/import_use_cases.dart`
- `lib/application/llm/llm_gateway.dart`
- `lib/application/llm/ai_generator_llm_gateway.dart`
- `lib/services/ai_generator_service.dart`
- `lib/controllers/scene_batch_import_controller.dart`
- `lib/screens/resource_library/scene_batch_import_page.dart`

Exact functions:

- `SceneBatchImportUseCase.identify`
- `SceneBatchImportUseCase.importSelected`
- `SceneBatchImportUseCase._validatedLinks`
- `AiGeneratorService.identifyCharacterNames`
- `AiGeneratorService.generateSceneBatchCharacters`
- `_SceneBatchImportPage._confirmCandidates`
- `_SceneBatchImportPage._import`

Do not change:

- Existing saved card schema unless required.
- Resource Library visual design.
- Prompt wording as a substitute for structural identity.
- Repository public API more than necessary.

Recommended implementation:

- Introduce a candidate DTO with stable `sourceId`.
- Selection uses IDs.
- Generation must return `sourceId`.
- Relationship links use `targetResourceId`, not `targetName`.
- Validate generated IDs against selected IDs.

Compatibility constraints:

- Existing imported cards remain readable.
- Existing library cards remain selectable as relationship context.
- Names remain display-only.

Required tests:

- Name variant preserves item by ID.
- Duplicate display names remain distinct.
- Unknown source ID rejected.
- Missing source ID rejected.
- Relation target display-name variant still maps by ID.

Acceptance criteria:

- No selected item is dropped solely because the LLM changed display name.
- No relationship is dropped solely because target display text changed.

Suggested commit boundary:

`fix(scene-batch): use stable candidate identity`

Dependencies:

None, but Agent B should start after this lands.

### Agent B — SceneBatch Generation Orchestration

Problem:

SceneBatch generates all selected characters in one giant JSON response.

Root cause:

Batch is treated as one LLM unit instead of a set of per-character jobs.

Exact files:

- `lib/application/resource_library/import_use_cases.dart`
- `lib/application/resource_library/import_models.dart`
- `lib/application/llm/llm_gateway.dart`
- `lib/application/llm/ai_generator_llm_gateway.dart`
- `lib/services/ai_generator_service.dart`
- `lib/controllers/scene_batch_import_controller.dart`

Exact functions:

- `SceneBatchImportUseCase.importSelected`
- `AiGeneratorService.generateSceneBatchCharacters`
- `SceneBatchImportController.importSelected`

Do not change:

- CharacterCard parser.
- Runtime schema.
- Global retry manager behavior.
- UI styling.

Recommended implementation:

- Split selected candidates into independent generation jobs.
- Limit concurrency.
- Validate and retry per item.
- Preserve successful items until final save.
- Add cancellation and idempotency boundaries.

Compatibility constraints:

- Final saved cards should still go through `ILibraryRepository`.
- Do not create duplicate cards on retry.

Required tests:

- 5 selected candidates produce 5 generation calls.
- One failed item does not discard four successful items.
- Retry is bounded per item.
- Cancellation prevents pending persistence.
- Batch save remains atomic or reports partial state clearly.

Acceptance criteria:

- Giant 5×5000 output request no longer exists.
- Partial success is not lost.

Suggested commit boundary:

`fix(scene-batch): generate selected cards as bounded jobs`

Dependencies:

Agent A stable identity.

### Agent C — LLM Thinking Policy

Problem:

Helper calls inherit `CompletionParams` thinking defaults.

Root cause:

Chat defaults and helper defaults are not separated.

Exact files:

- `lib/models/completion_params.dart`
- `lib/services/translation_service.dart`
- `lib/services/tts_service.dart`
- `lib/engines/chat_engine_internals/summary_service.dart`
- `lib/services/ai_import_service.dart`
- `lib/services/ai_generator_service.dart`
- `lib/application/llm/ai_generator_llm_gateway.dart`
- related tests under `test/unit/`

Exact functions:

- `TranslationService.translate`
- `TtsService.synthesizeWithLLM`
- `SummaryService` timeline summary call
- `AiGeneratorLlmGateway.rawCompletion`
- `_callVision`

Do not change:

- User chat settings semantics.
- Deep-thinking explicit resource generation behavior.
- DeepSeek request-map contract.

Recommended implementation:

- Add explicit `enableThinking:false` to helper calls.
- Consider named constructors for helper/chat/deep defaults.
- Keep interactive chat user-controlled.

Compatibility constraints:

- Existing persisted `CompletionParams` still load.
- Existing presets still work.

Required tests:

- Translation passes disabled thinking.
- TTS helper passes disabled thinking.
- Summary helper passes disabled thinking.
- raw JSON helper passes disabled thinking.
- Chat still preserves user thinking setting.

Acceptance criteria:

- No helper call accidentally uses `true/high`.
- Chat default decision remains explicit.

Suggested commit boundary:

`fix(llm): make helper calls non-thinking by policy`

Dependencies:

None.

### Agent D — CI Quality Gate

Problem:

GitHub release can publish without regression tests.

Root cause:

No quality-gate workflow and no protected main required checks.

Exact files:

- `.github/workflows/release-arm64.yml`
- possibly new `.github/workflows/quality-gate.yml`

Exact functions:

Not applicable.

Do not change:

- Android ARM64 artifact naming.
- SHA256 generation.
- Release title/tag convention.

Recommended implementation:

- Add CI workflow with format/analyze/test.
- Make release depend on quality gate for exact commit, or run same checks before build.
- Update Actions versions if Node 24-compatible majors are available.
- Configure branch protection in GitHub settings.

Compatibility constraints:

- Manual dispatch release remains supported.
- Tag release still builds ARM64-only APK.

Required tests:

- Workflow lint by `gh workflow view` / dry run if available.
- Confirm tag build still uploads APK and SHA256.

Acceptance criteria:

- A failing test blocks release.
- `main` requires passing quality checks.

Suggested commit boundary:

`ci: add Flutter regression quality gate`

Dependencies:

None.

### Agent E — Additional Trust-Boundary / Async Findings

Problem:

Some persisted scene runtime rows still decode strictly.

Root cause:

Runtime row isolation was applied to v28 entity overlays but not older scene runtime state/presence reads.

Exact files:

- `lib/services/repositories/adventure_repository_impl.dart`
- `lib/models/scene_state.dart`
- `test/unit/database_and_repositories_test.dart`

Exact functions:

- `getScenePresence`
- `getSceneState`
- `SceneState.decode`

Do not change:

- DB schema.
- Runtime data model.
- Existing valid scene state format.

Recommended implementation:

- Add tolerant read wrappers for persisted scene runtime rows.
- Log and return safe absence/default for malformed rows.
- Do not delete bad rows in read path.

Compatibility constraints:

- Valid rows must remain unchanged.
- Bad row handling must not hide repository write failures.

Required tests:

- Bad `participant_ids_json` does not throw.
- Bad `scene_runtime_state.state_json` does not throw.
- Valid scene state still round-trips.

Acceptance criteria:

- One corrupt scene runtime row cannot block next Adventure context construction.

Suggested commit boundary:

`fix(runtime): isolate malformed scene runtime rows`

Dependencies:

None.

## 18. Acceptance Criteria For Future Agents

General:

- Do not modify unrelated UI styling.
- Do not suppress errors with silent broad catches unless the boundary is explicitly a tolerant persisted/external read path and diagnostics are preserved.
- Do not use prompt text alone as a substitute for structural validation.
- Do not weaken existing tests.
- Run:

```text
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --reporter compact
```

SceneBatch:

- Identity is stable and machine-readable across identify, selection, generation, relationship binding, validation, and persistence.
- Display names are never primary keys.
- Batch generation is bounded, resumable or at least partial-success aware, and retry is per item.

Thinking:

- Helper calls are non-thinking by explicit policy.
- Chat remains user-configurable.

CI:

- Release build success must depend on regression validation success.
- `main` should have required checks.

Runtime/trust boundary:

- Persisted bad rows should not collapse an entire feature if valid neighboring rows can still be used.
- Internal canonical DTOs may remain strict where the producer and consumer are within the same trusted boundary.
