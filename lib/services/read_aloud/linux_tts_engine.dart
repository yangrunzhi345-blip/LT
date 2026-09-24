import 'dart:async';

import '../../domain/read_aloud/read_aloud_contracts.dart';
import 'linux_tts_backend.dart';
import 'read_aloud_engine.dart';

/// Linux desktop Speech Dispatcher engine.
///
/// `flutter_tts` does not declare Linux support in this project. This engine
/// talks to the user's `spd-say` executable instead, keeping Linux process and
/// voice details outside the global read-aloud Authority.
class LinuxReadAloudEngine implements ReadAloudEngine {
  LinuxReadAloudEngine({LinuxTtsBackend? backend})
      : _backend = backend ?? createLinuxTtsBackend();

  static const String unavailableReasonCode = 'linux_tts_unavailable';

  final LinuxTtsBackend _backend;
  ReadAloudCapability _capability = const ReadAloudCapability.unavailable(
    reasonCode: unavailableReasonCode,
    message: '正在检测 Linux Speech Dispatcher（spd-say）……',
  );
  bool _initialized = false;
  int _generation = 0;
  double _rate = 0.5;
  double _pitch = 1.0;
  double _volume = 0.9;
  String? _language;

  void Function()? _onComplete;
  void Function()? _onStart;
  void Function(Object error)? _onError;

  @override
  ReadAloudCapability get capability => _capability;

  @override
  bool get isInitialized => _initialized;

  @override
  set onComplete(void Function()? handler) => _onComplete = handler;

  @override
  set onStart(void Function()? handler) => _onStart = handler;

  @override
  set onCancel(void Function()? handler) {}

  @override
  set onError(void Function(Object error)? handler) => _onError = handler;

  @override
  Future<void> initialize() async {
    if (_initialized || _capability.supported) return;
    try {
      if (!await _backend.isAvailable()) {
        _markUnavailable(
          'Linux 未检测到 spd-say。请安装 speech-dispatcher，并确认已配置语音模块。',
        );
        return;
      }
      _capability = const ReadAloudCapability.available(supportsPause: false);
      _initialized = true;
    } catch (error) {
      _markUnavailable('Linux Speech Dispatcher 不可用：$error', cause: error);
    }
  }

  @override
  Future<void> configure({
    double? rate,
    double? pitch,
    double? volume,
    String? language,
  }) async {
    if (!_capability.supported) return;
    if (rate != null) _rate = rate.clamp(0.0, 1.0);
    if (pitch != null) _pitch = pitch.clamp(0.5, 2.0);
    if (volume != null) _volume = volume.clamp(0.0, 1.0);
    if (language != null && language.isNotEmpty) _language = language;
  }

  @override
  Future<List<String>> availableLanguages() async {
    if (!_capability.supported) return const <String>[];
    try {
      return await _backend.availableLanguages();
    } catch (_) {
      return const <String>[];
    }
  }

  @override
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    if (!_capability.supported) {
      throw const ReadAloudEngineException(
        'read aloud backend unavailable',
        code: ReadAloudErrorCode.engineUnavailable,
      );
    }
    if (!_initialized) await initialize();
    if (!_capability.supported) {
      throw const ReadAloudEngineException(
        'read aloud backend unavailable',
        code: ReadAloudErrorCode.engineUnavailable,
      );
    }
    final generation = ++_generation;
    try {
      _onStart?.call();
      await _backend.speak(
        text,
        rate: _rate,
        pitch: _pitch,
        volume: _volume,
        language: _language,
      );
      // Keep completion asynchronous. ReadAloudController records its active
      // run immediately after [speak] returns, so a synchronous callback would
      // be discarded as an unbound/late completion.
      if (generation == _generation) {
        Timer.run(() {
          if (generation == _generation) _onComplete?.call();
        });
      }
    } catch (error) {
      if (generation != _generation) return;
      final exception = ReadAloudEngineException('Linux 语音合成失败。', cause: error);
      _onError?.call(exception);
      throw exception;
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    if (!_capability.supported) return;
    await _backend.stop();
  }

  @override
  Future<bool> pause() async => false;

  @override
  Future<bool> resume() async => false;

  @override
  void dispose() {
    _generation++;
    _backend.dispose();
    _onComplete = null;
    _onStart = null;
    _onError = null;
  }

  void _markUnavailable(String message, {Object? cause}) {
    _initialized = false;
    _capability = ReadAloudCapability.unavailable(
      reasonCode: unavailableReasonCode,
      message: message,
    );
    _onError?.call(ReadAloudEngineException(message, cause: cause));
  }
}
