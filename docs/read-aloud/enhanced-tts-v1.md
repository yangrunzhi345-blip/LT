# Enhanced TTS v1 — Optional Local Neural Read-Aloud

Baseline: `main` @ `133910d`. This document describes the implemented
architecture and is kept in sync with the code.

## 1. Goals and invariants

- System TTS stays the **default**, immediately available, zero-download mode.
- Enhanced mode is **opt-in**: local, offline neural TTS via `sherpa-onnx`.
- **LT never automatically downloads a model.** A network request happens only
  when the user explicitly chooses Download.
- `ReadAloudController` remains the **single global playback authority**.
- Voice bindings are keyed by a **stable resource id**, never by a character
  name, model path or speaker integer, and are **never** written into
  character/NPC content.

## 2. Authority and engine routing

```
UI / ChatEngineHost / Resource Studio
        │  (play / playText / toggle)
        ▼
ReadAloudController                ← single playback state machine + run token
        │  resolve voice → selectVoice(target) → speak(text)
        ▼
RoutedReadAloudEngine implements ReadAloudEngine (and ReadAloudVoiceAwareEngine)
     ↙                                   ↘
System backend                     Neural backend
(flutter_tts / Linux spd-say)      (sherpa-onnx worker isolate + audioplayers)
```

- `ReadAloudVoiceAwareEngine` is an **optional** capability interface. System
  engines and existing test fakes do not implement it, so they are unchanged.
- The routing engine lazily creates the neural engine and audio player on first
  neural use, so building the runtime never touches native/platform audio.
- Every neural failure degrades to the system backend **without interrupting the
  current session**. The authority surfaces at most one localized notice per
  session (`ReadAloudState.voiceFallbackCode`).

## 3. Domain model (pure Dart, `lib/domain/tts/`)

| Type | Purpose |
| --- | --- |
| `TtsBackendKind` | `system` / `neural` |
| `TtsModelDescriptor` | model id, version, engine/voice family, languages, speaker count, verified download URI + size + digest, license, required files, capabilities |
| `TtsVoiceDescriptor` | `voiceId` (`<family>:s<sid>`), family, speaker id, languages, capabilities |
| `TtsVoiceCapabilities` | real per-voice control surface (Kokoro: rate + volume, no pitch) |
| `VoiceBinding` / `NarratorVoiceBinding` | resource id → voiceId; narrator → voiceId |
| `TtsVoicePreferences` | mode, narrator voice, default character voice, auto-assign flag, bindings map |
| `SpeechRole` / `SpeechSegment` / `SpeechPlan` | narration / dialogue / unknown and the planned segments |
| `NarrativeSpeakerRef` / `NarrativeSpeakerContext` | pure-data speaker roster (resource id, name, aliases) |
| `ReadAloudVoiceTarget` | resolved backend + voice + speaker for one segment |
| `TtsErrorCode` / `TtsException` | stable localizable failures + technical detail kept inside the service layer |

Model / Speaker / Voice are decoupled: a character binds a stable `voiceId`; the
resolver maps `voiceId → voiceFamily → modelId → speakerId → install state`.
`voiceFamily` lets a binding survive re-downloading a compatible release (int8
vs fp32 v1.1 share the same 103 voices).

## 4. Model system

- Catalog (`TtsModelCatalog`) contains only **verified** sherpa-onnx releases:
  - `kokoro-int8-multi-lang-v1_1` — 147,031,220 bytes, sha256
    `a1e94694…4dcafc6`, 103 speakers, zh-CN + en-US.
  - `kokoro-multi-lang-v1_1` — 364,816,464 bytes, sha256
    `a3f4c73d…78dbad`, 103 speakers.
- `TtsModelManager` is the single install authority (catalog, download, verify,
  extract, install, delete, disk usage). It cannot control playback and never
  downloads on construction/refresh.
- Install pipeline: `download → verify (size + sha256) → extract to staging →
  validate required files → locate model root → atomic move → write manifest.json`.
  A `.part` file is never treated as installed.
- Download security: `package:http` streaming (no `wget`/`curl`/`tar` shell-out),
  Range resume when the server honours it (falls back to a full restart when it
  does not), cancellation checks between chunks, and typed failures.
- Extraction uses `package:archive` (BZip2 + TAR streaming) with strict path
  validation: absolute paths, drive letters and `..` are rejected, and the
  resolved canonical path must stay inside the staging root.
- Storage layout under the app-support directory:

```
<ApplicationSupport>/tts/
  models/<modelId>/<version>/{manifest.json, model*.onnx, voices.bin, tokens.txt, …}
  downloads/<modelId>.<version>.part
  staging/
```

Model binaries are never written to `assets/`, the source tree or a hard-coded
user directory (guarded by an architecture test).

## 5. Voice casting

Resolution order (`TtsVoiceResolver`):

```
explicit per-resource binding
  → default character voice
  → deterministic auto assignment (if enabled + a model is installed)
  → narrator binding
  → system TTS
```

