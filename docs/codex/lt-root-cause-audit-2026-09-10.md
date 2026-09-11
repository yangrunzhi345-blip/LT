# LT Root Cause Audit

> **文档状态**：✅ **已完成 (Completed)**（审计结论已整改并验证：`dc7893e` / v1.1.4）
> **参考策略**：本文档已归档，仅作历史记录。后续任务默认不再参考或遵循本文件内容，除非用户明确要求。

Audit date: 2026-09-10

Scope: root-cause audit only. No production code was changed in this task.

## 1. Audit Baseline

Commands executed before analysis:

```text
git status --short
git branch --show-current
git rev-parse HEAD
git log -10 --oneline
git remote -v
git fetch origin
git rev-parse origin/main
```

Verified baseline:

| Item | Value |
| --- | --- |
| Branch | `main` |
| Local HEAD | `7cca4d17173ce8f94453b2b57f492908215ecdfe` |
| origin/main | `7cca4d17173ce8f94453b2b57f492908215ecdfe` |
| HEAD commit | `fix(release): harden P0 stability paths` |
| Working tree before audit doc | clean |
| Remote | `https://github.com/yangrunzhi345-blip/LT.git` |
| pubspec version | `1.1.3+6` |
| Latest tag | `v1.1.3` |
| Release | `LT Dialogue v1.1.3`, published 2026-09-10T08:05:15Z |
| Release workflow run | `34452691368`, success, head SHA `7cca4d17173ce8f94453b2b57f492908215ecdfe` |
| Database schema version | `28` in `DatabaseService._initDb()` |

Validation commands run during audit:

```text
flutter analyze
flutter test test/unit/p0_structured_output_incomplete_test.dart test/unit/p0_stage_payload_normalizer_test.dart test/unit/p0_retry_budget_test.dart test/widget/p0_adventure_wizard_start_boundary_test.dart test/widget/p0_adventure_wizard_loading_test.dart test/unit/resource_import_semantics_test.dart test/unit/detailed_generation_and_wizard_test.dart test/unit/database_and_repositories_test.dart
flutter test test/unit/p0_llm_service_truncation_test.dart test/unit/p0_detailed_character_generation_test.dart test/unit/character_generation_pipeline_semantics_test.dart test/unit/narrative_runtime_test.dart test/unit/adventure_assembly_semantics_test.dart
flutter test
```

Results:

| Command | Result |
| --- | --- |
| `flutter analyze` | No issues found |
| Targeted P0/import/runtime/assembly tests | All passed |
| Full `flutter test` | 268 passed |

Network note: the sandboxed Flutter commands could not resolve `pub.flutter-io.cn`; reruns with network escalation completed successfully.

## 2. Executive Summary

The previously released P0 fixes are materially effective: wizard submit recovery, structured truncation rejection, stage schema normalization, retry bounds, resource-load isolation, worldview origin ordering, and unset relationship semantics are all covered by passing targeted and full tests.

The audit still found unresolved architecture-level risks:

- `AdventureSetupController.loadInitialData()` still permits overlapping loads and has no single-flight, sequence token, latest-wins guard, dispose guard, or stale-error protection.
- `CharacterCard` still has two parser contracts. Normal persisted reads are tolerant through `CharacterCard.fromJson()` and `CharacterCardEntry.fromRow()`, but explicit JSON/PNG imports still call `_cardFromJson()` with strict casts.
- Several persisted legacy boundaries still use strict casts. The most concrete current risk is `ModelContextCapability.fromJson()` and `CompletionParams.fromJson()` with numeric/bool legacy variants.
- SceneBatch uses display name equality as cross-stage identity and still generates the entire selected batch in one giant JSON response.
- `CompletionParams` product paths for resource AI generation mostly override thinking explicitly, but low-level defaults still enable thinking for helper/summary/import/service paths that use `const CompletionParams(...)`.
- Runtime state versioning is mostly sound, but one malformed runtime entity row can still crash `getRuntimeEntities()` and block Adventure context loading.
- Release workflow builds and publishes successfully but does not run format/analyze/test. `main` has no branch protection and no required status checks.

## 3. Issue Status Matrix

| ID | Severity | Status | Root Cause | Evidence | Affected Layer | Recommended Owner |
| -- | -------- | ------ | ---------- | -------- | -------------- | ----------------- |
| ISSUE-01 | P1 | CONFIRMED | Shared controller has no load generation or single-flight contract | `AdventureSetupController.loadInitialData()` writes `_worldviewPresets/_characterCards/_npcCards/_loading` after `Future.wait` without checking whether this is still the newest request | Controller / Provider / UI state | Agent A |
| ISSUE-02 | P1 | PARTIALLY_RESOLVED | CharacterCard has tolerant persisted parser and strict import parser in parallel | `fromJson()` uses `_asText/_asTextList`; `parseFromJson()` and `parseFromPngBytes()` call `_cardFromJson()` with `as String?`, `as Map<String,dynamic>?`, `.cast<String>()` | Model / external import | Agent B |
| ISSUE-03 | P1 | CONFIRMED | Persisted legacy settings/model metadata are parsed with strict runtime casts | `ModelContextCapability.fromJson()` casts token fields as `int?` and booleans as `bool?`; `CompletionParams.fromJson()` casts `max_tokens` as `int?`, `enable_thinking` as `bool?` | Persisted legacy boundary | Agent B |
| ISSUE-04 | P1 | CONFIRMED | SceneBatch lacks stable identity between identify and generation stages | `SceneBatchImportUseCase.importSelected()` filters generated items by `selectedNames.contains(item['name']?.toString().trim())` | LLM DTO / matching algorithm | Agent C |
| ISSUE-05 | P1 | CONFIRMED | SceneBatch treats multi-character long generation as a single JSON request | `generateSceneBatchCharacters()` sends all selected names and uses one `maximumOutputTokens: 8192` response | LLM orchestration / batch persistence | Agent C |
| ISSUE-06 | P2 | PARTIALLY_RESOLVED | Low-level `CompletionParams` default represents long-form reasoning, but helper call sites inherit it | Constructor defaults `enableThinking=true`, `reasoningEffort='high'`; resource import paths set mode, summary/translation/import helpers often do not | LLM policy | Agent D |
| P0-A | P0 | RESOLVED | Previous wizard submit failure paths lacked reliable regression coverage | `_handleStart()` has broad `try/catch/finally`; boundary widget tests cover save/load/assembly/start failures | Wizard UI / controller integration | Agent A |
| P0-B | P0 | RESOLVED | Incomplete structured responses could be repaired into accepted data | `p0_structured_output_incomplete_test` and `p0_llm_service_truncation_test` reject length/maxTokens/interrupted/incomplete stop outputs | LLM service / structured parser | Agent C |
| P0-C | P0 | RESOLVED | Stage schema accepted wrong scalar types before consumer casts | `p0_stage_payload_normalizer_test` rejects `{"name":123}`, `{"gender":true}`, malformed list/map text fields | Stage normalizer / validator | Agent B |
| P0-D | P0 | RESOLVED | Stage2B nested `world_profile` did not match downstream flat contract | `DetailedCharacterStageNormalizer` folds nested world_profile before validation; tests cover root-vs-nested precedence | Detailed character generation | Agent B |
| P0-E | P0 | RESOLVED | Retry semantics could multiply or loop unexpectedly | `p0_retry_budget_test` verifies transport/content budgets, 429, 5xx, timeout, cancellation, and content failure boundaries | Retry policy | Agent D |
| P0-F | P0 | RESOLVED | One resource type failure could blank the Wizard | `AdventureSetupController` isolates world/character/NPC loads; tests cover poisoned row and per-type failure | Resource loading / Wizard | Agent A |
| P0-G | P0 | RESOLVED | `matching_worldview_id` could act as hard allow-list | `WorldviewCharacterScopePolicy.filterSceneResources()` orders all resources, tests assert cross-world still selectable | Resource scope policy | Agent A |
| P0-H | P0 | RESOLVED | Unset relation could be converted into role/default relation | `AdventureAssembler` tests keep undefined relation empty and clear role pollution | Adventure assembly | Agent A |
| RUNTIME-01 | P1 | NEW | Runtime entity reads are strict while runtime tables are persisted state | `getRuntimeEntities()` maps enum by name and decodes `state_json` with strict casts; no bad-row isolation test exists | Runtime repository / Adventure open | Agent F |
| CI-01 | P1 | NEW | Release build is the only workflow and is not a regression gate | `.github/workflows/release-arm64.yml` runs pub get/build/APK checks/release only; GitHub branch API reports `protected:false` | CI / release governance | Agent E |

