import 'dart:typed_data';

/// Plays raw neural TTS audio.
///
/// Abstracted so the routing engine can be tested without any platform audio.
/// Implementations never become a second playback authority: the global
/// [ReadAloudController] still sequences segments and owns pause/resume/stop.
abstract class NeuralAudioPlayer {
  bool get isInitialized;

  Future<void> initialize();

  /// Replaces any current audio with [samples] (mono, `[-1, 1]`) at
  /// [sampleRate] Hz and starts playback.
  Future<void> play(
    Float32List samples,
    int sampleRate, {
    double volume = 1.0,
  });

  Future<void> stop();

  Future<bool> pause();

  Future<bool> resume();

  set onComplete(void Function()? handler);

  set onError(void Function(Object error)? handler);

  Future<void> dispose();
}
