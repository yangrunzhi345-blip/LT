import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/read_aloud/read_aloud_contracts.dart';
import '../../domain/tts/tts_errors.dart';
import '../../domain/tts/tts_models.dart';
import '../../domain/tts/tts_voices.dart';
import '../tts/neural/neural_audio_player.dart';
import '../tts/neural/neural_tts_engine.dart';
import 'read_aloud_engine.dart';

/// Optional voice routing capability of the global read-aloud engine.
abstract class ReadAloudVoiceAwareEngine {
  Future<TtsBackendKind> selectVoice(ReadAloudVoiceTarget? target);

  /// Delivers an immutable voice/text pair instead of sharing selection state.
  Future<void> speakWithVoice(String text, ReadAloudVoiceTarget? target,
      {String? systemLanguage});

  /// Resets failures remembered for the previous session.
  void beginSession();

  TtsBackendKind get activeBackend;
  set onVoiceFallback(void Function(TtsErrorCode code)? handler);
}

typedef NeuralModelPathResolver = NeuralTtsModelPaths? Function(String modelId);

/// Routes utterances while invalidating all work belonging to a replaced one.
class RoutedReadAloudEngine
    implements ReadAloudEngine, ReadAloudVoiceAwareEngine {
  RoutedReadAloudEngine({
    required ReadAloudEngine systemEngine,
    NeuralTtsEngine Function()? neuralEngineFactory,
    NeuralAudioPlayer Function()? audioPlayerFactory,
    NeuralModelPathResolver? modelPaths,
    bool Function()? neuralAvailable,
  })  : _system = systemEngine,
        _neuralFactory = neuralEngineFactory,
        _audioFactory = audioPlayerFactory,
        _modelPaths = modelPaths,
        _neuralAvailable = neuralAvailable;

  final ReadAloudEngine _system;
  final NeuralTtsEngine Function()? _neuralFactory;
  final NeuralAudioPlayer Function()? _audioFactory;
  final NeuralModelPathResolver? _modelPaths;
  final bool Function()? _neuralAvailable;
  NeuralTtsEngine? _neural;
  NeuralAudioPlayer? _audio;
  ReadAloudVoiceTarget? _target;
  String? _requestedModelId;
  TtsBackendKind _activeBackend = TtsBackendKind.system;
  double _volume = 0.9;
  double _neuralSpeed = 1;
  int _operation = 0;
  bool _disposed = false;
  Future<void> _stops = Future<void>.value();
  final Set<String> _neuralFailedModels = <String>{};
  final Set<String> _releasingModels = <String>{};

  void Function()? _onComplete;
  void Function()? _onStart;
  void Function()? _onCancel;
  void Function(Object error)? _onError;
  void Function(TtsErrorCode code)? _onVoiceFallback;

  @override
  ReadAloudCapability get capability => hasNeuralEngine &&
          (_activeBackend == TtsBackendKind.neural ||
              (_neuralAvailable?.call() ?? false))
      ? ReadAloudCapability.available(
          supportsPause: _activeBackend == TtsBackendKind.neural ||
              _system.capability.supportsPause)
      : _system.capability;

  /// System availability is independent of an installed, enabled neural model.
  ReadAloudCapability get systemCapability => _system.capability;
  @override
  bool get isInitialized =>
      _system.isInitialized ||
      (hasNeuralEngine && (_neuralAvailable?.call() ?? false)) ||
      _neural?.isInitialized == true;
  @override
  TtsBackendKind get activeBackend => _activeBackend;
  @override
  set onVoiceFallback(void Function(TtsErrorCode code)? handler) =>
      _onVoiceFallback = handler;
  @override
  set onComplete(void Function()? handler) => _onComplete = handler;
  @override
  set onStart(void Function()? handler) => _onStart = handler;
  @override
  set onCancel(void Function()? handler) => _onCancel = handler;
  @override
  set onError(void Function(Object error)? handler) => _onError = handler;

  bool get hasNeuralEngine => _neuralFactory != null && _audioFactory != null;
  bool _isCurrent(int operation) => !_disposed && operation == _operation;

  @override
  Future<void> initialize() => _system.initialize();
  @override
  Future<List<String>> availableLanguages() => _system.availableLanguages();

  @override
  Future<void> configure(
      {double? rate, double? pitch, double? volume, String? language}) async {
    if (rate != null) {
      _neuralSpeed = (0.6 + 0.8 * rate.clamp(0.0, 1.0)).clamp(0.5, 1.6);
    }
    if (volume != null) _volume = volume.clamp(0.0, 1.0);
    if (_system.isInitialized && _system.capability.supported) {
      await _system.configure(
          rate: rate, pitch: pitch, volume: volume, language: language);
    }
  }

  @override
  void beginSession() => _neuralFailedModels.clear();

  @override
  Future<TtsBackendKind> selectVoice(ReadAloudVoiceTarget? target) async {
    _target = target;
    return target?.isNeural == true && hasNeuralEngine
        ? TtsBackendKind.neural
        : TtsBackendKind.system;
  }

  @override
  Future<void> speak(String text) => speakWithVoice(text, _target);

  @override
  Future<void> speakWithVoice(String text, ReadAloudVoiceTarget? target,
      {String? systemLanguage}) async {
    if (_disposed) return;
    final operation = ++_operation;
    final complete = _onComplete;
    final start = _onStart;
    final cancel = _onCancel;
    final error = _onError;
    final fallback = _onVoiceFallback;
    _target = target;
    _requestedModelId = target?.modelId;
    _system.onComplete = null;
    _system.onCancel = null;
    _system.onError = null;
    _audio?.onComplete = null;
    _audio?.onError = null;
    await _stopBackends();
    if (!_isCurrent(operation)) return;

    void bindSystem() {
      _activeBackend = TtsBackendKind.system;
      _system.onComplete = () {
        if (_isCurrent(operation)) complete?.call();
      };
      _system.onStart = () {
        if (_isCurrent(operation)) start?.call();
      };
      _system.onCancel = () {
        if (_isCurrent(operation)) cancel?.call();
      };
      _system.onError = (failure) {
        if (_isCurrent(operation)) error?.call(failure);
      };
    }

    Future<void> speakSystem([TtsErrorCode? code]) async {
      if (!_isCurrent(operation)) return;
      if (!_system.capability.supported) {
        throw const ReadAloudEngineException('System speech unavailable',
            code: ReadAloudErrorCode.engineUnavailable);
      }
      bindSystem();
      if (code != null) fallback?.call(code);
      if (systemLanguage != null) {
        await _system.configure(language: systemLanguage);
        if (!_isCurrent(operation)) return;
      }
      await _system.speak(text);
    }

    final modelId = target?.modelId;
    if (target?.isNeural != true || !hasNeuralEngine) {
      await speakSystem();
      return;
    }
    if (modelId == null || _releasingModels.contains(modelId)) {
      await speakSystem(TtsErrorCode.modelUnavailable);
      return;
    }
    if (_neuralFailedModels.contains(modelId)) {
      await speakSystem();
      return;
    }
    final paths = _modelPaths?.call(modelId);
    if (paths == null) {
      await speakSystem(TtsErrorCode.modelUnavailable);
      return;
    }
    final neural = _neural ??= _neuralFactory!();
    final audio = _audio ??= _audioFactory!();
    var fallingBack = false;
    // A playback-stream error occurs after play() returned. Recover the same
    // utterance through the system backend; its completion still owns sequencing.
    audio.onComplete = () {
      if (_isCurrent(operation) && !fallingBack) complete?.call();
    };
    audio.onError = (failure) {
      if (!_isCurrent(operation) || fallingBack) return;
      fallingBack = true;
      _neuralFailedModels.add(modelId);
      unawaited(() async {
        try {
          await audio.stop();
          if (_isCurrent(operation)) {
            await speakSystem(TtsErrorCode.audioPlaybackFailed);
          }
        } catch (systemError) {
          if (_isCurrent(operation)) error?.call(systemError);
        }
      }());
    };
    try {
      final speakerId = target?.speakerId ?? 0;
      if (speakerId < 0 || speakerId >= paths.speakerCount) {
        throw const TtsException(TtsErrorCode.voiceUnavailable);
      }
      if (!neural.isInitialized) await neural.initialize();
      if (!_isCurrent(operation)) return;
      await neural.loadModel(paths);
      if (!_isCurrent(operation)) return;
      final result = await neural.synthesize(
          text: text, speakerId: speakerId, speed: _neuralSpeed);
      if (!_isCurrent(operation)) return;
      if (result.isEmpty) {
        throw const TtsException(TtsErrorCode.neuralGenerationFailed);
      }
      await audio.initialize();
      if (!_isCurrent(operation)) return;
      _activeBackend = TtsBackendKind.neural;
      start?.call();
      await audio.play(result.samples, result.sampleRate, volume: _volume);
    } catch (failure) {
      if (!_isCurrent(operation) || fallingBack) return;
      if (failure is TtsException && failure.code == TtsErrorCode.cancelled) {
        cancel?.call();
        return;
      }
      _neuralFailedModels.add(modelId);
      await audio.stop();
      if (!_isCurrent(operation)) return;
      await speakSystem(failure is TtsException
          ? failure.code
          : TtsErrorCode.neuralGenerationFailed);
    }
  }

  Future<void> _stopBackends() {
    final neural = _neural;
    final audio = _audio;
    final stopped = _stops.then((_) async {
      // Independent failures must not prevent stopping the other backends.
      for (final stop in <Future<void> Function()>[
        _system.stop,
        if (neural != null) neural.stop,
        if (audio != null) audio.stop,
      ]) {
        try {
          await stop();
        } catch (error) {
          debugPrint('[ReadAloud] Backend stop failed: $error');
        }
      }
    });
    _stops = stopped;
    return stopped;
  }

  @override
  Future<void> stop() {
    _operation++;
    _activeBackend = TtsBackendKind.system;
    _system.onComplete = null;
    _system.onCancel = null;
    _system.onError = null;
    _audio?.onComplete = null;
    _audio?.onError = null;
    return _stopBackends();
  }

  /// Stops and frees a model before the install authority removes its files.
  Future<void> releaseModel(String modelId) async {
    _neuralFailedModels.remove(modelId);
    if (_requestedModelId != modelId && _neural?.loadedModelId != modelId) {
      return;
    }
    _releasingModels.add(modelId);
    final neural = _neural;
    final stopping = stop();
    final operation = _operation;
    // Detach the captured runtime now: another model may start while native
    // teardown waits for an already running inference to finish.
    _neural = null;
    try {
      await stopping;
      if (_isCurrent(operation)) {
        _requestedModelId = null;
        _onCancel?.call();
      }
      await neural?.dispose();
    } finally {
      _releasingModels.remove(modelId);
    }
  }

  @override
  Future<bool> pause() async {
    if (_activeBackend == TtsBackendKind.neural) {
      return await _audio?.pause() ?? false;
    }
    return _system.pause();
  }

  @override
  Future<bool> resume() async {
    if (_activeBackend == TtsBackendKind.neural) {
      return await _audio?.resume() ?? false;
    }
    return _system.resume();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _operation++;
    _activeBackend = TtsBackendKind.system;
    _system.onComplete = null;
    _system.onStart = null;
    _system.onCancel = null;
    _system.onError = null;
    _system.dispose();
    _audio?.onComplete = null;
    _audio?.onError = null;
    final audio = _audio;
    final neural = _neural;
    _audio = null;
    _neural = null;
    unawaited(audio?.dispose().catchError((Object error) {
          debugPrint('[ReadAloud] Audio dispose failed: $error');
        }) ??
        Future<void>.value());
    unawaited(neural?.dispose().catchError((Object error) {
          debugPrint('[ReadAloud] Neural dispose failed: $error');
        }) ??
        Future<void>.value());
  }
}
