# LT — Flutter UI Automation Infrastructure

Status: ACCEPTED (host scope)
Execution mode: Integrated Single-Agent Full-Cycle
Device testing: `NOT EXECUTED — DEVICE UNAVAILABLE BY DESIGN`

No device was connected, no USB authorization was requested, no APK was installed, no
user-device data was touched and no Release was published. All work and verification ran on
the Arch Linux host.

## 1. BASELINE

- Working tree before this task: only the untracked device-validation docs from the previous
  task were present; no tracked file was modified.
- Branch `main`; `HEAD = 38769c9f74cd1fb17408a6ce87ba4f5447b1d739` (= origin/main).
- Flutter 3.44.8 / Dart 3.12.2; Android SDK 36.1.0.
- No `integration_test/` directory existed before this task.

## 2. FILES CHANGED

Production / config (tracked):

- `lib/features/resource_library/presentation/screens/resource_ai_create_page.dart` — numeric
  target-word input + two-way Slider sync + unified validation.
- `lib/features/adventure/presentation/session/widgets/session_input_bar.dart` — stable keys
  for the dialogue input and the send/stop controls.
- `lib/l10n/app_*.arb` (6 files) + `lib/l10n/generated/*` — one new string
  `resourceTargetCharactersInputInvalid`, regenerated with `flutter gen-l10n`.
- `android/app/build.gradle.kts` — debug-only `applicationIdSuffix = ".debug"` isolation.
- `pubspec.yaml` / `pubspec.lock` — added the official `integration_test` SDK dev-dependency.

Test infrastructure (new):

- `integration_test/support/lt_ui_keys.dart` — single-source key registry.
- `integration_test/support/lt_ui_driver.dart` — reusable key-based UI driver.
- `integration_test/support/scripted_llm_gateway.dart` — deterministic `LlmGateway` double.
- `integration_test/lt_core_flow_test.dart` — device entry point (Test A–D).
- `test/widget/resource_ai_create_budget_input_test.dart` — host budget tests (Test A/B/C).
- `test/widget/lt_ui_driver_host_test.dart` — host validation of the driver layer.

Test updates (layout adaptation only, no assertion weakened):

- `test/widget/resource_ai_create_studio_navigation_test.dart`,
  `test/widget/resource_library_production_test.dart`,
  `test/widget/resource_studio_test.dart` — added `ensureVisible` before tapping the submit
  button (the form is now taller by one input row).

## 3. IMPLEMENTATION

### Task A — numeric target-word input

- Added a full-width numeric `AppTextField` with the required stable key
  `ValueKey('ai_creation_target_words_input')` and an adjacent "apply" `IconButton` with key
  `ValueKey('ai_creation_target_words_confirm')` (`check` SVG icon, `applyAction` tooltip).
- **Two-way sync:** the Slider writes into the field; typing a valid in-range integer updates
  the Slider live. The field is never reformatted while focused (no caret jump); the
  controller is only rewritten on Slider/type change (when unfocused) or on explicit commit.
- **Unified confirm/blur validation** (`_commitTargetCharactersInput`): a parseable number is
  clamped to `[minimumGenerationTargetCharacters, nominalCharacters]` and snapped to the
  `generationTargetStepCharacters` (500) grid — the exact Slider domain; empty or non-numeric
  input is rejected with a localized error and the field reverts to the last valid value.
- The value flows into the real generation config: `_buildDraft()` already put
  `_targetCharacters` into `ResourceStudioCreationDraft.targetCharacters`, so a typed budget
  reaches the pipeline, not just the UI. Proven by the draft-capture tests.
- The existing Slider, min/max/step rules, capacity policy and business semantics are
  unchanged.

### Task B — stable automation keys

Audit result: the core surfaces already carried stable keys on the active code paths
(library, creation entry, AI create, Studio, assembly wizard, resource-selection pages).
Gaps found and filled:

- `session_input_bar.dart` had no keys — added `adventure-session-input`,
  `adventure-session-send-button`, `adventure-session-stop-button`.
