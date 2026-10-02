import '../../domain/read_aloud/read_aloud_contracts.dart';
import '../../domain/tts/tts_errors.dart';
import '../../domain/tts/tts_models.dart';
import '../../domain/tts/tts_voices.dart';
import '../tts/neural/neural_audio_player.dart';
import '../tts/neural/neural_tts_engine.dart';
import 'read_aloud_engine.dart';

/// Optional capability implemented by engines that can route between the system
/// backend and a local neural backend.
///
/// Keeping this separate from [ReadAloudEngine] means the system engines and all
/// existing fakes stay unchanged, and the read-aloud authority only needs an
/// `is` check to use voice routing when it is available.
abstract class ReadAloudVoiceAwareEngine {
  /// Selects the voice target for subsequent [ReadAloudEngine.speak] calls.
  /// Returns the backend that will actually be attempted.
  Future<TtsBackendKind> selectVoice(ReadAloudVoiceTarget? target);

  /// The backend used by the most recent [ReadAloudEngine.speak].
  TtsBackendKind get activeBackend;

  /// Notified when a neural request had to fall back to system TTS, so the
  /// authority can surface a single, localized notice per session.
  set onVoiceFallback(void Function(TtsErrorCode code)? handler);
}

/// Resolves a model id to its on-disk runtime paths.
typedef NeuralModelPathResolver = NeuralTtsModelPaths? Function(String modelId);