Status counts in this matrix:

| Status | Count |
| --- | ---: |
| RESOLVED | 8 |
| PARTIALLY_RESOLVED | 2 |
| CONFIRMED | 4 |
| NEW | 2 |
| REGRESSION | 0 |
| NOT_REPRODUCIBLE | 0 |
| INSUFFICIENT_EVIDENCE | 0 |

## 4. P0 Regression Review

P0-A Wizard submit deadlock: RESOLVED.

Evidence:

- `AdventureWizardScreen._handleStart()` wraps save worldview, `setupController.loadInitialData()`, character save, domain assembly, snapshot/config assembly, and `onStartAdventure(config)` in `try/catch/finally`.
- `finally` executes `if (mounted) setState(() => _submitting = false);`.
- `test/widget/p0_adventure_wizard_start_boundary_test.dart` covers `onStartAdventure` failure retry, character save failure, worldview save failure, `loadInitialData` failure, and malformed custom attributes/domain assembly failure.
- The targeted and full test runs both passed.

Failure chain now contained:

```text
Injected save/load/assembly/start failure
→ _handleStart catch
→ safe feedback
→ finally clears _submitting
→ no navigation
→ retry remains possible
```

Test quality: REAL REGRESSION for submit recovery. It uses fake dependencies to avoid FakeAsync real I/O deadlock, which is appropriate for the widget boundary. It still does not cover every real sqflite failure mode, but repository-level tests cover persistence separately.

P0-B Structured truncated JSON: RESOLVED.

Evidence:

- `test/unit/p0_llm_service_truncation_test.dart` rejects finish reasons `length`, `maxTokens`, `interrupted`, and `stop` with `responseCompleted=false`.
- `test/unit/p0_structured_output_incomplete_test.dart` verifies truncated Stage1/Stage2A/Stage2B are re-requested and not accepted after repair.
- Bounded persistent truncation exhausts content budget instead of silently accepting partial data.

Failure chain now contained:

```text
LLM emits incomplete structured payload
→ LLMService marks response incomplete
→ content-stage retry or terminal structured failure
→ damaged prefix is not exposed as valid model data
```

Test quality: REAL REGRESSION. It asserts interrupted stream and bounded retry, not just parser helpers.

P0-C Stage schema scalar bug: RESOLVED.

Evidence:

- `test/unit/p0_stage_payload_normalizer_test.dart` rejects bool/map/list scalars for string fields and rejects malformed `taboos`.
- `StageSchemaValidator` comments explicitly bind schema validation to downstream consumer safety.

Failure chain now contained:

```text
LLM returns scalar/type-mismatched stage data
→ typed normalizer rejects or canonicalizes allowed exceptions
→ StageSchemaValidator sees canonical shape only
→ consumer no longer crashes on string casts
```

Test quality: REAL REGRESSION. It covers canonical pipeline and malformed input.

P0-D Stage2B nested world_profile: RESOLVED.

Evidence:

- `DetailedCharacterStageNormalizer` folds nested `world_profile` into the canonical flat Stage2B payload.
- Tests assert nested Stage2B survives into final card and root fields win over conflicting nested values.

Failure chain now contained:

```text
LLM returns nested world_profile
→ normalizer flattens to Stage2B contract
→ validator only sees canonical flat payload
→ assembler stores one coherent world_profile
```

Test quality: REAL REGRESSION.

P0-E Retry semantics: RESOLVED.

Evidence:

- `test/unit/p0_retry_budget_test.dart` verifies `maximumAttempts` includes first call, one retry for `2`, capped exponential backoff, `retryAfterMs`, non-retryable 4xx, transport classification, content failure exclusion, cancellation exclusion, structured content budget `transport=2/content=3`, schema-invalid stage exactly three content attempts, and transient transport retry within one content attempt.

Failure chain now contained:

```text
Transport/content failure
→ classified into transport or content bucket
→ bounded attempts applied
→ cancellation/content failure not treated as transport
→ no infinite or accidental multiplicative retry
```

Test quality: REAL REGRESSION.

P0-F Worldview / character / NPC independent loading: RESOLVED for per-type failure, not for stale concurrency.

Evidence:

- `AdventureSetupController._loadWorldview/_loadCharacters/_loadNpcs()` catch errors independently and return empty list per failed type.
- `test/unit/p0_adventure_resource_loading_test.dart` verifies one poisoned character row does not block two valid rows and a worldview failure keeps character/NPC usable.
- `test/widget/p0_adventure_wizard_loading_test.dart` verifies Wizard keeps usable resources selectable and reports damaged row.

