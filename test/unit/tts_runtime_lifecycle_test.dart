import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:lt_dialogue/domain/read_aloud/read_aloud_contracts.dart';
import 'package:lt_dialogue/domain/tts/tts_models.dart';
import 'package:lt_dialogue/domain/tts/tts_voices.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_controller.dart';
import 'package:lt_dialogue/services/repositories/settings_repository.dart';
import 'package:lt_dialogue/services/tts/neural/neural_tts_engine.dart';
import 'package:lt_dialogue/services/tts/tts_model_catalog.dart';
import 'package:lt_dialogue/services/tts/tts_runtime.dart';

import '../helpers/read_aloud_fakes.dart';
import '../helpers/tts_fakes.dart';

class _MockSettingsRepository extends Mock implements ISettingsRepository {}

class _PendingNeuralEngine extends FakeNeuralTtsEngine {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<NeuralSynthesisResult> synthesize(
      {required String text,
      required int speakerId,
      double speed = 1,
      double silenceScale = 0.2}) async {
    started.complete();
    await release.future;
    return super.synthesize(
        text: text,
        speakerId: speakerId,
        speed: speed,
        silenceScale: silenceScale);
  }
}

void main() {
  group('TtsRuntime production model deletion hook', () {
    late Directory directory;
    late TtsModelCatalog catalog;
    late Uint8List payload;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('lt-runtime-delete-');
      payload = Uint8List.fromList(List<int>.generate(32, (index) => index));
      final digest = SHA256Digest()
          .process(payload)
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      catalog = TtsModelCatalog(models: [
        TtsModelDescriptor(
          modelId: 'test-model',
          version: 'v1',
          displayName: 'Fixture',
          engineFamily: 'kokoro',
          voiceFamily: 'test-family',
          languages: const ['zh-CN'],
          speakerCount: 4,
          downloadUri: Uri.parse('https://example.invalid/model.tar.bz2'),
          downloadSizeBytes: payload.length,
          license: 'Apache-2.0',
          licenseUri: null,
          archiveFormat: TtsArchiveFormat.tarBz2,
          requiredFiles: const [
            TtsFileSpec(name: 'tokens.txt'),
            TtsFileSpec(name: 'voices.bin'),
            TtsFileSpec(name: 'espeak-ng-data')
          ],
          modelFileName: const ['model.onnx'],
          capabilities: TtsVoiceCapabilities.kokoro,
          integrity: TtsModelIntegrity.officialSha256(digest),
        )
      ]);
    });
    tearDown(() => directory.delete(recursive: true));

    TtsRuntime runtime(
            FakeNeuralTtsEngine neural, FakeNeuralAudioPlayer audio) =>
        TtsRuntime.production(
            settingsRepo: _MockSettingsRepository(),
            rootProvider: () async => directory,
            catalog: catalog,
            systemEngineFactory: FakeReadAloudEngine.new,
            neuralEngineFactory: () => neural,
            audioPlayerFactory: () => audio,
            downloadClientFactory: () =>
                FakeTtsDownloadClient(payload: payload),
            extractor: const FakeTtsArchiveExtractor());

    const target = ReadAloudVoiceTarget(
        backend: TtsBackendKind.neural,
        capabilities: TtsVoiceCapabilities.kokoro,
        modelId: 'test-model',
        speakerId: 0,
        voiceId: 'test-family:s0');

    test('should stop playback and free the runtime before deleting its files',
        () async {
      final neural = FakeNeuralTtsEngine();
      final audio = FakeNeuralAudioPlayer();
      final production = runtime(neural, audio);
      final controller = ReadAloudController(
          engine: production.engine,
          initialPreferences: const ReadAloudPreferences(enabled: true));
      addTearDown(() {
        controller.dispose();
        production.dispose();
      });
      await production.manager.download('test-model');
      final modelFile =
          File(production.manager.installed('test-model')!.modelPath);
      await controller.playText('active story',
          sourceId: 'story', voiceOverride: target);
      expect(audio.playCount, 1);
      await production.manager.delete('test-model');
      expect(neural.disposed, isTrue);
      expect(controller.state.status, ReadAloudStatus.stopped);
      expect(await modelFile.exists(), isFalse);
      expect(production.manager.isModelInstalled('test-model'), isFalse);
    });

    test('should stop preparing and discard inference completed after deletion',
        () async {
      final neural = _PendingNeuralEngine();
      final audio = FakeNeuralAudioPlayer();
      final production = runtime(neural, audio);
      final controller = ReadAloudController(
          engine: production.engine,
          initialPreferences: const ReadAloudPreferences(enabled: true));
      addTearDown(() {
        controller.dispose();
        production.dispose();
      });
      await production.manager.download('test-model');
      final reading = controller.playText('active story',
          sourceId: 'story', voiceOverride: target);
      await neural.started.future;
      expect(controller.state.status, ReadAloudStatus.preparing);
      await production.manager.delete('test-model');
      expect(controller.state.status, ReadAloudStatus.stopped);
      neural.release.complete();
      await reading;
      expect(audio.playCount, 0);
      expect(neural.disposed, isTrue);
    });
  });
}
