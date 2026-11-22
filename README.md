# LT Dialogue

[![Flutter](https://img.shields.io/badge/Flutter-app-02569B?logo=flutter)](https://flutter.dev/) [![Latest release](https://img.shields.io/github/v/release/yangrunzhi345-blip/LT)](https://github.com/yangrunzhi345-blip/LT/releases/latest)

[English](README.md) | [简体中文](README.zh-CN.md)

LT Dialogue is a local-first workbench for AI interactive storytelling, worldbuilding, and character creation.

Build reusable resources, start Adventures from their snapshots, and follow the story alongside its changing character and world state. LT uses Flutter, Dart, Riverpod, and SQLite.

![LT Dialogue logo](logo.png)

## Highlights

- Interactive Adventures with streaming turns, action choices, branches, and saved-session recovery.
- A searchable Resource Library for worldviews, character cards, and NPCs, with manual editing and single-shot AI drafting.
- Character relationships carried from library resources into evolving Adventure state and narrative context.
- A Runtime State Hub with a dashboard, entity views, timelines, and per-turn changes.
- Translation and system read-aloud for conversations and resource text.
- Responsive navigation: a desktop sidebar with recent Adventures and compact navigation for smaller screens; access Adventure, Resource Library, Runtime State, and Settings.

## Interactive Adventures

Use the creation wizard to select a worldview, protagonist, companions, and NPCs, configure the opening scene, and check readiness before starting. Selected resources become Adventure-owned snapshots; subsequent library edits do not silently rewrite an existing Adventure.

During play, stream narrative turns, choose actions, create branches, switch the active character, and resume saved sessions. Bookmarks, message editing, dice checks, conversation import/export, and context summaries support longer stories.

## Resource Library

Create, edit, search, filter, sort, and delete worldviews, character cards, and NPCs. Each resource is a single editable document rather than a tree of sections and parts: the editor writes the whole card, and an AI draft is rendered into that same document for review before saving.

Legacy tree rows and older library rows are migrated once into this card shape, so existing data stays readable and editable. Deleting a card removes it from the library; the app has no recycle-bin restore screen.

Character and NPC cards also carry the relationships and tracked-state definitions that the Adventure wizard and the Runtime State Hub read.

## Characters, Relationships & Runtime State

Manage character relationships in the library, and link related characters while drafting a new one in the creation wizard. Relationships between selected characters can be copied into the Adventure snapshot and evolve during play. Current relationship state enters the narrative context and its weighted token-budget planning, so relevant changes can influence subsequent AI storytelling. Later library relationship edits do not silently change that snapshot.

For the active Adventure, the Runtime State Hub provides a dashboard, character and world state, locations, factions, relationships, tracked state, a timeline, and turn history. Inspect recorded changes and entity history alongside the story.

## AI-Assisted Authoring

Configure an OpenAI-compatible endpoint, model, and API key. The Resource Library can draft a worldview, character, or NPC from a short instruction, and the model's structured answer is rendered into the card document, which you edit and save yourself. Generation is one request per card; there is no multi-step blueprint, part-by-part streaming, revision history, or automatic compression stage.

Adventure generation assembles resource snapshots, recent narrative, summaries, and runtime state within a context budget. Structured state output is parsed and validated before accepted changes are persisted and used in later turns.

## Read Aloud

Read-aloud uses the platform's system speech engine; no neural model is bundled, downloaded, or selectable. Settings expose enable, automatic reading, rate, pitch, and language.

On Linux, system read-aloud uses Speech Dispatcher when available. Conversation translation uses the configured text model, independently of read-aloud.

## Local-first Architecture

Resources, Adventures, messages, and application settings are primarily persisted in local SQLite. API keys go to the platform credential store when the OS provides one, with an application-encrypted SQLite fallback; this does not mean the entire database is encrypted.

AI text generation and translation send the required context to your configured endpoint, which may be remote. Local-first storage does not mean every AI feature works offline.

## Localization

The UI supports English and Simplified Chinese. Select a language during onboarding or in Settings. Translation sources are in [`lib/l10n/`](lib/l10n/).

## Installation

### Download Android Release

Download the signed APK from [Latest Release](https://github.com/yangrunzhi345-blip/LT/releases/latest). Official prebuilt releases currently provide **Android ARM64 / arm64-v8a only**. Windows, Linux, macOS, and iOS installers are not currently distributed through this release workflow.

See [`docs/releases/`](docs/releases/) for release-specific details and signing/upgrade notes. When moving from an older debug-signed build, back up/export your data before any uninstall required by Android's signing rules.

### Run from Source

The repository includes Android, Linux, Windows, macOS, and iOS platform projects for source development; platform toolchains and service availability still apply. Android configuration currently restricts native libraries to ARM64.

Use Git, Flutter stable, and the target platform's native toolchain. `pubspec.yaml` declares Dart `>=3.0.0 <4.0.0`, but the current [`pubspec.lock`](pubspec.lock) requires **Flutter >=3.44.0 and Dart >=3.12.0 <4.0.0**. The checked source setup uses Flutter 3.44.8 / Dart 3.12.2.

```bash
git clone https://github.com/yangrunzhi345-blip/LT.git
cd LT
flutter pub get
flutter run
```

Use `flutter devices` to select a target, then `flutter run -d <device-id>` if needed. Configure the model service during onboarding or in Settings before AI generation.

## Development

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Run focused tests while developing; the repository CI checks formatting, analysis, and Flutter tests. See [`AGENTS.md`](AGENTS.md) for repository working rules.

## Project Structure

- [`lib/features/`](lib/features/): feature UI and related feature code.
- [`lib/application/`](lib/application/): use cases, narrative context, and orchestration.
- [`lib/domain/`](lib/domain/): domain contracts and models.
- [`lib/services/`](lib/services/): persistence, repositories, model access, and TTS.
- [`lib/core/`](lib/core/): shared routing, theme, and UI foundations.
- [`test/`](test/): automated tests; [`docs/`](docs/): implementation and development documentation.

Existing controllers, providers, screens, and widgets coexist with these boundaries. Start at [`lib/main.dart`](lib/main.dart); use the [`documentation index`](docs/README.md) for deeper references.

## Roadmap

Future work focuses on resource authoring, Adventure state tools, recovery, and cross-platform polish. These are ongoing improvement areas, not additional shipped capabilities.

## Contributing

Focused pull requests are welcome. Describe the behavior change, protect user data and credentials, update affected documentation, and run relevant checks before opening a PR.

## License

The repository currently has no root `LICENSE` file. Contact the project owner through GitHub before redistributing or using LT commercially.
