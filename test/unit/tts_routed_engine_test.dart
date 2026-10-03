import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/read_aloud/read_aloud_contracts.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_controller.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_engine.dart';
import 'package:lt_dialogue/domain/tts/tts_errors.dart';
import 'package:lt_dialogue/domain/tts/tts_models.dart';
import 'package:lt_dialogue/domain/tts/tts_voices.dart';
import 'package:lt_dialogue/services/read_aloud/routed_read_aloud_engine.dart';
import 'package:lt_dialogue/services/tts/neural/neural_tts_engine.dart';

import '../helpers/read_aloud_fakes.dart';
import '../helpers/tts_fakes.dart';

NeuralTtsModelPaths _paths() => const NeuralTtsModelPaths(
      modelId: 'test-model',
      modelPath: '/tmp/model.onnx',
      voicesPath: '/tmp/voices.bin',
      tokensPath: '/tmp/tokens.txt',
      dataDirPath: '/tmp/espeak-ng-data',
      lexicon: '',
      speakerCount: 4,
    );

ReadAloudVoiceTarget _target(int speakerId) => ReadAloudVoiceTarget(
      backend: TtsBackendKind.neural,
      capabilities: TtsVoiceCapabilities.kokoro,
      voiceId: 'family:s$speakerId',
      modelId: 'test-model',
      speakerId: speakerId,
    );

RoutedReadAloudEngine _engine(
  FakeReadAloudEngine system,
  FakeNeuralTtsEngine neural,
  FakeNeuralAudioPlayer audio, {
  bool hasPaths = true,
}) {
  return RoutedReadAloudEngine(
    systemEngine: system,
    neuralEngineFactory: () => neural,
    audioPlayerFactory: () => audio,
    modelPaths: (id) => hasPaths && id == 'test-model' ? _paths() : null,
  );
}

