/// Process-backed Linux speech synthesizer used by [LinuxReadAloudEngine].
abstract class LinuxTtsBackend {
  /// Whether the backend executable is installed and responds to probing.
  Future<bool> isAvailable();

  /// Returns locale tags reported by Speech Dispatcher voices.
  Future<List<String>> availableLanguages();

  /// Speaks one utterance and completes when the backend finishes it.
  Future<void> speak(
    String text, {
    required double rate,
    required double pitch,
    required double volume,
    String? language,
  });

  /// Stops the active utterance, if any.
  Future<void> stop();

  /// Releases process resources.
  void dispose();
}
