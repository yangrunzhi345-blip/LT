# Error/Event i18n Final Acceptance

## Baseline

- Start HEAD: `14776e1a273f9c42667a6e96478a9674d03dd748`
- `origin/main`: `14776e1a273f9c42667a6e96478a9674d03dd748`
- Worktree contained pre-existing uncommitted widget/test localization changes; they were preserved.
- Final HEAD: recorded when this migration commit is created.

## Initial verified debt

The current scan covered 389 Dart production files. The audit confirmed six debt families: import, Resource Studio, API/provider/LLM, Adventure readiness, Skill/Inventory/Combat/ChatEngine events, and TTS. The detailed producer and sink inventory remains in `docs/codex/error-event-localization-migration-audit.md`.

## Architecture implemented

- Added one shared `AppErrorCode` / `AppDomainError` contract.
- Added one shared `AppEventCode` / `AppEvent` contract and versioned in-band codec.
- Added Presentation-only error and event localizers.
- Added six-locale ARB keys and regenerated gen-l10n output.
- API conversion now keeps raw transport detail as diagnostics and exposes stable domain codes.
- Adventure AI, scene batch import, provider connection settings, Resource Studio user-message adapter, and read-aloud controller no longer forward raw exception text as their primary user copy.

## Module results

- Import: scene batch import catch now maps unknown failures to generic localized copy. Dedicated import producer migration remains incomplete.
- Resource Studio: regex-based protocol-string cleaning was removed from the presentation adapter. Application/runtime error fields still require typed transient state migration.
- API / Provider / LLM: `ApiError.toDomainError` and provider presentation mapping are in place. ChatEngine persistence still requires event/error envelope migration.
- Adventure readiness: not yet fully migrated; application readiness records still contain display strings.
- Runtime events: contracts and codec are present, but Combat/Skill/Inventory/ChatEngine producers are not yet migrated.
- TTS: controller no longer stores engine/plugin raw detail in UI error state; capability contract and localized status mapping still need completion.

## Localization

Six ARB files were updated with synchronized error/event keys and generated output. `flutter gen-l10n` succeeded and `flutter analyze` reports no issues.

## Regression

- `flutter gen-l10n`: passed.
- `flutter analyze`: passed.
- `git diff --check`: passed.
- Targeted tests: localization tests passed; existing read-aloud tests currently fail because they assert the removed raw engine message. A requested `test/unit/api_error_test.dart` path does not exist.
- Full test suite: not run because the targeted contract tests already expose expected-test updates that must be completed before a meaningful full-suite result.

## Compatibility

No database schema/version, Resource Creation Authority, generation cursor, streaming, retry, lease, compression, or TTS backend behavior was changed. Existing Message persistence and legacy history remain unchanged. Event codec is additive and currently not wired into ChatEngine producers.

## Findings

### BLOCKER

- The complete end-to-end migration is not complete because ChatEngine and manager events still persist/render locale-specific prose.
- Adventure readiness and Resource Studio application contracts still carry display strings.

### MAJOR

- TTS capability still exposes a legacy `message` field and settings presentation has additional capability-message paths.
- Existing read-aloud tests need to assert typed/generic behavior instead of raw engine diagnostics.

### MINOR / INFO

- `ApiError.message` and `ReadAloudEngineException.message` remain compatibility diagnostics; they must stay out of Presentation paths.

## Final Verdict

**FAILED** — the shared contracts and several high-risk sinks are migrated, but the required complete six-family Error/Event migration and full regression acceptance are not yet proven.