void main() {
  group('RoutedReadAloudEngine cancellation regressions', () {
    test('should discard inference completed after stop', () async {
      final system = FakeReadAloudEngine();
      final neural = _GatedNeuralEngine();
      final audio = FakeNeuralAudioPlayer();
      final engine = _engine(system, neural, audio);
      addTearDown(engine.dispose);
      await engine.selectVoice(_target(1));
      final speaking = engine.speak('old');
      await neural.started.future;
      await engine.stop();
      neural.gate.complete();
      await speaking;
      expect(audio.playCount, 0);
      expect(system.spokenTexts, isEmpty);
      expect(neural.stopCount, greaterThan(0));
    });

    test('should stop neural audio when switching to system', () async {
      final system = FakeReadAloudEngine();
      final neural = FakeNeuralTtsEngine();
      final audio = FakeNeuralAudioPlayer();
      final engine = _engine(system, neural, audio);
      addTearDown(engine.dispose);
      await engine.selectVoice(_target(1));
      await engine.speak('neural');
      final stops = audio.stopCount;
      await engine.selectVoice(null);
      await engine.speak('system');
      expect(audio.stopCount, greaterThan(stops));
      expect(system.spokenTexts, ['system']);
    });

    test('should preserve new session after a delayed stop finishes', () async {
      final system = _DelayedStopEngine();
      final controller = ReadAloudController(
        engine: system,
        initialPreferences: const ReadAloudPreferences(enabled: true),
      );
      addTearDown(controller.dispose);
      await controller.playText('old', sourceId: 'A');
      final stopGate = Completer<void>();
      system.stopGate = stopGate;
      final stopping = controller.stop();
      await controller.playText('new', sourceId: 'B');
      stopGate.complete();
      await stopping;
      expect(controller.state.sourceId, 'B');
      expect(controller.state.status, ReadAloudStatus.playing);
    });

    test('should bind new text to its own voice while old inference is pending',
        () async {
      final system = FakeReadAloudEngine();
      final neural = _GatedNeuralEngine();
      final audio = FakeNeuralAudioPlayer();
      final engine = _engine(system, neural, audio);
      final controller = ReadAloudController(
        engine: engine,
        initialPreferences: const ReadAloudPreferences(enabled: true),
      );
      addTearDown(controller.dispose);
      final old =
          controller.playText('old', sourceId: 'A', voiceOverride: _target(1));
      await neural.started.future;
      final newer =
          controller.playText('new', sourceId: 'B', voiceOverride: _target(2));
      await settleReadAloud();
      neural.gate.complete();
      await Future.wait([old, newer]);
      expect(audio.playCount, 1);
      expect(neural.synthesizedSpeakers.last, 2);
      expect(controller.state.sourceId, 'B');
    });
  });
  group('RoutedReadAloudEngine lifecycle and capability', () {
    test('should retry a failed model in the next session', () async {
      final system = FakeReadAloudEngine();
      final neural = FakeNeuralTtsEngine(failOnSynthesize: true);
      final audio = FakeNeuralAudioPlayer();
      final engine = _engine(system, neural, audio);
      addTearDown(engine.dispose);
      engine.beginSession();
      await engine.speakWithVoice('first', _target(1));
      await engine.speakWithVoice('second', _target(1));
      expect(neural.synthesizeAttempts, 1);
      neural.failOnSynthesize = false;
      engine.beginSession();
      await engine.speakWithVoice('new session', _target(2));
      expect(audio.playCount, 1);
      expect(neural.synthesizeAttempts, 2);
    });

    test('should stop active controller and release its model', () async {
      final system = FakeReadAloudEngine();
      final neural = FakeNeuralTtsEngine();
      final audio = FakeNeuralAudioPlayer();
      final engine = _engine(system, neural, audio);
      final controller = ReadAloudController(
          engine: engine,
          initialPreferences: const ReadAloudPreferences(enabled: true));
      addTearDown(controller.dispose);
      await controller.playText('active',
          sourceId: 'A', voiceOverride: _target(1));
      await engine.releaseModel('test-model');
      expect(neural.disposed, isTrue);
      expect(controller.state.status, ReadAloudStatus.stopped);
      expect(audio.stopCount, greaterThan(0));
    });

    test('should retain another session started during model release',
        () async {
      final system = _DelayedStopEngine();
      final neural = FakeNeuralTtsEngine();
      final audio = FakeNeuralAudioPlayer();
      final engine = _engine(system, neural, audio);
      final controller = ReadAloudController(
          engine: engine,
          initialPreferences: const ReadAloudPreferences(enabled: true));
      addTearDown(controller.dispose);
      await controller.playText('active',
          sourceId: 'A', voiceOverride: _target(1));
      final gate = Completer<void>();
      system.stopGate = gate;
      final release = engine.releaseModel('test-model');
      final newer = controller.playText('system', sourceId: 'B');
      gate.complete();
      await Future.wait([release, newer]);
      expect(neural.disposed, isTrue);
      expect(controller.state.status, ReadAloudStatus.playing);
      expect(controller.state.sourceId, 'B');
    });

    test('should recover asynchronous audio failure through system playback',
        () async {
      final system = FakeReadAloudEngine();
      final neural = FakeNeuralTtsEngine();
      final audio = FakeNeuralAudioPlayer();
      final engine = _engine(system, neural, audio);
      final controller = ReadAloudController(
          engine: engine,
          initialPreferences: const ReadAloudPreferences(enabled: true));
      addTearDown(controller.dispose);
      await controller.playText('active',
          sourceId: 'A', voiceOverride: _target(1));
      audio.emitError(StateError('lost audio device'));
      await settleReadAloud();
      expect(system.spokenTexts, ['active']);
      expect(controller.state.activeBackend, TtsBackendKind.system);
      expect(controller.state.currentVoiceId, isNull);
      system.emitComplete();
      expect(controller.state.status, ReadAloudStatus.completed);
    });

    test(
        'should support installed enabled neural without claiming system exists',
        () async {
      final system = FakeReadAloudEngine(supported: false);
      final neural = FakeNeuralTtsEngine();
      final audio = FakeNeuralAudioPlayer();
      var enabledAndInstalled = false;
      final engine = RoutedReadAloudEngine(
          systemEngine: system,
          neuralEngineFactory: () => neural,
          audioPlayerFactory: () => audio,
          modelPaths: (_) => _paths(),
          neuralAvailable: () => enabledAndInstalled);
      final controller = ReadAloudController(
          engine: engine,
          initialPreferences: const ReadAloudPreferences(enabled: true));
      addTearDown(controller.dispose);
      expect(controller.capability.supported, isFalse);
      enabledAndInstalled = true;
      controller.refreshCapability();
      expect(controller.capability.supported, isTrue);
      expect(controller.systemCapability.supported, isFalse);
      await controller.playText('active',
          sourceId: 'A', voiceOverride: _target(1));
      expect(audio.playCount, 1);
      expect(controller.capability.supportsPause, isTrue);
      await controller.pause();
      expect(controller.state.status, ReadAloudStatus.paused);
      await controller.resume();
      expect(controller.state.status, ReadAloudStatus.playing);
      await controller.stop();
      enabledAndInstalled = false;
      controller.refreshCapability();
      expect(controller.capability.supported, isFalse);
    });

    test('should apply neural rate and volume without initializing system',
        () async {
      final system = FakeReadAloudEngine(supported: false)..initialized = false;
      final neural = FakeNeuralTtsEngine();
      final audio = FakeNeuralAudioPlayer();
      final engine = RoutedReadAloudEngine(
          systemEngine: system,
          neuralEngineFactory: () => neural,
          audioPlayerFactory: () => audio,
          modelPaths: (_) => _paths(),
          neuralAvailable: () => true);
      final controller = ReadAloudController(
          engine: engine,
          initialPreferences:
              const ReadAloudPreferences(enabled: true, rate: 1, volume: 0.2));
      addTearDown(controller.dispose);
      await controller.playText('active',
          sourceId: 'A', voiceOverride: _target(1));
      expect(audio.lastVolume, 0.2);
      expect(system.configureCount, 0);
      expect(system.initializeCount, 0);
    });

    test('should avoid unsupported system language configuration for neural',
        () async {
      final system = _LanguageConstrainedSystem();
      final neural = FakeNeuralTtsEngine();
      final audio = FakeNeuralAudioPlayer();
      final engine = _engine(system, neural, audio);
      final controller = ReadAloudController(
          engine: engine,
          initialPreferences: const ReadAloudPreferences(enabled: true));
      addTearDown(controller.dispose);
      await controller.init();
      await controller.playText('这是中文。',
          sourceId: 'A', voiceOverride: _target(1));
      expect(audio.playCount, 1);
      expect(system.appliedLanguages, isEmpty);
    });

    test('should report fallback failure when both backends are unavailable',
        () async {
      final system = FakeReadAloudEngine(
          supported: false,
          speakError: const ReadAloudEngineException('unavailable'));
      final neural = FakeNeuralTtsEngine(failOnSynthesize: true);
      final audio = FakeNeuralAudioPlayer();
      final engine = RoutedReadAloudEngine(
          systemEngine: system,
          neuralEngineFactory: () => neural,
          audioPlayerFactory: () => audio,
          modelPaths: (_) => _paths(),
          neuralAvailable: () => true);
      final controller = ReadAloudController(
          engine: engine,
          initialPreferences: const ReadAloudPreferences(enabled: true));
      addTearDown(controller.dispose);
      await controller.playText('active',
          sourceId: 'A', voiceOverride: _target(1));
      expect(controller.state.status, ReadAloudStatus.error);
    });

    test('should not pass invalid speaker IDs to the neural boundary',
        () async {
      final system = FakeReadAloudEngine();
      final neural = FakeNeuralTtsEngine();
      final audio = FakeNeuralAudioPlayer();
      final engine = _engine(system, neural, audio);
      addTearDown(engine.dispose);
      for (final sid in [-1, 4, 999]) {
        engine.beginSession();
        await engine.speakWithVoice('invalid', _target(sid));
      }
      expect(neural.synthesizeAttempts, 0);
      expect(system.spokenTexts, ['invalid', 'invalid', 'invalid']);
    });

    test('should not let delayed fallback pause overwrite a replay', () async {
      final system = _DelayedStopEngine()..supportsPause = false;
      final controller = ReadAloudController(
          engine: system,
          initialPreferences: const ReadAloudPreferences(enabled: true));
      addTearDown(controller.dispose);
      await controller.playText('active', sourceId: 'A');
      final gate = Completer<void>();
      system.stopGate = gate;
      final pausing = controller.pause();
      await controller.replayCurrent();
      gate.complete();
      await pausing;
      expect(controller.state.status, ReadAloudStatus.playing);
    });

    test('should not let delayed end-of-queue next overwrite a replay',
        () async {
      final system = _DelayedStopEngine();
      final controller = ReadAloudController(
          engine: system,
          initialPreferences: const ReadAloudPreferences(enabled: true));
      addTearDown(controller.dispose);
      await controller.playText('active', sourceId: 'A');
      final gate = Completer<void>();
      system.stopGate = gate;
      final completing = controller.next();
      await controller.previous();
      gate.complete();
      await completing;
      expect(controller.state.status, ReadAloudStatus.playing);
    });
  });

  test('system target always uses the system engine', () async {
    final system = FakeReadAloudEngine();
    final neural = FakeNeuralTtsEngine();
    final audio = FakeNeuralAudioPlayer();
    final engine = _engine(system, neural, audio);
    await engine.initialize();

    await engine.selectVoice(null);
    await engine.speak('hello');

    expect(system.spokenTexts, <String>['hello']);
    expect(neural.synthesizedTexts, isEmpty);
    expect(audio.playCount, 0);
    expect(engine.activeBackend, TtsBackendKind.system);
  });

  test('neural target synthesizes and plays, and reuses the loaded model',
      () async {
    final system = FakeReadAloudEngine();
    final neural = FakeNeuralTtsEngine();
    final audio = FakeNeuralAudioPlayer();
    final engine = _engine(system, neural, audio);
    await engine.initialize();

    await engine.selectVoice(_target(1));
    await engine.speak('first');
    await engine.selectVoice(_target(2));
    await engine.speak('second');

    expect(neural.loadedModelIds, <String>['test-model']);
    expect(neural.synthesizedSpeakers, <int>[1, 2]);
    expect(neural.initializeCount, 1);
    expect(audio.playCount, 2);
    expect(audio.lastSampleRate, 24000);
    expect(system.spokenTexts, isEmpty);
    expect(engine.activeBackend, TtsBackendKind.neural);
  });

  test('a missing model falls back to system TTS with one callback', () async {
    final system = FakeReadAloudEngine();
    final neural = FakeNeuralTtsEngine();
    final audio = FakeNeuralAudioPlayer();
    final engine = _engine(system, neural, audio, hasPaths: false);
    final fallbacks = <TtsErrorCode>[];
    engine.onVoiceFallback = fallbacks.add;
    await engine.initialize();

    await engine.selectVoice(_target(1));
    await engine.speak('hello');

    expect(system.spokenTexts, <String>['hello']);
    expect(engine.activeBackend, TtsBackendKind.system);
    expect(fallbacks, <TtsErrorCode>[TtsErrorCode.modelUnavailable]);
  });

  test('synthesis failure falls back and is not retried every segment',
      () async {
    final system = FakeReadAloudEngine();
    final neural = FakeNeuralTtsEngine(failOnSynthesize: true);
    final audio = FakeNeuralAudioPlayer();
    final engine = _engine(system, neural, audio);
    final fallbacks = <TtsErrorCode>[];
    engine.onVoiceFallback = fallbacks.add;
    await engine.initialize();

    await engine.selectVoice(_target(1));
    await engine.speak('first');
    await engine.speak('second');

    expect(system.spokenTexts, <String>['first', 'second']);
    expect(fallbacks, <TtsErrorCode>[TtsErrorCode.neuralGenerationFailed]);
    // The failing model is remembered, so it is not re-loaded/re-tried.
    expect(neural.synthesizeAttempts, 1);
  });

  test('audio playback completion is forwarded to the authority', () async {
    final system = FakeReadAloudEngine();
    final neural = FakeNeuralTtsEngine();
    final audio = FakeNeuralAudioPlayer();
    final engine = _engine(system, neural, audio);
    var completions = 0;
    engine.onComplete = () => completions++;
    await engine.initialize();

    await engine.selectVoice(_target(1));
    await engine.speak('hello');
    audio.emitComplete();

    expect(completions, 1);
  });
}

class _GatedNeuralEngine extends FakeNeuralTtsEngine {
  final started = Completer<void>();
  final gate = Completer<void>();

  @override
  Future<NeuralSynthesisResult> synthesize(
      {required String text,
      required int speakerId,
      double speed = 1,
      double silenceScale = 0.2}) async {
    if (!started.isCompleted) started.complete();
    await gate.future;
    return super.synthesize(
        text: text,
        speakerId: speakerId,
        speed: speed,
        silenceScale: silenceScale);
  }
}

class _DelayedStopEngine extends FakeReadAloudEngine {
  Completer<void>? stopGate;

  @override
  Future<void> stop() async {
    final gate = stopGate;
    stopGate = null;
    await gate?.future;
    await super.stop();
  }
}

class _LanguageConstrainedSystem extends FakeReadAloudEngine {
  _LanguageConstrainedSystem() : super(availableLanguageTags: ['en-US']);
  @override
  Future<void> configure(
      {double? rate, double? pitch, double? volume, String? language}) async {
    if (language != null && language != 'en-US') {
      throw const ReadAloudEngineException('unsupported language');
    }
    await super.configure(
        rate: rate, pitch: pitch, volume: volume, language: language);
  }
}