Failure chain now contained:

```text
One resource source or row fails
→ only that resource loader stores its error / parse marker
→ other loader results are retained
→ Wizard can render usable resources
```

Test quality: REAL REGRESSION for isolation. It does not test concurrent stale result, which is ISSUE-01.

P0-G Worldview source association: RESOLVED.

Evidence:

- `WorldviewCharacterScopePolicy` documents `matching_worldview_id` as origin compatibility, not eligibility.
- `test/unit/adventure_assembly_semantics_test.dart` verifies legacy filter wrapper returns native, unbound, and cross-world resources.

Failure chain now contained:

```text
Selected worldview differs from resource origin
→ scope policy orders native resources first
→ cross-world resources remain selectable
→ no hard allow-list
```

Test quality: REAL REGRESSION.

P0-H Undefined relation: RESOLVED.

Evidence:

- `AdventureWizardScreen._handleStart()` writes supporting character relation as empty unless a relationship exists and normalizes to non-`unset`.
- `AdventureAssembler` tests keep undefined selected-character relation empty and preserve explicit relations.

Failure chain now contained:

```text
Character has role/suggestion but no explicit adventure relation
→ relationType remains unset
→ assembled runtime relation is empty
→ UI/AI context does not invent friend/ally/companion
```

Test quality: REAL REGRESSION.

## 5. ISSUE-01 AdventureSetup stale load

Status: CONFIRMED.

Direct cause:

`AdventureSetupController.loadInitialData()` always writes the result of its own `Future.wait` into shared controller state when it completes, regardless of whether a newer load has already started or finished.

Root cause:

The shared Adventure setup state has no concurrency contract. It is a global `ChangeNotifierProvider<AdventureSetupController>`, not `autoDispose`, and it has no single-flight deduplication, request generation, latest-wins guard, cancellation token, mounted/disposed guard, or stale error isolation.

Relevant code:

- `lib/controllers/adventure_setup_controller.dart:123-136`: sets `_loading=true`, awaits `Future.wait`, then assigns `_worldviewPresets`, `_characterCards`, `_npcCards`, `_loading=false`.
- `lib/controllers/adventure_setup_controller.dart:138-168`: per-type loaders mutate `_worldviewError`, `_characterError`, `_npcError` inside each async branch.
- `lib/providers/riverpod_providers.dart:144-149`: global `ChangeNotifierProvider<AdventureSetupController>`.
- `lib/features/adventure/presentation/home/widgets/dashboard_featured_worlds.dart:40-48`: Dashboard worlds card calls `loadInitialData()`.
- `lib/features/adventure/presentation/home/widgets/dashboard_character_cards.dart:40-48`: Dashboard character card calls `loadInitialData()`.
- `lib/features/adventure/presentation/wizard/screens/adventure_wizard_screen.dart:205-260`: Wizard initial load calls the same controller.
- `lib/features/adventure/presentation/wizard/screens/adventure_wizard_screen.dart:1791-1793`: Wizard submit calls `loadInitialData()` again after optional worldview save.

Full current call chain:

```text
DashboardFeaturedWorlds.initState / DashboardCharacterCards.initState / AdventureWizardScreen.initState
→ ref.read(adventureSetupControllerProvider)
→ shared AdventureSetupController
→ AdventureSetupController.loadInitialData()
→ Future.wait(_loadWorldview, _loadCharacters, _loadNpcs)
→ AdventureSetupUseCase
→ ILibraryRepository / LibraryRepositoryImpl
→ SQLite through DatabaseService.database
→ returned rows assigned to _worldviewPresets/_characterCards/_npcCards
→ notifyListeners()
→ UI copies shared controller state into local widget state
```

Failure chain:

```text
UI triggers load A from Dashboard worlds
→ UI triggers load B from Dashboard characters or Wizard
→ B returns first and writes fresh state
→ A returns later with an older snapshot or older error state
→ A overwrites controller rows/errors/loading
→ UI reads stale rows or stale error and regresses visible resource lists
```

Additional stale-loading variants:

- `loading=false` can be written by an older request while a newer request is still in flight.
- `_worldviewError/_characterError/_npcError` are mutated inside branch methods before the request is known to be current; an older branch can clear or set error state after a newer load.
- `reset()` does not invalidate in-flight loads. A later completion can repopulate state after reset.
- `_notify()` has no disposed guard. `ChangeNotifierProvider` will dispose the controller when the provider container is disposed; a late completion after dispose can call `notifyListeners()` on a disposed notifier.

Current tests:

- `p0_adventure_resource_loading_test.dart` covers per-type failure isolation and poisoned row isolation.
- `p0_adventure_wizard_loading_test.dart` covers Wizard rendering under damaged rows and mobile viewports.
- No test covers overlapping `loadInitialData()` calls with controlled delays, stale error overwrite, stale loading flag, `reset()` during in-flight load, or provider disposal during load.

Impact:

This is user-visible when Dashboard and Wizard mount close together, when refresh/reload triggers overlap, or when slow DB/backup/migration/load operations cause request completion order to differ from request start order.

Recommendation:

Introduce one explicit controller-level load contract:

- `requestGeneration` / sequence integer.
- Apply results/errors/loading only if the generation is still current.
- Make `reset()` invalidate current generation.
- Add `_disposed` guard around `_notify()`.
- Decide between single-flight reuse and latest-wins. For resource refresh UI, latest-wins is safer; for identical initial loads, single-flight may reduce DB churn but still needs generation ownership for reset/dispose.

Acceptance tests for future fix:

- Two loads A/B with B completing first; A must not overwrite B.
- A error completing after B success must not reintroduce stale error.
- A success completing after B error must not clear B error.
- `loading` remains true until the current generation completes.
- `reset()` during in-flight load prevents later state repopulation.
- Dispose during in-flight load does not notify.

## 6. ISSUE-02 CharacterCard parser split

Status: PARTIALLY_RESOLVED.

Direct cause:

There are two active parser paths:

- Tolerant path: `CharacterCard.fromJson()` uses `_asText`, `_asTextList`, `_asMap`.
- Strict import path: `parseFromJson()` and `parseFromPngBytes()` call `_cardFromJson()`, which still uses `as Map<String,dynamic>?`, `as String?`, and `.cast<String>()`.

Root cause:

The model owns both canonical domain parsing and external import parsing, but those paths have diverged. The tolerant parser was added for persisted/legacy reads without retiring the older JSON/PNG import parser. That means the parser contract depends on entry point, not on trust boundary.

Relevant code:

