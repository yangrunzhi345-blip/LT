# LT Dialogue

[![Flutter](https://img.shields.io/badge/Flutter-app-02569B?logo=flutter)](https://flutter.dev/) [![Dart](https://img.shields.io/badge/Dart-%3E%3D3.0.0-0175C2?logo=dart)](https://dart.dev/)

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md)

LT Dialogue is a local-first AI interactive storytelling platform built with Flutter and Dart. It combines a structured resource library, AI-assisted world and character creation, and stateful Adventure sessions in one application. Local SQLite storage keeps your resources, adventures, messages, revisions, and settings on the device by default.

![LT Dialogue logo](logo.png)

## Key features

- **Interactive Adventures** — build an Adventure in a guided flow: choose a worldview, protagonist and supporting cast, bind NPC snapshots, set the opening scene and options, review readiness, and start from a stable resource revision. During play, stream each turn, choose actions, create branches, switch characters, and resume from saved state.
- **World and character resources** — create, import, search, filter, and edit worldviews, character cards, and NPC records. Resources use an ordered `Resource → Section → Part` structure so long setting material stays reusable and navigable.
- **AI generation pipeline** — start an idempotent creation or import session, provide pasted or file text, plan a blueprint, confirm candidates, generate parts through the configured model, validate the result, and recover or retry failed work without silently duplicating resources.
- **Resource Studio** — work on one resource in a focused editor: add and reorder sections, edit or retry individual parts, follow streaming progress, restore autosaved drafts, inspect revision history, and publish compression candidates without replacing the current content automatically.
- **Stateful storytelling** — each Adventure owns its messages, scene state, character and NPC snapshots, world entries, branches, summaries, and runtime commits. Structured model output is parsed, checked against the active revision, and persisted before it affects the next turn.
- **Reading support** — translate conversation content and read selected text aloud through the platform TTS service. Linux desktop uses Speech Dispatcher when detected and keeps the read-aloud entry hidden when no usable voice backend is available.
- **Navigation-first UI** — move between Adventure, Resource Library, Resource Studio, and Settings through a responsive shell. Desktop uses a sidebar while compact layouts use drawer or bottom navigation patterns.

## Architecture overview

```text
Flutter pages and widgets
          ↓
Controllers, Riverpod providers, and application use cases
          ↓
Domain contracts, engines, repositories, and model gateways
          ↓
SQLite + configured OpenAI-compatible endpoint + platform services
```

The repository is in a gradual architectural transition. The newer `features/`, `application/`, and `domain/` boundaries coexist with established `controllers/`, `providers/`, `services/`, `screens/`, and `widgets/` code. New work should follow the relevant feature and application boundaries instead of assuming one directory is the whole architecture.

## AI generation system

LT connects directly to a configured OpenAI-compatible model endpoint. You choose the base URL, model, and API key in Settings; the key is stored locally through the application’s secure storage path. Resource creation and import flows support manual input, pasted or file text, existing resources, planning sessions, structured blueprints, streaming generation, validation, and retry/recovery.

Adventure responses contain narrative text and structured state data. The application validates the structured result before it becomes part of the next turn or is written to the local database.

## Characters and worlds

The resource model is:

```text
Resource → Section → Part
```

Worldviews hold setting material such as rules, places, and factions. Character cards and NPC records hold reusable people and relationships. When an Adventure starts, selected resources are assembled into Adventure-owned snapshots, so later library edits do not silently rewrite an existing story.

## Resource Library

The Resource Library supports search, type filtering, detail views, manual editing, AI creation, import flows, autosave and draft recovery, revision history, trash and restore, capacity checks, and compression candidates. Resource Studio provides the focused editing and generation workspace for sections and parts.

## Reading experience

Adventure sessions support streaming output, optional reasoning display, action choices, branches, bookmarks, character switching, dice checks, message editing, bounded context and summaries, conversation import/export, translation, and read-aloud. Runtime state is committed through validated, revision-aware application services rather than treating raw model output as database input.

## Multi-language support

The application currently ships UI localization for English, Simplified Chinese, Traditional Chinese, Japanese, and Korean. The source translations live under [`lib/l10n/`](lib/l10n/), and language selection is available during onboarding and in Settings.

## Screenshots

UI screenshots are not currently committed to the repository. The tracked logo above is the available project visual; screenshots can be added when a stable capture set is maintained.

## Installation

### Requirements

- Git.
- Flutter stable with a Dart SDK satisfying `>=3.0.0 <4.0.0`.
- The SDK and native toolchain for the target platform: Android SDK, Xcode, Linux desktop dependencies, or Windows desktop tooling as appropriate.

### Run from source

```bash
git clone https://github.com/yangrunzhi345-blip/LT.git
cd LT
flutter pub get
flutter devices
flutter run -d linux       # or windows / macos
# flutter run -d android
# flutter run -d ios
```

On first launch, open Settings and configure a DeepSeek or other OpenAI-compatible service. A custom service requires its base URL, model name, and API key.

Supported product targets are Linux, Windows, Android, macOS, and iOS.

## Development

```bash
dart format .
flutter analyze
flutter test
flutter test benchmark/core_benchmark.dart
```

Useful entry points include [`lib/main.dart`](lib/main.dart), [`lib/core/router/app_router.dart`](lib/core/router/app_router.dart), [`docs/README.md`](docs/README.md), and [`docs/adventure_runtime_state.md`](docs/adventure_runtime_state.md).

## Roadmap

The project continues to improve resource authoring, Adventure state tooling, recovery behavior, and cross-platform polish. Generic tool-calling agents, graph or vector databases, and autonomous cross-resource decision systems are not presented as shipped LT features; they require separate implementation and documentation before they belong in this list.

## Contributing

Small, focused pull requests are welcome. Please describe the behavior change, keep user data and credentials safe, update documentation when source behavior changes, and run the relevant formatter, analyzer, and tests before opening a pull request.

## License

This repository currently has no root `LICENSE` file. Contact the project owner through GitHub before redistributing or using LT commercially.
