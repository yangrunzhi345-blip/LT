# README Audit

Date: 2026-09-24
Baseline: current `main` worktree (`8981942`)

## Scope and evidence

This audit compares the repository documentation with the current source tree. The primary evidence is `pubspec.yaml`, `lib/main.dart`, `lib/core/localization/app_locale.dart`, `lib/core/router/app_router.dart`, `lib/services/database_service.dart`, the `lib/features/` tree, and the current tests and documentation index.

## Confirmed project facts

| Area | Current evidence and conclusion |
| --- | --- |
| Positioning | `lt_dialogue` is a Flutter/Dart, local-first AI interactive storytelling application. Local SQLite stores resources, adventures, messages, runtime state, versions, and settings. |
| Main experiences | The source tree contains Adventure session and assembly flows, Resource Library, Resource Studio, Settings, onboarding, conversation management, import/export, and read-aloud services. |
| Resource model | The current resource pipeline uses `Resource → Section → Part`, with resource creation, generation, revisions, autosaves, trash, compression, assembly readiness, and migration tables in `DatabaseService`. |
| AI generation | Application and gateway layers provide OpenAI-compatible model requests, streaming generation, resource blueprints, creation sessions, import flows, and structured Adventure turn handling. |
| Adventure state | Adventure-owned snapshots, messages, branches, runtime entities, state commits, scene state, and setting candidates are persisted separately from library resources. |
| Architecture | The code is a transitional layered Flutter application. `features`, `application`, `domain`, `data`, `services`, `controllers`, `providers`, `screens`, and `widgets` coexist; the README should describe boundaries without claiming a fully migrated architecture. |
| Storage | SQLite schema version is `44` (`lib/services/database_service.dart`). Desktop initialization uses `sqflite_common_ffi`; mobile uses `sqflite`. API keys are handled by the local KeyVault path and `api_keys` table. |
| Platforms | Platform-specific code and project folders exist for Linux, Windows, Android, macOS, and iOS. The product documentation should list these five targets. Web code paths exist for selected services, but web is not listed as a supported product target in the project brief. |
| UI languages | `AppLocale` defines exactly five UI languages: English, Simplified Chinese, Traditional Chinese, Japanese, and Korean. |
| Read-aloud | `flutter_tts` is used on supported platforms; Linux desktop has a Speech Dispatcher (`spd-say`) engine with capability detection and fallback behavior. |
| Installation | `flutter pub get`, `flutter run`, `flutter analyze`, and `flutter test` are the repository-supported development commands. Platform toolchains are required for the selected target. |
| License | No root `LICENSE` file is tracked. README language must state this accurately instead of assigning a license. |

## Stale or unsupported claims found in the previous README

- The previous root README was predominantly Chinese and therefore was not an English GitHub entry point.
- Its version and test snapshot were stale (`1.1.15+18` and a dated 1,917-test report); `pubspec.yaml` currently declares `1.1.16+19`.
- It contained very detailed internal phase and implementation claims that are not appropriate as the short project entry point and could drift from code.
- It described several legacy compatibility paths and historical implementation details without clearly separating them from the supported product surface.
- It listed aspirational systems such as generic tool calling, graph/vector databases, and autonomous agent workflows as excluded boundaries; these are retained only as a concise roadmap boundary in the new README.
- It linked to `docs/adventure_runtime_state.md` and `docs/README.md`, which exist. Other links in the rewritten README must be checked against the current tree.

## Documentation decisions

1. Make `README.md` a concise English product and developer entry point.
2. Add aligned `README.zh-CN.md`, `README.zh-TW.md`, `README.ja.md`, and `README.ko.md` files.
3. Keep implementation detail in `docs/` and link only to current, useful documents.
4. State the missing license and unsupported/roadmap boundaries plainly.
5. Avoid release metrics, test counts, or feature claims that are not stable source facts.