- `lib/models/character_card.dart:139-212`: tolerant `fromJson()`.
- `lib/models/character_card.dart:216-218`: `fromJsonString()` passes `jsonDecode(jsonString)` directly to typed `fromJson`; top-level non-map can still throw before tolerant parsing starts.
- `lib/models/character_card.dart:330-353`: `parseFromPngBytes()` decodes PNG text and calls `_cardFromJson()`.
- `lib/models/character_card.dart:356-365`: `parseFromJson()` decodes JSON and calls `_cardFromJson()`.
- `lib/models/character_card.dart:367-413`: strict `_cardFromJson()`.
- `lib/models/character_card_entry.dart:101-134`: persisted DB row parsing catches decode/build failures and uses tolerant `CharacterCard.fromJson(raw)`.
- `lib/managers/character_manager.dart:25`: JSON import uses `CharacterCard.parseFromJson`.

Failure chain:

```text
External SillyTavern / PNG / JSON card contains type variant
→ JSON/PNG import uses parseFromJson/parseFromPngBytes
→ _cardFromJson casts fields strictly
→ TypeError escapes to parse catch or is swallowed into null/empty import
→ same logical data would be readable if it had gone through CharacterCardEntry/fromJson
```

Type mutation behavior:

| Field/value variant | Tolerant persisted path | JSON/PNG import path |
| --- | --- | --- |
| String in text field | accepted | accepted |
| num in text field | converted to text | `TypeError` for direct `as String?` fields; `_readString` fields call `toString()` |
| bool in text field | converted to text | `TypeError` for direct `as String?` fields |
| List in text field | fallback empty for `_asText`; `_readString` uses `toString()` | `TypeError` for direct `as String?` fields |
| Map in text field | fallback empty for `_asText`; `_readString` uses `toString()` | `TypeError` for direct `as String?` fields |
| null / missing | default empty or default version | default empty or default version |
| wrong `data` wrapper | falls back to flat root | `json['data'] as Map<String,dynamic>?` can throw if non-map |
| wrong `world_profile` | `_asMap` returns empty | ignored entirely by `_cardFromJson()` |
| `tags` string | `_asTextList` returns empty | `.cast<String>()` path skipped if not list; direct `as List?` throws for non-list |
| `tags` list of numbers | converted to string list | `.cast<String>()` throws |
| `alternate_greetings` list of numbers | converted to string list | `.cast<String>()` throws |
| `custom_attributes` malformed | ignores non-map items | `_cardFromJson()` ignores custom attributes entirely |

Confirmed statement:

Yes, the current code can have "database read works, but the same logical card through JSON/PNG import fails or imports incompletely." The persisted path uses `CharacterCardEntry.fromRow()` plus tolerant `fromJson()`, while JSON/PNG import uses `_cardFromJson()`.

Recommended unified parser architecture:

- Keep one canonical tolerant external parser, e.g. `CharacterCardParser.parseExternal(Object?, source)`.
- Route `fromJson`, `fromJsonString`, `parseFromJson`, `parseFromPngBytes`, `CharacterCardEntry.fromRow`, and `CharacterManager` imports through it.
- Separate parser result from model: return `ParseResult<CharacterCard>` with diagnostics, source filename, source type, and recoverability.
- Preserve strict validation at save/import policy boundaries, not inside raw external parsing.
- Keep canonical storage adapter as the place that normalizes generated AI payloads into storage shape.

## 7. ISSUE-03 Persisted JSON trust boundaries

Status: CONFIRMED.

Direct cause:

Several JSON decode sites still immediately cast fields to Dart runtime types without considering legacy persisted variants such as `"8192"`, `8192.0`, `1`, `0`, `"true"`, `"false"`, `{}`, or `[]`.

Root cause:

The project does not have an explicit trust-boundary parsing policy. Some boundaries are now tolerant because a prior P0 forced that change, while other persisted settings/runtime rows and some external imports still use strict model constructors.

Boundary classification:

| Boundary | Contract |
| --- | --- |
| Trusted Internal Boundary | Strict is acceptable when values are produced by current code in the same transaction/schema and are not externally editable. |
| External Boundary | Tolerant decode plus validation diagnostics required. Applies to LLM JSON, PNG, SillyTavern JSON, import files, web/API responses. |
| Persisted Legacy Boundary | Backward-compatible decode required. Applies to SQLite rows, SharedPreferences settings, historical JSON blobs. |

Risk table:

| File | Function | Field | Source | Current parsing | Risk | Suggested contract | Priority |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `lib/models/model_context_capability.dart` | `ModelContextCapability.fromJson` | `context_window_tokens`, `max_output_tokens` | Persisted/user/model metadata | `as int?` | `"8192"` or `8192.0` throws | accept `int`, integral `num`, numeric string; clamp sane bounds | P1 |
| `lib/models/model_context_capability.dart` | `ModelContextCapability.fromJson` | `supports_prompt_caching`, `supports_structured_output`, `supports_tool_calling` | Persisted/user/model metadata | `as bool?` | `1`, `0`, `"true"` throw | accept bool/int/string variants with default false | P1 |
| `lib/models/completion_params.dart` | `CompletionParams.fromJson` | `max_tokens` | SharedPreferences/settings JSON | `as int?` | `"4096"` or `4096.0` throws and settings load falls back | tolerant positive int parse | P1 |
| `lib/models/completion_params.dart` | `CompletionParams.fromJson` | `enable_thinking` | SharedPreferences/settings JSON | `as bool?` | `"false"` or `0` throws and may reset to default true | tolerant bool parse with legacy false preserved | P1 |
| `lib/models/completion_params.dart` | `CompletionParams.fromJson` | `response_format` | Settings JSON | `as Map<String,dynamic>?` | decoded `_Map<dynamic,dynamic>` shape can throw | `value is Map ? Map<String,dynamic>.from(value)` | P2 |
| `lib/models/prompt_preset.dart` | `fromJson` | translation/note depth fields | Persisted preset JSON | `as int?`, enum index | string/double/out-of-range may throw | parse int and validate enum bounds | P2 |
| `lib/models/world_entry.dart` | `fromJson` / keyword parse | keyword lists, position/probability | DB/import JSON | `jsonDecode(...) as List`, `.cast<String>()`, enum index | malformed legacy rows can throw | tolerant list strings and enum clamp | P2 |
| `lib/models/game_state.dart` | `fromMap` | inventory JSON, numeric state fields | SQLite | numeric `as int?`, list casts | low risk because DB columns are typed, but imports may vary | tolerate numeric strings in import path | P3 |
| `lib/services/repositories/adventure_repository_impl.dart` | `getRuntimeEntities` | `entity_type`, `state_json` | SQLite runtime tables | `RuntimeEntityType.values.byName`, `jsonDecode(...) as Map` | one bad row can block Adventure load/context | row-level isolation with diagnostics | P1 |
| `lib/controllers/adventure_template_controller.dart` | template decode | `char_data_json`, `npc_data_json` | persisted template JSON | `jsonDecode(...) as Map` | malformed template can block template load/import | tolerate bad rows at controller/use-case boundary | P2 |
| `lib/controllers/scene_batch_import_controller.dart` | `relationshipContextOf` | `json_data` | resource library row | `jsonDecode(...) as Map` inside catch | current catch prevents crash; helper-only loss of context | acceptable with diagnostics | P3 |
| `lib/application/resource_library/import_use_cases.dart` | `SceneBatchImportUseCase.importSelected` | `result['items']` | LLM external JSON | `as List` | malformed result throws instead of diagnostic import error | external parser result with validation error | P1 |
| `lib/services/web_search_service.dart` | search decode | DuckDuckGo fields | external API | `as String` for some fields | external schema drift can throw | tolerant API DTO parse | P3 |

