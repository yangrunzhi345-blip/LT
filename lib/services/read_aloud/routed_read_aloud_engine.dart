import '../../domain/read_aloud/read_aloud_contracts.dart';
import 'read_aloud_engine.dart';

/// Thin routing shell over the platform read-aloud engine.
///
/// LT ships only the lightweight system TTS backend ([FlutterTtsEngine] /
/// [LinuxReadAloudEngine]); the former neural backend and its model manager have
/// been removed. The class name is retained because the read-aloud authority and
/// tests refer to it, but every call now delegates straight to the system engine.
class RoutedReadAloudEngine implements ReadAloudEngine {
  RoutedReadAloudEngine({required ReadAloudEngine systemEngine})
      : _system = systemEngine;

  final ReadAloudEngine _system;

  @override
  ReadAloudCapability get capability => _system.capability;

  @override
  bool get isInitialized => _system.isInitialized;

  @override
  Future<void> initialize() => _system.initialize();

  @override
  Future<void> configure({
    double? rate,
    double? pitch,
    double? volume,
    String? language,
  }) =>
      _system.configure(
        rate: rate,
        pitch: pitch,
        volume: volume,
        language: language,
      );

  @override
  Future<List<String>> availableLanguages() => _system.availableLanguages();

  @override
  Future<void> speak(String text) => _system.speak(text);

  @override
  Future<void> stop() => _system.stop();

  @override
  Future<bool> pause() => _system.pause();

  @override
  Future<bool> resume() => _system.resume();

  @override
  set onComplete(void Function()? handler) => _system.onComplete = handler;

  @override
  set onStart(void Function()? handler) => _system.onStart = handler;

  @override
  set onCancel(void Function()? handler) => _system.onCancel = handler;

  @override
  set onError(void Function(Object error)? handler) =>
      _system.onError = handler;

  @override
  void dispose() => _system.dispose();
}
