import 'package:flutter_test/flutter_test.dart';
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