Failure chain:

```text
Legacy persisted JSON stores a valid semantic value in a different JSON type
→ model constructor performs strict Dart cast
→ TypeError escapes or is caught by a broad settings/controller catch
→ data resets to defaults, row disappears, or page load fails
→ user sees changed behavior despite data being recoverable
```

Recommendation:

Add small local parse helpers per boundary or a shared `JsonValueReader` with explicit methods:

- `stringScalar`, `intScalar`, `boolScalar`, `object`, `stringList`, `enumName`.
- Constructors at persisted/external boundaries should use these helpers.
- Strict constructors can remain for current in-memory DTOs if they are not exposed to persisted/external data.

## 8. ISSUE-04 SceneBatch identity matching

Status: CONFIRMED.

Direct cause:

`SceneBatchImportUseCase.importSelected()` keeps generated items only when generated `item['name'].trim()` exactly equals one of the selected display names.

Root cause:

SceneBatch uses display text as entity identity across independent LLM phases. The identify phase returns only strings. The generate phase receives those strings and is free to emit modified display names. There is no stable candidate ID, normalized name, source span, alias list, selected index, or canonical identity contract.

Relevant code:

- `SceneBatchImportUseCase.identify()` returns `Future<List<String>>`.
- `SceneBatchImportUseCase.importSelected()` passes `selectedNames.toList()` into generation.
- `SceneBatchImportUseCase.importSelected()` filters generated items with `selectedNames.contains(item['name']?.toString().trim())`.
- `AiGeneratorService.identifyCharacterNames()` asks for `facts` and `fuzzy` but returns only a deduped string list.
- `AiGeneratorService.generateSceneBatchCharacters()` prompt says only generate selected names, but returns plain items with name fields.

Failure chain:

```text
identify returns candidate "林月"
→ user selects "林月"
→ generate request asks for "林月"
→ LLM returns "林月·玄霜剑主" or "林月（少女时期）" or "林 月"
→ exact selectedNames.contains(...) fails
→ generated item is silently dropped
→ if all names drift, import fails with "未识别到可导入..."
```

Layer classification:

This is primarily an Identity contract and DTO design problem. Prompt contract can reduce drift but cannot be the root guarantee. Matching algorithm is the immediate failure point. LLM hallucination is an expected external-boundary behavior, not the root cause.

Duplicate names:

Duplicate display names cannot be represented safely today because the selected set is `Set<String>` and the DTO has no source span/index. Two different "林月" entities collapse into one selection.

Recommendation:

Redesign SceneBatch DTO:

```text
identify
→ candidates [{candidate_id, display_name, aliases, source_span, confidence}]
→ user selects candidate_id values
→ per-selected generation echoes candidate_id
→ validator matches by candidate_id, then checks name/alias consistency
→ save canonical item with source metadata
```

Minimum interim contract:

- Add normalized-name matching only as a fallback, not primary identity.
- Record dropped generated items with diagnostics so users and tests can see partial failure.

## 9. ISSUE-05 SceneBatch output scaling

Status: CONFIRMED.

Direct cause:

SceneBatch sends one request to generate all selected characters/NPCs and expects one JSON object with an `items` array under `maximumOutputTokens: 8192`.

Root cause:

Batch generation is modeled as one atomic LLM response and one batch save, but the product allows multiple long cards. It lacks chunking, per-character tasks, checkpointing, resumable state, partial success, and item-level validation/retry.

Relevant code:

- `SceneBatchImportUseCase.importSelected()` calls `gateway.generateSceneBatchCharacters()` once.
- `AiGeneratorService.generateSceneBatchCharacters()` creates one prompt containing all selected names, source, worldview, related characters, and detail instruction.
- The same method uses `maximumOutputTokens: 8192`.
- `SceneBatchImportUseCase.importSelected()` validates and saves after the single response; if parsing fails or all items are filtered, the whole import fails.

Failure chain:

```text
User selects N characters
→ one LLM request asks for all N profiles
→ required output grows roughly N × per-card target
→ 8192 output-token ceiling or context pressure truncates JSON
→ parser rejects entire response or exact-name filter drops items
→ no partial save/checkpoint/resume
→ user loses the whole batch
```

Scaling estimate:

| Selected count | Target per card | Approx Chinese chars | Risk |
| ---: | ---: | ---: | --- |
| 5 | 3000 | 15000 | Already unsuitable for one 8192-token JSON response once JSON overhead and instructions are included |
| 5 | 5000 | 25000 | High truncation risk |
| 20 | 3000 | 60000 | Not viable as one response |
| 20 | 5000 | 100000 | Requires multi-request architecture |

Additional risks:

- One malformed item can cause whole batch failure before save.
- No item-level retry for structured content failure.
- No checkpoint means app crash/cancel loses all progress.
- `relationship_links` matching also uses `targetName` exact display name against related characters.

Future architecture:

```text
identify
→ stable candidates
→ per-character generation tasks
→ limited concurrency, e.g. 2-3
→ per-item canonical validation
→ item-level retry bounded by retry policy
→ checkpoint progress
→ batch transaction for final save or resumable partial save policy
```

## 10. ISSUE-06 Thinking defaults

Status: PARTIALLY_RESOLVED.

Direct cause:

`CompletionParams` defaults to `enableThinking=true` and `reasoningEffort='high'`. Any call site constructing `CompletionParams` without explicitly setting `enableThinking` inherits thinking.

