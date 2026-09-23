# Error/Event Localization Migration Audit

## Git and worktree baseline

- Repository: `yangrunzhi345-blip/LT`, branch `main`.
- Audit baseline: `be9185ff1cd0e50d3c255166dedbce0c5f5093c2`.
- `origin/main`: `dfd41da3a4035ff483227870e0380c59b52dc848`; local main is one
  documentation commit ahead, with no remote divergence.
- The worktree contains pre-existing uncommitted i18n UI/test changes in
  `lib/core/widgets/`, `lib/models/completion_params.dart`,
  `lib/widgets/`, `test/`, and `test/helpers/localization_test_helper.dart`.
  They are not part of this migration and must be preserved.
- Current ARB set: `en`, `ja`, `ko`, `zh`, `zh_Hans`, `zh_Hant` (six files).
- Current SQLite schema version is 44. This migration must not change it.

## Audit method and classification

Scanned all 396 Dart files in `lib/` for exception/error/failure/result/message/
event declarations, `SnackBar`/feedback call sites, `toString()`, throws, catches,
and message access. Then followed the known D-class call paths into Presentation.
The raw scanner output is intentionally not treated as a debt count: `catch`,
`Exception`, `Message`, and `Event` also occur in internal protocols, logs,
user-authored content, and generated narrative. Each item below is a verified
cross-layer user-visible path or a producer that feeds such a path.

- **A: new blockers during implementation** — any newly introduced raw text,
  exception message, or domain-generated UI event caption reaching Presentation.
- **B: existing D debt** — the six families below; this audit is the source list
  for the dedicated migration.
- **C: dynamic content** — user input and model/resource names or prose. Keep as
  content; do not treat it as a localization key or translate it automatically.
- **Internal/protocol** — stable enum/JSON/API/database values, prompts, and
  diagnostics not rendered to users. Preserve behavior and avoid false-positive
  replacement.

## Verified D-class inventory

| Family | Producers / contracts | Presentation or persistence leak | Required migration |
| --- | --- | --- | --- |
| Import | `lib/application/resource_library/import_use_cases.dart` (`ImportValidationException`, message-bearing throws, dynamic `$error`); `lib/controllers/resource_library_import_controller.dart`; `resource_card_import_controller.dart`; `scene_batch_import_controller.dart` | Controllers expose `errorMessage`; `lib/screens/resource_library/scene_batch_import_page.dart` stores and renders `error.toString()` | Replace message exception with stable import error codes + typed parameters; controllers keep typed errors; Presentation maps with `AppLocalizations`; unknown failures show safe localized generic text, diagnostics remain non-UI. |
| Resource Studio | `lib/features/resource_studio/presentation/resource_studio_user_message.dart`; `lib/features/resource_studio/application/use_cases/streaming_section_regeneration_executor.dart`; Studio controllers/use cases; related contracts in `lib/application/resources/` (notably resource creation/capacity, compression, readiness, autosave, section-control outcomes) | `errorMessage`, `validationMessage`, `outcome.message`, `Exception.message`, and persisted existing `error_message`/`validation_message` values are interpreted as display strings in Studio; some use cases throw Chinese `StateError`/typed exceptions | Give Studio failures stable code/parameters, preserve user intent/results, and localize at Presentation. Keep generation ordering, cursor, retries, commit authority, storage schema, and user resource text unchanged. Legacy free-form stored values must render safely without exposing technical strings. |
| API / Provider / LLM | `lib/services/api_error.dart` (`message`, `userMessage`, `fromException`); `lib/services/llm_service.dart`; `lib/controllers/adventure_ai_controller.dart` | `lib/features/settings/presentation/widgets/provider_config_section.dart` displays `ApiError.message`; Adventure AI controller returns raw API/exception text; `lib/engines/chat_engine.dart` persists `ApiError.userMessage` or raw `toString()` inside error messages | Stable `ApiErrorCode` + retry/status parameters and separate `debugMessage`; no service-owned user copy. Map at presentation. Chat error records may keep machine `errorType`, but visible error text must be localized at render time; preserve retry and error categories. |
| Adventure readiness / validation | `lib/application/adventure/adventure_readiness_gate.dart`; assembly/readiness records and `lib/application/resources/assembly_readiness_coordinator.dart` | `AdventureAssetReadiness.message`, `validationMessage`, `AdventureReadinessGateException.message`; exact-Chinese compatibility mapper at `lib/features/adventure/presentation/wizard/adventure_readiness_message_localization.dart`; raw exception shown by `assembly_preview_page.dart` / `adventure_wizard_screen.dart` | Return typed validation issues (`code` + parameters such as resource type/name/id); keep dynamic resource names as arguments. Presentation maps errors and issues. Eliminate language-dependent equality matching and never display raw failure detail. |
| Skill / Inventory / Combat / ChatEngine events | `lib/managers/skill_manager.dart` result `message`; `inventory_manager.dart` result `message`; `combat_manager.dart` `CombatTurnResult.description` and `CombatState.combatLog`; ChatEngine rest, level-up, combat, API error, and some state-feedback `Message.content` producers | Results and manager log text are presented directly; ChatEngine stores rendered Chinese event/error prose in message `content`, which is also durable chat history | Introduce `AppEventCode` and structured payloads for accepted business events and failures. Presentation maps event codes. Preserve user/model/item names as payload content. Keep durable message schema unchanged; define a backward-compatible event envelope/renderer and prompt-history compatibility before migrating ChatEngine. |
| Linux TTS diagnostics | `lib/services/read_aloud/linux_tts_engine.dart`; shared `ReadAloudEngineException`; `ReadAloudCapability.message` in `lib/domain/read_aloud/read_aloud_contracts.dart`; `lib/services/read_aloud/read_aloud_controller.dart` | Engine/capability/controller carry localized diagnostic strings; settings and chat widgets display capability/error message | Use stable TTS diagnostic/error code plus optional redacted debug detail; Presentation maps all visible states. Preserve platform detection, subprocess calls, capability flags, and playback behavior. |

