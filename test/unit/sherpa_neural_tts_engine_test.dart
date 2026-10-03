import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/tts/tts_errors.dart';
import 'package:lt_dialogue/services/tts/neural/neural_tts_engine.dart';
import 'package:lt_dialogue/services/tts/neural/sherpa_neural_tts_engine.dart';

NeuralTtsModelPaths _paths(String model) => NeuralTtsModelPaths(
    modelId: model,
    modelPath: '/$model/model.onnx',
    voicesPath: '/$model/voices.bin',
    tokensPath: '/$model/tokens.txt',
    dataDirPath: '/$model/data',
    lexicon: '',
    speakerCount: 103);

void _controlledWorker(SendPort mainPort) {
  final commands = ReceivePort();
  mainPort.send({'type': 'handshake', 'port': commands.sendPort});
  var loadCount = 0;
  commands.listen((message) async {
    final command = message as Map;
    final id = command['requestId'];
    switch (command['type']) {
      case 'load':
        if ((command['modelPath'] as String).contains('crash')) Isolate.exit();
        if ((command['modelPath'] as String).contains('broken')) {
          mainPort.send({
            'type': 'error',
            'requestId': id,
            'code': 'neuralGenerationFailed',
            'error': 'fixture load failure'
          });
          return;
        }
        loadCount++;
        mainPort.send({'type': 'loaded', 'requestId': id, 'speakerCount': 103});
      case 'synth':
        if (command['text'] == 'hang') return;
        final samples = Float32List.fromList(
            [loadCount.toDouble(), (command['sid'] as int).toDouble()]);
        mainPort.send({
          'type': 'audio',
          'requestId': id,
          'sampleRate': 24000,
          'samples':
              TransferableTypedData.fromList([samples.buffer.asUint8List()]),
        });
      case 'dispose':
        // Acknowledgement represents free completing, not merely command send.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        mainPort.send({'type': 'disposed', 'requestId': id});
        commands.close();
    }
  });
}

void _exitingWorker(SendPort mainPort) => Isolate.exit();
void _throwingWorker(SendPort mainPort) => throw StateError('startup failure');

void _silentWorker(SendPort mainPort) {
  final commands = ReceivePort();
  commands.listen((_) {});
}

void main() {
  group('SherpaOnnxNeuralTtsEngine lifecycle', () {
    late SherpaOnnxNeuralTtsEngine engine;
    setUp(() {
      engine = SherpaOnnxNeuralTtsEngine(
          workerEntry: _controlledWorker,
          synthesisTimeout: const Duration(milliseconds: 100));
    });
    tearDown(() => engine.dispose());

    test('should dispose before initialization and allow repeated dispose',
        () async {
      await engine.dispose();
      await engine.dispose();
      expect(engine.isInitialized, isFalse);
    });

    test('should deduplicate concurrent startup and identical model loads',
        () async {
      await Future.wait(
          [engine.initialize(), engine.initialize(), engine.initialize()]);
      await Future.wait(
          [engine.loadModel(_paths('good')), engine.loadModel(_paths('good'))]);
      final result = await engine.synthesize(text: 'hello', speakerId: 0);
      expect(result.samples.first, 1);
      expect(engine.loadedModelId, 'good');
    });

    test('should reload A after switching to a model that fails to load',
        () async {
      await engine.loadModel(_paths('A'));
      await expectLater(
          engine.loadModel(_paths('broken')), throwsA(isA<TtsException>()));
      expect(engine.loadedModelId, isNull);
      await engine.loadModel(_paths('A'));
      final result = await engine.synthesize(text: 'hello', speakerId: 0);
      expect(result.samples.first, 2);
    });

    test('should fail exited worker requests promptly and restart next load',
        () async {
      await expectLater(
          engine.loadModel(_paths('crash')).timeout(const Duration(seconds: 2)),
          throwsA(isA<TtsException>()));
      expect(engine.loadedModelId, isNull);
      await engine.loadModel(_paths('good'));
      expect((await engine.synthesize(text: 'hello', speakerId: 102)).isEmpty,
          isFalse);
    });

    test('should reject out-of-range speakers before sending to worker',
        () async {
      await engine.loadModel(_paths('good'));
      for (final sid in [-1, 103, 999]) {
        await expectLater(
            engine.synthesize(text: 'hello', speakerId: sid),
            throwsA(isA<TtsException>().having(
                (error) => error.code, 'code', TtsErrorCode.voiceUnavailable)));
      }
      for (final sid in [0, 102]) {
        expect(
            (await engine.synthesize(text: 'hello', speakerId: sid))
                .samples
                .last,
            sid);
      }
    });

    test('should resolve pending inference on stop without playback results',
        () async {
      await engine.loadModel(_paths('good'));
      final pending = engine.synthesize(text: 'hang', speakerId: 0);
      final cancelled = expectLater(
          pending,
          throwsA(isA<TtsException>()
              .having((error) => error.code, 'code', TtsErrorCode.cancelled)));
      await engine.stop();
      await cancelled;
      expect((await engine.synthesize(text: 'hello', speakerId: 0)).isEmpty,
          isFalse);
    });

    test('should supervise inference timeout and recover with a fresh worker',
        () async {
      await engine.loadModel(_paths('good'));
      await expectLater(engine.synthesize(text: 'hang', speakerId: 0),
          throwsA(isA<TtsException>()));
      expect(engine.isInitialized, isFalse);
      await engine.loadModel(_paths('good'));
      expect((await engine.synthesize(text: 'hello', speakerId: 0)).isEmpty,
          isFalse);
    });

    test('should await worker free acknowledgement before completing dispose',
        () async {
      await engine.loadModel(_paths('good'));
      final stopwatch = Stopwatch()..start();
      await engine.dispose();
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(15));
      expect(engine.isInitialized, isFalse);
      expect(engine.loadedModelId, isNull);
    });

    for (final worker in [_exitingWorker, _throwingWorker]) {
      test(
          'should supervise worker startup failure before handshake ${worker == _exitingWorker ? "exit" : "throw"}',
          () async {
        final early = SherpaOnnxNeuralTtsEngine(workerEntry: worker);
        await expectLater(
            early.initialize().timeout(const Duration(seconds: 2)),
            throwsA(isA<TtsException>().having((error) => error.code, 'code',
                TtsErrorCode.neuralRuntimeUnavailable)));
        expect(early.isInitialized, isFalse);
        await early.dispose();
      });
    }

    test('should cancel startup that has not produced a handshake', () async {
      final silent = SherpaOnnxNeuralTtsEngine(workerEntry: _silentWorker);
      final starting = silent.initialize();
      final cancelled = expectLater(starting, throwsA(isA<TtsException>()));
      await silent.dispose().timeout(const Duration(seconds: 2));
      await cancelled;
    });
  });
}