- Added `integration_test/support/lt_ui_keys.dart` as the single declarative registry so the
  driver and the app are auditable against one list.

Existing stable keys reused (examples): `resource-create-button`, `create-choice-ai`,
`ai-create-*` (type/name/reference/submit/plan/slider/origin), `resource-detail-<id>`,
`resource-selection-item-<id>` / `-search-input` / `-confirm-button`,
`assembly-open-world-selection-button` / `-character-selection` / `-npc-selection` /
`-next-phase` / `-start-adventure` / `-opening-ai-generate`, `studio-save-action`,
`studio-retry-failed-parts`. No coordinates, no localized-text coupling, no widget-order
coupling; list items use business ids.

### Task C — integration_test infrastructure

- Added the official `integration_test` SDK package (no third-party framework).
- `LtUiDriver` wraps a `WidgetTester` and exposes bounded, key-based operations:
  `openLibrary`, `openCreateFlow`, `chooseAiCreate`, `enterResourceName`, `enterReference`,
  `setTargetWords`, `readTargetWords`/`readTargetWordsInput`/`readTargetSlider`,
  `submitCreate`, `planBlueprint`, `waitForStudio`, `saveStudio`, `retryFailedParts`,
  `selectWorldview`, `selectCharacters`, `nextAssemblyPhase`, `generateOpening`,
  `startAdventure`, `waitForAdventureSession`, `sendMessage`, `waitForAssistantReply`.
- Waits are bounded by an iteration budget (works under both fake and real clocks) and throw
  `LtUiTimeoutException` naming the missing finder — no fixed `sleep`, no coordinate taps.
- `ScriptedLlmGateway` is the controlled external-model double: it answers blueprint planning
  and NDJSON part generation deterministically and throws on any unmocked method, so no test
  silently depends on a real model. It is never wired into a production composition root.
- Clear separation: host widget tests (deterministic, no device) vs. the device
  `integration_test` entry (real Android path, deterministic model double).

### Task D — preset scenarios

- **Test A (8,000)** and **Test B (20,000)**: host widget tests
  (`resource_ai_create_budget_input_test.dart`) assert the typed value equals the Slider value,
  the shown value, and the captured `ResourceStudioCreationDraft.targetCharacters`; the device
  entry repeats the same assertions through `LtUiDriver`.
- **Test C (boundaries)**: min clamp, max clamp, empty reject+revert, non-numeric
  reject+revert, negative clamp, off-grid snap, Slider↔input two-way sync, survival across a
  page rebuild, and type-change re-clamping.
- **Test D (full flow)**: the device entry drives library → AI create → budget → submit →
  Studio against the real Android path with `ScriptedLlmGateway`. The adventure-assembly and
  real-LLM dialogue portion is a device entry (driver methods provided) and is **not** claimed
  as passed without a device.

### Task E — automation data isolation

- Added `debug { applicationIdSuffix = ".debug"; versionNameSuffix = "-debug" }` in
  `android/app/build.gradle.kts`. Debug/automation builds install as
  `com.example.lt_dialogue.debug` in a separate Android data space and are signed with the
  Android **debug** key, so they can neither upgrade nor read/write the release package's real
  user data.
- Release identity is untouched: `applicationId = com.example.lt_dialogue`, release signing
  config and `verifyReleaseSigning` guard unchanged.
- The test package is disposable and repeatable; no uninstall or data-clear of the release
  app is ever required.

## 4. AUTOMATION COVERAGE