Root cause:

The model parameter type mixes product-mode policy with low-level request defaults. Recent resource generation paths introduced explicit `LlmGenerationMode.fast/deepThinking`, but not every helper path has been reclassified into a product mode.

Call-site inventory:

| Call site | Current params | Thinking explicit? | User path risk |
| --- | --- | --- | --- |
| `LLMService.sendMessageStream`, default arg | `params = const CompletionParams()` | No | Callers without params enable thinking |
| `LLMService.sendMessage`, default arg | `params = const CompletionParams()` | No | Same |
| `LLMService.testConnection` | `const CompletionParams(enableThinking:false, ...)` | Yes | Resolved |
| `AiGeneratorService._callText` | `CompletionParams(... enableThinking: generationMode == deepThinking)` | Yes | Resource AI generation resolved |
| `AiGeneratorService._callMessages` | same explicit mode check | Yes | Detailed resource generation resolved |
| `AiGeneratorService.generateSceneBatchCharacters` | via `_callText` with `generationMode` omitted | Yes, resolves to false | SceneBatch not thinking by default, but no mode choice exposed |
| `AiImportService` | `const CompletionParams(maxTokens:4096)` | No | Short import helper may use thinking |
| `SummaryService` | `const CompletionParams(temperature:.2,maxTokens:800)` | No | Summary may use thinking unnecessarily |
| `TranslationService` | `const CompletionParams(maxTokens:2048,temperature:.2)` | No | Translation may use thinking |
| `TtsService` | `const CompletionParams(maxTokens:1024,temperature:.2)` | No | TTS helper may use thinking |
| `AiGeneratorLlmGateway.rawCompletion` | `CompletionParams(temperature,maxTokens,responseFormat)` | No | JSON helper raw completion may use thinking |
| SettingsProvider default | `_completionParams = const CompletionParams()` | No | Chat default remains reasoning-heavy by product choice |
| ChatEngine main adventure | uses user settings from SettingsProvider | User-controlled | Product semantic, not automatically a bug |
| ChatEngine option repair | `enableThinking:false` | Yes | Resolved |
| Response length supplement | copies then disables thinking | Yes | Resolved |

Failure chain:

```text
Helper code constructs CompletionParams without enableThinking
→ low-level default enables thinking/high reasoning
→ DeepSeek/non-DeepSeek request includes thinking/reasoning_effort where supported
→ short helper request consumes extra latency/output budget or alters sampling behavior
→ user sees slow summary/translation/import/test-like operations
```

Judgment:

Actual resource import user paths are mostly resolved by explicit `LlmGenerationMode`. Chat/adventure default thinking may be intentional product behavior. The remaining risk is not "default true is always wrong"; it is that low-level defaults silently define policy for helper paths whose product semantics are short, deterministic, or classification-like.

Recommendation:

- Define named presets by task: `creativeNarrative`, `deepReasoning`, `shortUtility`, `structuredJson`.
- Require helper/utility calls to choose a preset explicitly.
- Keep current chat setting default only if product wants adventure chat to be reasoning-heavy.
- Add tests that inventory call sites or assert known helper paths disable thinking.

## 11. Runtime State Versioning Review

Status: mostly sound, with NEW P1 `RUNTIME-01`.

Verified sound areas:

- Original CharacterCard / Worldview baseline remains immutable by value through `AdventureAssembler`; tests cover later mutation of source maps not affecting frozen config.
- Runtime state stores overlays/deltas: `RuntimeEntityState.overlay`, `adventure_runtime_entities.state_json`, `adventure_state_changes`.
- Branch isolation is tested: runtime overlays fork and remain branch-local.
- Revision is monotonic per branch: `_applyRuntimeDraft()` increments `currentRevision + 1`.
- `expectedRevision` prevents stale commit when non-negative; mismatch throws `RuntimeHeadConflict`.
- Runtime commit is applied in the same repository transaction as scene dialogue commit through `commitSceneDialogue()`.
- Duplicate request id is covered by unique `(adventure_id, branch_id, request_id)` and tests assert idempotent runtime commit behavior.
- Runtime entities enter next-round context: `ChatEngine` passes `runtimeRevision`, `_runtimeEntities`, and archive facts into prompt builder; `narrative_runtime_test` verifies bounded runtime HEAD placement.
- Adventure deletion cascades at schema level for runtime tables that reference `adventures`.

Open / newly discovered problem:

`AdventureRepositoryImpl.getRuntimeEntities()` is a persisted legacy boundary but reads rows strictly:

```text
RuntimeEntityType.values.byName(row['entity_type'] as String)
jsonDecode(row['state_json'] as String) as Map
```

Failure chain:

```text
One runtime entity row has unknown entity_type or malformed/non-object state_json
→ getRuntimeEntities() throws
→ AdventureProvider/ChatEngine cannot load runtime overlay
→ next prompt/context load can fail for the whole Adventure
→ a single bad runtime row can drag down an otherwise valid Adventure
```

This violates the row-isolation pattern already applied to character card resources. It does not prove runtime writes are unsafe; it proves persisted runtime reads are not hardened against corruption or legacy schema drift.

Additional runtime observations:

- Non-character runtime changes require pre-seeded entities, which prevents LLM narrative output from inventing arbitrary faction/location/world overlays.
- Character changes require known character IDs from config when no runtime entity exists.
- `deleteBranch()` deletes runtime heads/entities for the branch but intentionally preserves archive commits because descendants may reference them. This is documented in code.
- `deleteAdventure()` does not manually delete runtime tables, relying on `PRAGMA foreign_keys = ON` and `ON DELETE CASCADE`. This is acceptable if all DB connections keep FK enabled; `DatabaseService` config does enable it.

Recommended tests:

- Insert malformed runtime entity JSON and verify Adventure load skips/diagnoses that row.
- Insert unknown `entity_type` and verify skip/diagnostic.
- Verify `commitSceneDialogue()` with duplicate request id is idempotent for both messages and runtime entities.
- Verify stale `expectedRevision` throws and does not insert partial scene/runtime rows.
- Verify delete Adventure removes runtime rows under FK constraints.

## 12. Actions / CI Review

Status: NEW P1 governance issue.

Release workflow:

- File: `.github/workflows/release-arm64.yml`.
- Trigger: tag push `v*` and manual dispatch.
- Steps: checkout, set up Flutter, `flutter pub get`, parse pubspec version, `flutter build apk --release --target-platform android-arm64`, verify native libraries only under `lib/arm64-v8a/`, upload artifact, create GitHub Release with APK and SHA256.
- Latest run `34452691368` succeeded for `v1.1.3` at commit `7cca4d17173ce8f94453b2b57f492908215ecdfe`.

