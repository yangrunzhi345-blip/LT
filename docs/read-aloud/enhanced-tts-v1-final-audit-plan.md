# Enhanced TTS v1 final independent audit — implementation specification

## Baseline and scope

- START_HEAD = START_ORIGIN = `138f73c573ad3c34503fadab199dc7a4b7ae3bec`.
- START_WORKTREE = clean, branch main. No Codex-specific rule file was found.
- Authority: AGENTS.md, current code and production execution; prior reports are leads only.
- Scope: Enhanced TTS, existing system read-aloud regression, build/package validation.
- Excluded: new model families, cloning, cloud TTS, DB/resource/presence redesign,
  navigation redesign, cache or streaming protocol additions, permanent ABI changes.

## Current architecture and invariants

| Owner | State / lifetime | Persistence | Concurrency / error boundary |
| --- | --- | --- | --- |
| ReadAloudController | global queue, run id, active chunk | existing preferences KV | rejects old run callbacks, owns sequence and fallback notices |
| PlaybackQueue / TextSegmenter | per session chunks, paragraph IDs | none | bounds utterances, planner metadata must survive segmentation |
| SpeechPlanner | pure per-plan role/resource attribution | none | ambiguity and unknown speakers use narrator; prose semantics preserved |
| Adventure speaker projection | stable selected resource / NPC snapshot IDs | existing Adventure snapshots | projects roster, no new presence authority |
| VoiceBindingStore / Resolver | device preferences; per-plan assignments | settings KV, stable resource IDs | explicit binding precedes auto; compatible versioned family contract |
| RoutedReadAloudEngine | one delegated system/neural utterance | none | select/configure/speak and stop must not revive stale work |
| Sherpa worker | isolate owns native OfflineTts | none | serialized commands; load/free/crash/dispose resolve all requests |
| NeuralAudioPlayer | delegated PCM playback | owned temporary WAV only | complete/stop/error/dispose release source; never independent authority |
| TtsModelManager | install registry/status, operation per model | verified tree + manifest | explicit download only; download/cancel/delete/refresh serialized |
| Downloader / Extractor | operation HTTP/sink/staging | resumable .part | validate range, paths/types, bounded memory, close every handle |

Product paths: UI / ChatEngine.autoRead → controller → planner/queue → resolver →
routed engine → system or Sherpa worker → mono float PCM → WAV → audioplayers.
Install path: explicit download → HTTP → .part → whole SHA256 → file-backed archive
extraction → staging validation → manifest → atomic publish → registry → runtime.

## Confirmed findings and implementation requirements

1. BLOCKER: install only locates ONNX; refresh checks existence, not nonzero bytes,
   manifest contract or complete tree. Validate required files/lexicons/data,
   whitelist manifest paths, match identity/version/family/integrity, record and
   check file sizes. Publish a flushed manifest inside staging before rename.
   Recovery must not invent installed state; stale staging may be cleaned only
   when no operation owns it. Keep valid resumable downloads.
2. MAJOR: Range 206 trusts status without checking start/end/total. Reject
   mismatches before append, restart oversized .part, verify full size/digest,
   bound response inactivity and storage-error mapping.
3. MAJOR: cancel/delete race with download/extract and refresh overwrites active
   status. Serialize operations, await writer/extractor before cleanup, suppress
   progress after cancellation, dedupe downloads, permit immediate safe retry.
4. MAJOR: routed inference can play after stop/new session, switching doesn't
   consistently stop old backend; per-session failed-model set never resets.
   Use operation identity checks across every await, atomic voice+utterance
   delivery from controller, cancellation of both backends, stale callback
   rejection and recoverable fallback. Active model deletion must stop and
   release its runtime before deleting files (manager hook, no second authority).
5. MAJOR: Sherpa init/load/dispose and worker exit lifecycle are not controlled.
   Serialize worker commands, dedupe startup/model load, guard speaker bounds,
   supervise errors/exits, graceful acknowledged free before forced fallback,
   never send to an absent port or leave requests hanging.
6. MAJOR: dependency setSourceBytes writes unowned temporary WAV on desktop /
   Darwin. Explicitly own source lifecycle, clean on all terminal paths, test
   production wrapper with audio platform fake and inspect actual WAV header.
7. MAJOR: compatible dual-model resolution follows catalog order. Define a
   documented deterministic installed-model priority independent of list order,
   cover one/both/delete/reinstall without changing voice family identity.
8. BLOCKER: planner uses remote names and weak substring cues, assigning unknown
   dialogue to a known character. Require local attribution, whole-name matching,
   ambiguity → narrator; preserve interrupted dialogue and Chinese/English forms.
9. MAJOR: resource voice picker labels System / Auto identically but both clear
   binding. Represent explicit system choice distinctly and preserve auto clear.

## Ownership and handoff

- Root: model manager/storage/download/extraction, plan/report, actual E2E and builds.
- Runtime audit/execution: controller/routed/Sherpa/audio and associated tests;
  read this specification before editing; report extra issues without widening scope.
- Speaker audit/execution: catalog/resolver/planner/bindings/autoRead/picker and tests.
- Independent review: inspect other executor's diff against this specification;
  no reviewer edits without root authorization. One final commit after verification.

## Tests and acceptance

Reproduce before fix; add regression for every confirmed BLOCKER/MAJOR. Cover
archive content and non-regular entries, all traversal forms, 206 mismatches,
duplicate/cancel/retry/delete operations, corrupt/zero-byte manifests, dual models,
speaker 0/102/invalid, late synthesis, atomic voice selection, active deletion,
Chat autoRead with two voices, name/alias ambiguity, duplicate paragraph identity.
Verify settings defensive decoding, zero automatic HTTP, default system mode,
stable resource binding, narrator fallback, architecture import boundaries.

Final gates: format, analyze, full flutter test (counts), diff check; Linux release;
Android debug/release APK and release AAB, arm64/native presence and no weights;
Windows static paths/plugins/artifacts if no toolchain. Production manager +
Sherpa Kokoro INT8 E2E: install/manifest/nonzero files/load, zh/en/mixed, sid 0/102,
different speakers, invalid sid, load/inference/RSS observations and WAV metadata.
Audio output only claim if actual host playback ran. UI edits require 320 px,
phone/tablet/desktop and large text checks. Update architecture doc to match code.
Final report uses attachment sections and layered verification terminology.
No ACCEPTED while a proven BLOCKER/MAJOR remains; no unexecuted runtime claims.
