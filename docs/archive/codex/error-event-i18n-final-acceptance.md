# Error/Event i18n Final Acceptance

## Baseline

- Start HEAD for this recovery: `994b57c63b3e3318b9564eff61e4656ee0e2deff`
- `origin/main`: `14776e1a273f9c42667a6e96478a9674d03dd748`
- Worktree contained pre-existing uncommitted widget/test localization changes; they were preserved.
- Final HEAD: `451f4ad` (`refactor(i18n): finish typed resource studio failures`).

## Initial verified debt

The current scan covered 394 Dart production files. Broad keyword scans reported 1,726 raw-oriented hits and 7,917 hardcoded Chinese literal hits; these include protocol, diagnostics, dynamic content, generated localization, and legacy compatibility and are not equivalent to UI debt. The audit confirmed six debt families: import, Resource Studio, API/provider/LLM, Adventure readiness, Skill/Inventory/Combat/ChatEngine events, and TTS. The detailed producer and sink inventory remains in `docs/codex/error-event-localization-migration-audit.md`.

## Architecture implemented

- Added one shared `AppErrorCode` / `AppDomainError` contract.
- Added one shared `AppEventCode` / `AppEvent` contract and versioned in-band codec.
- Added Presentation-only error and event localizers.
- Added six-locale ARB keys and regenerated gen-l10n output.
- Added import and adventure-readiness error codes, with synchronized six-locale copy.
- API conversion now keeps raw transport detail as diagnostics and exposes stable domain codes.
- Adventure AI, scene batch import, provider connection settings, Resource Studio user-message adapter, and read-aloud controller no longer forward raw exception text as their primary user copy.

## Module results

- Import: AI import now emits typed invalid-input/parse/unsupported errors; scene and chat import pages map failures through the presentation localizer.
- Resource Studio: production panels now render typed `AppDomainError` values through the localization mapper; capacity summaries and streaming runtime events carry stable classifications while legacy diagnostics remain compatibility fields. The deprecated adapter is no longer the authority for new typed failures.
- API / Provider / LLM: `ApiError.toDomainError` and provider presentation mapping are in place. ChatEngine error history uses a typed error marker and event history uses the versioned envelope.
- Adventure readiness: readiness results now expose typed issue codes/parameters and the wizard renders them through the typed mapper; fallback gate failures carry typed errors while legacy message fields remain for compatibility.
- Runtime events: CombatManager logs and ChatEngine rest/level/combat messages now use the versioned event envelope; Skill/Inventory results now expose typed result codes while legacy message getters remain for compatibility. Prompt history projects envelopes to locale-neutral protocol text; export/import and full Presentation mapping still require migration.
- TTS: controller no longer stores engine/plugin raw detail in UI error state; chat/settings capability surfaces now map stable reason codes through localized copy. The legacy capability message field remains deprecated for compatibility.

## Localization

Six ARB files were updated with synchronized error/event keys and generated output. `flutter gen-l10n` succeeded and `flutter analyze` reports no issues.

## Regression

- `flutter gen-l10n`: passed.
- `flutter analyze`: passed.
- `flutter test test/unit/app_event_codec_test.dart`: passed (2 tests).
- `flutter test test/application/resources/streaming_section_regeneration_executor_test.dart`: passed (11 tests).
- `flutter test test/unit/read_aloud_controller_test.dart`: passed (42 tests) after migrating assertions to typed codes.
- Adventure readiness and post-removal inventory/combat targeted tests passed.
- Readiness typed issue mapping is covered by the existing readiness/widget flows.
- `git diff --check`: passed.
- ARB parity check: 1489 message keys in each of `en`, `ja`, `ko`, `zh`, `zh_Hans`, and `zh_Hant`; placeholder parity verified for parameterized error keys.
- Targeted tests: event codec (2), section regeneration (11), read-aloud controller (42), adventure readiness, and character-card capacity validation passed. A requested `test/unit/api_error_test.dart` path does not exist.
- Full test suite: ran to completion (`2178` passed, `1` skipped, `13` failures). Failures are concentrated in legacy widget expectations for raw exception text and unrelated pre-existing/user-modified flows; they require follow-up migration of those expectations and sinks.

## Compatibility

No database schema/version, Resource Creation Authority, generation cursor, streaming, retry, lease, compression, or TTS backend behavior was changed. Existing Message persistence remains compatible; event and error envelopes are additive and legacy getters remain for older callers.

## Residual scan

The follow-up scan still finds legacy diagnostic fields and compatibility text in persistence rows, TTS capability, and older result objects. New presentation paths use typed errors; old persisted `error_message`/`validation_message` rows and compatibility getters remain legacy diagnostics. Remaining `toString()`/`.message` hits are classified as diagnostics, protocol/value conversion, dynamic user/model content, or legacy compatibility. Full regression still exposes older tests that assert raw technical text, so the migration is not yet complete.

## Findings

### BLOCKER

- The complete end-to-end migration is not complete because Skill/Inventory result objects and several legacy Resource Studio/Adventure compatibility paths still carry display strings.
- Full regression acceptance is not green; existing tests still assert removed raw technical copy in some widget paths.

### MAJOR

- TTS capability still exposes a deprecated legacy `message` field.
- Existing read-aloud tests need to assert typed/generic behavior instead of raw engine diagnostics.

### MINOR / INFO

- `ApiError.message` and `ReadAloudEngineException.message` remain compatibility diagnostics; they must stay out of Presentation paths.

## Final Verdict

**FAILED** — the shared contracts and several high-risk sinks are migrated, but the required complete six-family Error/Event migration and full regression acceptance are not yet proven.