Confirmed properties:

- Release tag points to current main HEAD.
- Pubspec version is `1.1.3+6`; tag is `v1.1.3`.
- APK and `.sha256` assets were uploaded.
- ARM64-only verification exists in workflow.
- Concurrency is by `release-${{ github.ref_name }}`, so two runs for the same tag serialize without canceling in-progress release.

Node warning:

- Latest run produced a non-blocking annotation: `actions/checkout@v4` and `actions/upload-artifact@v4` target Node.js 20 and are forced to Node.js 24.
- Current status: not blocking.
- Forward risk: GitHub Actions ecosystem has newer Node 24 action majors. Public GitHub action release pages show `actions/checkout` has Node 24 major releases beyond v4, and `actions/upload-artifact` has Node 24 major releases beyond v4. Upgrade should be planned, but not done in this audit.

Missing release gate:

The release workflow does not run:

```text
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Therefore:

```text
Release build success != regression tests success
```

GitHub branch governance:

- GitHub branch API reports `protected:false`.
- Required status checks enforcement is `off`, with empty contexts/checks.
- Repository has only `.github/workflows/release-arm64.yml`; no separate PR/main CI workflow was found.

Recommendation:

- Add a separate CI workflow on push/PR to `main` that runs format check, analyze, targeted P0 tests, and full tests.
- Make that workflow a required status check on `main`.
- Keep release workflow focused on artifact build/publish, but optionally require CI-passed tag source.
- Upgrade actions after checking runner compatibility, especially if self-hosted runners are ever introduced.

## 13. Test Quality Review

| Test area | Quality | Evidence | Gap |
| --- | --- | --- | --- |
| Wizard submit boundary | REAL REGRESSION | Failing save/load/assembly/start dependencies through widget path; retry asserted | Does not use real DB in those boundary cases by design |
| Resource load isolation | REAL REGRESSION | Poisoned DB row plus per-type failure tests | No async stale-load race |
| Structured truncation | REAL REGRESSION | LLMService and stage tests assert incomplete output rejected | Good |
| Stage schema scalar | REAL REGRESSION | Normalizer and validator tested together | Good |
| Stage2B nested world_profile | REAL REGRESSION | Nested-to-flat and root precedence tested | Good |
| Retry semantics | REAL REGRESSION | Transport/content/cancel/429/budget boundaries asserted | Good |
| Worldview association | REAL REGRESSION | Cross-world remains selectable | Good |
| Undefined relation | REAL REGRESSION | Assembler keeps relation empty | Good |
| CharacterCard parser | PARTIAL | `fromJson` roundtrip and persisted row tolerance exist | No JSON/PNG import mutation tests against `_cardFromJson` |
| Persisted JSON casting | PARTIAL | Some roundtrips exist for model capability/completion params | No legacy string/double/int/bool variant tests |
| SceneBatch identity | FALSE CONFIDENCE / MISSING | No test found for generated name drift, aliases, duplicate names | Needs stable ID contract tests |
| SceneBatch scaling | MISSING | No chunk/checkpoint/partial-success tests found | Needs per-item orchestration tests |
| Thinking policy | PARTIAL | Resource generation mode tests cover fast/deepThinking; chat supplement disables thinking | No inventory test for helper paths |
| Runtime versioning | REAL REGRESSION with gap | Branch isolation, idempotence, immutable baseline, context injection tested | No malformed runtime row isolation test |
| CI release workflow | HELPER-ONLY | Release builds APK and validates ABI | Does not run regression tests |

## 14. Newly Discovered Problems

RUNTIME-01: malformed runtime entity row can block runtime context load.

Direct cause:

`getRuntimeEntities()` performs strict enum and JSON map casts for persisted runtime rows.

Root cause:

Runtime tables were designed as trusted internal state, but they are persisted and can be affected by legacy migrations, interrupted writes, manual recovery, or storage corruption. The read boundary should isolate bad rows like resource library parsing does.

Impact:

One row can prevent Adventure runtime overlay loading and potentially block ChatEngine from constructing the next context.

CI-01: release workflow is not a regression gate.

Direct cause:

The only workflow builds APK and creates a release; it does not run format/analyze/test.

Root cause:

Release automation and CI quality gate are conflated, and `main` has no required checks.

Impact:

A tag can publish a build from code that was not independently regression-tested on GitHub. Local test evidence may be good, but it is not enforced.

## 15. Root Cause Dependency Graph

```text
No explicit boundary contracts
├─ CharacterCard parser split
│  ├─ persisted path tolerant
│  └─ JSON/PNG import path strict
├─ Persisted JSON cast risks
│  ├─ model capability settings
│  ├─ completion params
│  └─ runtime entity rows
└─ SceneBatch LLM DTO risks
   ├─ display name used as identity
   └─ one giant JSON used as batch transport

No async ownership contract
└─ AdventureSetupController stale load
   ├─ old rows can overwrite newer rows
   ├─ old errors can overwrite newer errors
   └─ old loading=false can mask active load

Policy/default coupling
└─ CompletionParams default thinking
   ├─ resource generation now mostly explicit
   └─ helper paths still inherit reasoning defaults