/// The single engine the read-aloud authority talks to.
///
/// It routes each utterance to either the system backend or the neural backend
/// based on the resolved voice target. Every neural failure degrades to the
/// system backend without interrupting the current session, so system TTS
/// remains a reliable default.
class RoutedReadAloudEngine
    implements ReadAloudEngine, ReadAloudVoiceAwareEngine {
  RoutedReadAloudEngine({
    required ReadAloudEngine systemEngine,
    NeuralTtsEngine Function()? neuralEngineFactory,
    NeuralAudioPlayer Function()? audioPlayerFactory,
    NeuralModelPathResolver? modelPaths,
  })  : _system = systemEngine,
        _neuralFactory = neuralEngineFactory,
        _audioFactory = audioPlayerFactory,
        _modelPaths = modelPaths {
    _system.onComplete = () {
      if (_activeBackend == TtsBackendKind.system) _onComplete?.call();
    };
    _system.onStart = () {
      if (_activeBackend == TtsBackendKind.system) _onStart?.call();
    };
    _system.onCancel = () {
      if (_activeBackend == TtsBackendKind.system) _onCancel?.call();
    };
    _system.onError = (error) {
      if (_activeBackend == TtsBackendKind.system) _onError?.call(error);
    };
  }

  final ReadAloudEngine _system;
  final NeuralTtsEngine Function()? _neuralFactory;
  final NeuralAudioPlayer Function()? _audioFactory;
  final NeuralModelPathResolver? _modelPaths;

  NeuralTtsEngine? _neural;
  NeuralAudioPlayer? _audio;
  bool _audioCallbacksBound = false;

  ReadAloudVoiceTarget? _target;
  TtsBackendKind _activeBackend = TtsBackendKind.system;
  double _rate = 0.5;
  double _volume = 0.9;
  double _neuralSpeed = 1.0;
  bool _neuralInitialized = false;
  final Set<String> _neuralFailedModels = <String>{};

  void Function()? _onComplete;
  void Function()? _onStart;
  void Function()? _onCancel;
  void Function(Object error)? _onError;
  void Function(TtsErrorCode code)? _onVoiceFallback;

  @override
  ReadAloudCapability get capability => _system.capability;

  @override
  bool get isInitialized => _system.isInitialized;

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

  /// Whether neural routing is configured at all. The neural engine and audio
  /// player are created lazily on first use, so building the engine never
  /// touches native/platform audio.
  bool get hasNeuralEngine => _neuralFactory != null && _audioFactory != null;

  NeuralTtsEngine? _neuralEngine() {
    final factory = _neuralFactory;
    if (factory == null) return null;
    return _neural ??= factory();
  }

  NeuralAudioPlayer? _audioPlayer() {
    final factory = _audioFactory;
    if (factory == null) return null;
    final player = _audio ??= factory();
    if (!_audioCallbacksBound) {
      _audioCallbacksBound = true;
      player.onComplete = () {
        if (_activeBackend == TtsBackendKind.neural) _onComplete?.call();
      };
      player.onError = (error) {
        if (_activeBackend == TtsBackendKind.neural) {
          _handleNeuralFailure(TtsErrorCode.audioPlaybackFailed, error);
        }
      };
    }
    return player;
  }

  @override
  Future<void> initialize() => _system.initialize();

  @override
  Future<List<String>> availableLanguages() => _system.availableLanguages();

  @override
  Future<void> configure({
    double? rate,
    double? pitch,
    double? volume,
    String? language,
  }) async {
    if (rate != null) {
      _rate = rate.clamp(0.0, 1.0);
      _neuralSpeed = (0.6 + 0.8 * _rate).clamp(0.5, 1.6);
    }
    if (volume != null) _volume = volume.clamp(0.0, 1.0);
    await _system.configure(
      rate: rate,
      pitch: pitch,
      volume: volume,
      language: language,
    );
  }

  @override
  Future<TtsBackendKind> selectVoice(ReadAloudVoiceTarget? target) async {
    _target = target;
    if (target == null || !target.isNeural || !hasNeuralEngine) {
      _activeBackend = TtsBackendKind.system;
      return TtsBackendKind.system;
    }
    return TtsBackendKind.neural;
  }

  @override
  Future<void> speak(String text) async {
    final target = _target;
    if (target == null || !target.isNeural || !hasNeuralEngine) {
      _activeBackend = TtsBackendKind.system;
      await _system.speak(text);
      return;
    }
    await _speakNeural(text, target);
  }

  Future<void> _speakNeural(String text, ReadAloudVoiceTarget target) async {
    final modelId = target.modelId;
    if (modelId == null) {
      await _fallbackToSystem(text, TtsErrorCode.modelUnavailable);
      return;
    }
    if (_neuralFailedModels.contains(modelId)) {
      // Already reported once this session: fall back silently so the user is
      // not notified on every segment.
      await _fallbackToSystem(
        text,
        TtsErrorCode.modelUnavailable,
        notify: false,
      );
      return;
    }
    final paths = _modelPaths?.call(modelId);
    if (paths == null) {
      await _fallbackToSystem(text, TtsErrorCode.modelUnavailable);
      return;
    }
    final neural = _neuralEngine();
    final audio = _audioPlayer();
    if (neural == null || audio == null) {
      await _fallbackToSystem(text, TtsErrorCode.neuralRuntimeUnavailable);
      return;
    }
    try {
      if (!_neuralInitialized) {
        await neural.initialize();
        _neuralInitialized = true;
      }
      await neural.loadModel(paths);
      final result = await neural.synthesize(
        text: text,
        speakerId: target.speakerId ?? 0,
        speed: _neuralSpeed,
      );
      if (result.isEmpty) {
        throw const TtsException(TtsErrorCode.neuralGenerationFailed);
      }
      await audio.initialize();
      _activeBackend = TtsBackendKind.neural;
      _onStart?.call();
      await audio.play(result.samples, result.sampleRate, volume: _volume);
    } on TtsException catch (error) {
      if (error.code == TtsErrorCode.cancelled) rethrow;
      // A model that fails repeatedly in this session is remembered so we stop
      // trying (and stop notifying) on every subsequent segment.
      _neuralFailedModels.add(modelId);
      await _fallbackToSystem(text, error.code);
    } catch (error) {
      _neuralFailedModels.add(modelId);
      await _fallbackToSystem(text, TtsErrorCode.neuralGenerationFailed);
    }
  }

  Future<void> _fallbackToSystem(
    String text,
    TtsErrorCode code, {
    bool notify = true,
  }) async {
    _activeBackend = TtsBackendKind.system;
    if (notify) _onVoiceFallback?.call(code);
    await _system.speak(text);
  }

  void _handleNeuralFailure(TtsErrorCode code, Object error) {
    final target = _target;
    if (target?.modelId != null) _neuralFailedModels.add(target!.modelId!);
    _onVoiceFallback?.call(code);
    // An audio error after playback started cannot be recovered by re-speaking
    // here (the authority owns sequencing); report it so it can advance.
    _onError?.call(
      ReadAloudEngineException('audio playback failed', cause: error),
    );
  }

  @override
  Future<void> stop() async {
    await _system.stop();
    if (_activeBackend == TtsBackendKind.neural) {
      try {
        await _neural?.stop();
        await _audio?.stop();
      } catch (_) {
        // Stopping must never throw to the authority.
      }
    } else {
      // Also stop any leftover neural audio defensively.
      try {
        await _audio?.stop();
      } catch (_) {
        // ignore
      }
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
    _system.onComplete = null;
    _system.onStart = null;
    _system.onCancel = null;
    _system.onError = null;
    _system.dispose();
    _audio?.onComplete = null;
    _audio?.onError = null;
    _audio?.dispose();
    _neural?.dispose();
    _audio = null;
    _neural = null;
  }
}
