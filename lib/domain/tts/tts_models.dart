/// Read-aloud backend selector retained by the public contracts.
///
/// LT no longer ships a neural backend. The enum keeps `system` as the only
/// backend the app can select; `neural` remains for decoding persisted settings
/// written by older versions without failing.
library;

enum TtsBackendKind {
  /// The built-in system TTS (flutter_tts / Linux Speech Dispatcher).
  system,

  /// Legacy value from the removed neural backend. Never selected by new code.
  neural,
}