| Core surface | Stable locating key(s) |
| --- | --- |
| Resource library / create entry | `resource-create-button`, `create-choice-ai`, `resource-detail-<id>` |
| AI create (worldview / character / NPC) | `ai-create-type-select`, `ai-create-name-field`, `ai-create-paste-field`, `ai-create-submit-button`, `ai-create-plan-button` |
| Budget | `ai_creation_target_words_input`, `ai_creation_target_words_confirm`, `ai-create-target-slider`, `ai-create-target-value` |
| Generation / save / retry (Studio) | `studio-save-action`, `studio-retry-failed-parts`, `outline-retry-<partId>` |
| Assembly wizard | `assembly-open-world-selection-button`, `assembly-open-character-selection-button`, `assembly-open-npc-selection-button`, `assembly-next-phase-button`, `assembly-start-adventure-button`, `assembly-opening-ai-generate-button` |
| World / character / NPC selection | `resource-selection-search-input`, `resource-selection-item-<id>`, `resource-selection-confirm-button` |
| Adventure session dialogue | `adventure-session-input`, `adventure-session-send-button`, `adventure-session-stop-button` |

## 5. TEST RESULTS

Host (`flutter test --no-pub`, full suite): **PASS — 3 707 passed / 2 skipped / 0 failed**
(baseline 3 689 passed / 2 skipped / 0 failed; +18 new tests). The 2 skips are the
pre-existing opt-in real-TTS / Chrome cases.

New host tests:

- `test/widget/resource_ai_create_budget_input_test.dart` — 13 passed (Test A/B/C).
- `test/widget/lt_ui_driver_host_test.dart` — 5 passed (driver layer, incl. a bounded-timeout
  diagnostic test).

`dart format --output=none --set-exit-if-changed lib test` and `git diff --check`: PASS.
`flutter analyze`: PASS (zero issues).

## 6. BUILD VALIDATION

- `flutter build apk --debug --target-platform android-arm64` → success;
  `aapt2 dump badging` shows `name='com.example.lt_dialogue.debug' versionName='1.2.06-debug'`,
  signer `C=US, O=Android, CN=Android Debug`.
- `flutter build apk --release --target-platform android-arm64` → success (54.8 MB);
  `aapt2 dump badging` shows `name='com.example.lt_dialogue' versionCode='28'
  versionName='1.2.06'`, signer `CN=LT Android Release` (SHA-256 `1fb69259…e07b2d`, unchanged
  from the release identity). ARM64-only and Neural TTS native libraries are unaffected.

## 7. DATA ISOLATION

- Automation/debug package `com.example.lt_dialogue.debug`, signed with the debug key → separate
  data directory, cannot touch `com.example.lt_dialogue`.
- Release applicationId, signing and upgrade compatibility unchanged (verified by building the
  release APK and inspecting its signer).
- No uninstall, no `pm clear`, no user-resource access is part of automation.

## 8. LIMITATIONS

- The device `integration_test` entry is **not executed** here; only its host-testable parts
  are covered by the host suite. Compiling is not "device-passed".
- The adventure-assembly and real-LLM dialogue turn are driven by the same driver but require a
  real device and real model; they remain a device checklist item.
- The budget input snaps typed values to the 500-character Slider grid and clamps out-of-range
  values; this is intentional domain consistency, not a silent rejection.
- `adventure_wizard_screen.dart` (the secondary "预存场景工坊" wizard) was not re-keyed; the
  active library/dashboard wizard is `assembly_create_page.dart`, which is fully keyed.

## 9. DEVICE TEST STATUS

`NOT EXECUTED — DEVICE UNAVAILABLE BY DESIGN`

Future device command (to be run when a device is connected):

```
flutter test integration_test/lt_core_flow_test.dart -d <deviceId>
```

The debug/automation build it installs is `com.example.lt_dialogue.debug`, isolated from the
release app's real user data.

## 10. FINAL STATUS

**ACCEPTED (host scope).**

- Numeric budget input with verified two-way Slider sync and unified validation.
- 8 000 and 20 000 budget configurations verified end-to-end into the generation draft.
- Core business UI operable through stable, non-coordinate keys with a reusable driver layer.
- Deterministic external-LLM double; host/dev flows separated from real-LLM device flows.
- Automation data isolation implemented and build-verified; release identity unchanged.
- No known regression in the existing suite; no P0 fix was altered.