No enforced CI gate
└─ Release success can exist without remote regression tests
```

## 16. Recommended Remediation Order

1. ISSUE-01 AdventureSetup stale load.
   Reason: shared UI state can visibly regress even when all P0 load isolation tests pass.

2. ISSUE-02 + ISSUE-03 parser/trust boundary cleanup.
   Reason: unified parsing prevents the same class of TypeError from reappearing across imports, settings, and persisted rows.

3. RUNTIME-01 malformed runtime row isolation.
   Reason: Runtime state is now in the critical chat context path and should follow resource row-isolation precedent.

4. ISSUE-04 SceneBatch identity contract.
   Reason: exact display-name matching causes silent data loss and must be fixed before scaling.

5. ISSUE-05 SceneBatch per-item/chunked architecture.
   Reason: large output failure becomes easier to solve once identity and DTO contracts are stable.

6. ISSUE-06 thinking policy inventory.
   Reason: mostly a latency/cost/regression-risk cleanup after correctness risks.

7. CI-01 GitHub CI gate.
   Reason: should happen soon, but it should validate the above fixes once they land.

## 17. Agent Handoff Plan

Agent A: AdventureSetup concurrency.

- Scope: `AdventureSetupController`, Riverpod provider lifecycle, Dashboard/Wizard load callers.
- Files: `lib/controllers/adventure_setup_controller.dart`, `lib/providers/riverpod_providers.dart`, Dashboard widgets, Wizard load call sites, tests under `test/unit/p0_adventure_resource_loading_test.dart`.
- Root cause: no async ownership/latest-wins contract in shared controller.
- Must preserve: per-type resource failure isolation, damaged-row reporting, current Wizard submit recovery.
- Must not modify: UI theme/visual style, DB schema, prompt text.
- Tests: controlled delayed use case for A/B stale loads, stale errors, reset, dispose, loading flag.
- Acceptance: only current generation can mutate rows/errors/loading and notify.
- Suggested commit boundary: `fix(setup): ignore stale resource load completions`.
- Dependencies: none.

Agent B: CharacterCard + persisted parsing.

- Scope: CharacterCard import parsers and persisted JSON constructors.
- Files: `lib/models/character_card.dart`, `lib/models/character_card_entry.dart`, `lib/services/character_card_storage_adapter.dart`, `lib/models/model_context_capability.dart`, `lib/models/completion_params.dart`, related tests.
- Root cause: parser contracts depend on entry point and persisted constructors use strict casts.
- Must preserve: tolerant persisted reads, canonical generated storage, existing roundtrips.
- Must not modify: DB schema, unrelated resource import flows, Prompt content.
- Tests: JSON/PNG import with num/bool/list/map/null/malformed wrappers; model capability and completion params legacy variants.
- Acceptance: external/persisted boundaries do not throw on recoverable legacy variants; invalid data produces diagnostics/defaults.
- Suggested commit boundaries: one for CharacterCard parser unification, one for persisted settings/model capability readers.
- Dependencies: none.

Agent C: SceneBatch identity and scaling.

- Scope: identify DTO, selected identity, generation DTO, batch orchestration.
- Files: `lib/application/resource_library/import_use_cases.dart`, `lib/controllers/scene_batch_import_controller.dart`, `lib/application/llm/llm_gateway.dart`, `lib/application/llm/ai_generator_llm_gateway.dart`, `lib/services/ai_generator_service.dart`, SceneBatch page/tests.
- Root cause: display names are used as primary keys and all selected cards are generated in one response.
- Must preserve: existing import validation and library save semantics.
- Must not modify: character/world parser beyond using public contracts, DB schema unless explicitly approved.
- Tests: name drift, alias, Chinese spacing, duplicate names, partial item failure, truncation/chunk retry.
- Acceptance: selected candidate IDs survive identify→generate→save; one item failure does not destroy successful items under chosen policy.
- Suggested commit boundaries: identity DTO first, then per-item/chunked generation.
- Dependencies: parser contracts from Agent B help but are not strictly required for identity DTO.

Agent D: Thinking policy.

- Scope: task-level `CompletionParams` presets and call-site inventory.
- Files: `lib/models/completion_params.dart`, `lib/services/*`, `lib/engines/chat_engine*`, `lib/application/llm/ai_generator_llm_gateway.dart`, settings tests.
- Root cause: low-level constructor default doubles as product policy.
- Must preserve: user-selected adventure/chat thinking behavior and explicit fast/deepThinking resource generation.
- Must not modify: prompts to hide token/cost issues.
- Tests: helper calls disable thinking; chat/adventure paths keep intended behavior; resource generation mode tests remain green.
- Acceptance: every non-chat helper path chooses an explicit thinking policy.
- Suggested commit boundary: `fix(llm): make utility requests choose non-thinking params`.
- Dependencies: none.

Agent E: CI / Actions.

- Scope: GitHub workflows and branch protection recommendation/implementation if authorized later.
- Files: `.github/workflows/*`.
- Root cause: release workflow is artifact publishing, not CI.
- Must preserve: ARM64-only release assets, SHA256 generation, tag-triggered release.
- Must not modify: production Dart code.
- Tests: workflow syntax, dry-run reasoning, first CI run on PR/push.
- Acceptance: CI runs format check, analyze, targeted P0 tests, full tests; branch protection requires it.
- Suggested commit boundary: `ci: add main regression gate`.
- Dependencies: should be coordinated after high-priority fixes for stable checks.

Agent F: Runtime hardening.

- Scope: runtime row read isolation and transaction/idempotency tests.
- Files: `lib/services/repositories/adventure_repository_impl.dart`, `lib/models/adventure_runtime_state.dart`, `test/unit/database_and_repositories_test.dart`, `test/unit/narrative_runtime_test.dart`.
- Root cause: persisted runtime rows are trusted too strongly at read time.
- Must preserve: immutable baseline, delta overlay model, branch isolation, revision conflict behavior, scene/runtime same transaction.
- Must not modify: DB schema or runtime data model unless a later design explicitly approves it.
- Tests: malformed `state_json`, unknown `entity_type`, stale expectedRevision rollback, delete cascade, duplicate request id idempotency.
- Acceptance: bad runtime row is skipped/diagnosed without blocking Adventure context.
- Suggested commit boundary: `fix(runtime): isolate malformed runtime entity rows`.
- Dependencies: JSON reader utilities from Agent B could be reused.

## 18. Acceptance Criteria For Future Agents

General:

- Start from latest `origin/main`.
- Preserve user work and avoid broad formatting.
- Add tests before or with fixes.
- Do not weaken existing P0 tests.
- Do not hide errors by broad silent catches without diagnostics.
- Keep commits scoped and atomic.

ISSUE-01:

- Concurrent load tests prove latest-wins.
- Stale errors and stale loading flags cannot overwrite current state.
- Reset/dispose invalidate pending loads.

ISSUE-02 / ISSUE-03:

- One canonical external CharacterCard parser is used by JSON, PNG, persisted rows, and fromJsonString.
- Legacy numeric/bool/string variants for model capability and completion params do not throw.
- Trusted internal strict parsing remains documented and limited.

ISSUE-04 / ISSUE-05:

- SceneBatch no longer depends on exact generated display-name equality.
- Duplicate display names remain distinct through stable IDs.
- Large batches are chunked or per-item with bounded retry and partial-success policy.

ISSUE-06:

- Helper/utility LLM paths use explicit non-thinking or task-specific params.
- Chat/adventure/user-selected thinking behavior remains unchanged unless product explicitly changes it.

Runtime:

- Runtime commits remain delta-only.
- Expected revision conflict rolls back scene/runtime transaction.
- Malformed runtime rows do not block Adventure loading.
- Delete cascade is tested.

CI:

- GitHub CI runs format/analyze/tests independently of release build.
- Release workflow still publishes ARM64 APK and SHA256.
- Branch protection requires CI before merging to `main`.