## Additional verified leak sites within those six families

- Import error detail can be created by `$error` and `FormatException.message`,
  not only explicit `ImportValidationException` messages.
- Resource Studio contains older free-form error contracts throughout
  `lib/application/resources/` and `lib/features/resource_studio/**`; not every
  `message` field is UI text. Migrate only verified user-facing failure and
  validation paths; leave user content, prompts, protocol messages, and
  internal diagnostics as such.
- Provider and LLM errors have separate concerns: retry classification and
  diagnostic detail must remain available while the UI copy is localized.
- Adventure readiness has both stable top-level status and dynamic per-asset
  detail. Both require code/parameter results, not just translating the top
  heading.
- Existing manager and ChatEngine messages may already be persisted. No schema
  migration is allowed. Migration must read legacy localized messages as
  ordinary historical content while all newly generated event messages use a
  versioned, locale-neutral event envelope or equivalent typed representation.
- Linux TTS is only one producer; Flutter TTS shares the same capability/error
  contract and must not continue forwarding plugin text into UI when the common
  presentation path is migrated. Platform behavior must remain unchanged.

## Explicit scope boundaries

- No database schema or migration changes. Existing columns/JSON must be used
  compatibly; do not fabricate or rewrite historical user/resource/chat text.
- No Resource Creation Authority, generation protocol/cursor, retry/streaming,
  output parsing, or TTS backend behavior changes. Error metadata/display
  boundaries may change only when execution semantics remain identical.
- Do not modify AppLocale selection, gen_l10n configuration, delegates, or
  localization loading. New ARB entries and generated output are allowed and
  must be present in all six existing locale files.
- No BuildContext in Domain/Application/Service/Engine. Localization mapping is
  a Presentation-only operation over typed values and `AppLocalizations`.
- Pre-existing worktree changes are protected and must not be staged in this
  migration's commits.

## Implementation and acceptance sequence

1. Add shared typed `AppErrorCode`/`AppDomainError`, `AppEventCode`/`AppEvent`,
   and Presentation mappers. Keep parameters typed and stable; unknown codes
   render a safe localized generic message.
2. Migrate Import, then Resource Studio, API/Provider/LLM, Adventure readiness,
   ChatEngine and game managers, and finally TTS. Each module gets producer,
   Presentation, and regression tests before moving on.
3. Add all mapping ARB keys in the six existing locales; run `flutter gen-l10n`.
4. Re-scan all `lib/` and manually review all remaining message/error/event,
   `toString()`, `SnackBar`, throws, and catches. Every remaining hit receives
   A/B/C/internal classification; A must be zero and this six-family D list must
   be empty for the migrated call paths.
5. Run module tests and then `dart format --set-exit-if-changed .`,
   `flutter analyze`, `flutter test`, and `git diff --check`. Review event
   serialization/backward compatibility, retry behavior, old chat history,
   responsive error surfaces, and staged-file ownership.

## Known design decision before ChatEngine event migration

`Message` currently persists content through the existing messages table and
has only an error-type metadata field. Adding columns is prohibited. The
implementation must therefore select and test an in-band versioned event
envelope that can be rendered locally while legacy prose remains untouched.
Prompt construction must define how that envelope is represented to the LLM
without changing narrative generation/cursor semantics. Do not replace event
messages with localized strings inside Engine or persist UI-rendered text.
