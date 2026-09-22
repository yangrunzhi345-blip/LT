import 'linux_tts_backend_contract.dart';

LinuxTtsBackend createLinuxTtsBackend() => _UnavailableLinuxTtsBackend();

final class _UnavailableLinuxTtsBackend implements LinuxTtsBackend {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<List<String>> availableLanguages() async => const <String>[];

  @override
  Future<void> speak(
    String text, {
    required double rate,
    required double pitch,
    required double volume,
    String? language,
  }) async {
    throw StateError('Linux TTS requires a Dart IO runtime.');
  }

  @override
  Future<void> stop() async {}

  @override
  void dispose() {}
}