- Narrator is a **first-class** voice; unattributed dialogue and narration use it.
- Auto assignment uses **FNV-1a (stable hash)**, not Dart `hashCode`, and applies
  per-plan collision avoidance so co-occurring speakers get different voices
  when the pool allows. Gender is never used.
- Unresolved/ambiguous speakers fall back to the narrator — the planner never
  guesses a character.

## 6. Speech planner (`SpeechPlanner`)

- Pure Dart, **no LLM**, deterministic, offline.
- Splits paragraphs, finds Chinese/English quotes (`“”`, `「」`, `『』`, `"`), and
  attributes dialogue only on a high-confidence cue (speaker name adjacent to a
  speech verb or an attribution colon).
- Planning is applied **only when a non-empty `NarrativeSpeakerContext` is
  provided**, so existing callers keep the previous segmentation behaviour
  exactly.
- Chat auto-read supplies the current Adventure roster
  (`buildAdventureSpeakerContext`), so dialogue can use per-character voices.

## 7. Reading UX

- Paragraph-aware presentation (`NarrativeParagraphReadView`) on Chat AI
  bubbles and Resource Studio part cards: **read this paragraph** and **read
  from this paragraph** (hover on desktop, long-press menu on mobile), sharing
  paragraph chunk ids with the whole-text button so highlighting is consistent.
  Text selection across widgets is not hijacked; "read this paragraph" is the
  guaranteed surface.
- The active paragraph is marked with a lightweight accent surface (8% primary,
  4 px radius). The page is never force-scrolled.
- Voice model manager page (`TtsModelManagerPage`) shows name, languages,
  speaker count, size, license, version, status and progress; never URLs, paths
  or ONNX file names.
- Voice picker (`showTtsVoicePicker`) is a compact virtualized list, browsable
  for uninstalled voices; choosing an uninstalled voice asks for an explicit
  download confirmation first.

## 8. Persistence

Stored in the existing settings KV (`ISettingsRepository`) — **no schema
change**, database schema version unchanged:

| Key | Content |
| --- | --- |
| `tts_neural_preferences_v1` | `{schema, mode, autoAssignVoices}` |
| `tts_voice_bindings_v1` | `{schema, bindings: {resourceId: voiceId}}` |
| `tts_narrator_voice_binding_v1` | `{schema, voiceId}` |
| `tts_default_character_voice_v1` | `{schema, voiceId}` |

Parsing is defensive: missing/malformed/newer JSON falls back per-field and can
never break startup or discard other settings. Deleting a model **keeps** voice
bindings (they are a separate store); the bound voice simply shows as
unavailable until a compatible model is installed again.

## 9. Platform status

| Platform | System TTS | Neural TTS runtime |
| --- | --- | --- |
| Linux | Speech Dispatcher (`spd-say`) | sherpa-onnx + audioplayers (GStreamer) |
| Windows | flutter_tts | sherpa-onnx + audioplayers |
| Android | flutter_tts | sherpa-onnx + audioplayers |
| macOS | flutter_tts | sherpa-onnx + audioplayers |
| iOS | flutter_tts | sherpa-onnx + audioplayers |

Neural inference runs on a dedicated worker isolate (each isolate calls
`sherpa-onnx` bindings itself), the loaded model is cached, and switching
speakers of the same model does not reload it. Native build/run smoke tests were
NOT RUN in the authoring environment (see the task report for the explicit list).

## 10. Testing

- `test/unit/tts_speech_planner_test.dart` — narration/dialogue, attribution,
  ambiguity → narrator, English quotes, empty text.
- `test/unit/tts_voice_assignment_test.dart` — stable hash + collision avoidance.
- `test/unit/tts_voice_binding_store_test.dart` — encode/decode + bad JSON.
- `test/unit/tts_voice_resolver_test.dart` — resolution order + fallback.
- `test/unit/tts_model_manager_test.dart` — **no auto download**, progress,
  cancel, pause/resume, non-2xx, integrity, unsafe archive, install, delete.
- `test/unit/tts_archive_extractor_test.dart` — benign + traversal rejection.
- `test/unit/tts_routed_engine_test.dart` — routing, model reuse, fallback.
- `test/architecture/enhanced_tts_guard_test.dart` — import boundaries, single
  authority, no model binaries in assets, no voice identity in drafts.
- `test/widget/tts_settings_section_test.dart` — default system mode, no
  auto-download, model manager navigation, 320 px overflow-free.

## 11. Known limitations

- Neural read-aloud is documented as available only where the native runtime can
  load; if it cannot, playback falls back to system TTS (the session never
  breaks).
- Cross-widget text selection ("read selection") is not implemented; per
  paragraph reading covers the requirement.
- Whole-resource continuous reading in Resource Studio highlights at part level;
  per-paragraph highlight applies to per-part / chat reading.
- No persistent audio cache is implemented (generated audio is played and
  released); this avoids unbounded WAV growth.
- Real neural inference (native bindings + a downloaded model) is validated by
  design and unit-tested through fakes; an on-device integration test is not part
  of `flutter test`.
