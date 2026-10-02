import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lt_dialogue/domain/tts/tts_errors.dart';
import 'package:lt_dialogue/domain/tts/tts_models.dart';
import 'package:lt_dialogue/services/tts/neural/neural_audio_player.dart';
import 'package:lt_dialogue/services/tts/neural/neural_tts_engine.dart';
import 'package:lt_dialogue/services/tts/tts_archive_extractor.dart';
import 'package:lt_dialogue/services/tts/tts_download_client.dart';

/// In-memory neural engine used by tests. No native bindings are touched.
class FakeNeuralTtsEngine implements NeuralTtsEngine {
  FakeNeuralTtsEngine({this.failOnSynthesize = false});

  bool failOnSynthesize;
  bool initializeCalled = false;
  int initializeCount = 0;
  final List<String> loadedModelIds = <String>[];
  final List<int> synthesizedSpeakers = <int>[];
  final List<String> synthesizedTexts = <String>[];
  int synthesizeAttempts = 0;
  int stopCount = 0;
  bool disposed = false;
  String? _loadedModelId;

  @override
  bool get isInitialized => _loadedModelId != null;

  @override
  String? get loadedModelId => _loadedModelId;

  @override
  Future<void> initialize() async {
    initializeCalled = true;
    initializeCount++;
  }

  @override
  Future<void> loadModel(NeuralTtsModelPaths paths) async {
    if (_loadedModelId == paths.modelId) return;
    loadedModelIds.add(paths.modelId);
    _loadedModelId = paths.modelId;
  }

  @override
  Future<NeuralSynthesisResult> synthesize({
    required String text,
    required int speakerId,
    double speed = 1.0,
    double silenceScale = 0.2,
  }) async {
    if (failOnSynthesize) {
      synthesizeAttempts++;
      throw const TtsException(TtsErrorCode.neuralGenerationFailed);
    }
    synthesizeAttempts++;
    synthesizedSpeakers.add(speakerId);
    synthesizedTexts.add(text);
    return NeuralSynthesisResult(
      samples: Float32List.fromList(<double>[0.1, -0.1, 0.2]),
      sampleRate: 24000,
    );
  }

  @override
  Future<void> stop() async => stopCount++;

  @override
  Future<void> dispose() async => disposed = true;
}

/// In-memory audio player that completes asynchronously.
class FakeNeuralAudioPlayer implements NeuralAudioPlayer {
  bool initializeCalled = false;
  int playCount = 0;
  int stopCount = 0;
  bool disposed = false;
  Float32List? lastSamples;
  int? lastSampleRate;
  double? lastVolume;

  void Function()? _onComplete;
  void Function(Object error)? _onError;

  @override
  bool get isInitialized => initializeCalled;

  @override
  set onComplete(void Function()? handler) => _onComplete = handler;

  @override
  set onError(void Function(Object error)? handler) => _onError = handler;

  /// Simulates natural playback completion.
  void emitComplete() => _onComplete?.call();

  /// Simulates a playback error.
  void emitError(Object error) => _onError?.call(error);

  @override
  Future<void> initialize() async => initializeCalled = true;

  @override
  Future<void> play(
    Float32List samples,
    int sampleRate, {
    double volume = 1.0,
  }) async {
    playCount++;
    lastSamples = samples;
    lastSampleRate = sampleRate;
    lastVolume = volume;
  }

  @override
  Future<void> stop() async => stopCount++;

  @override
  Future<bool> pause() async => true;

  @override
  Future<bool> resume() async => true;

  @override
  Future<void> dispose() async => disposed = true;
}

/// Deterministic fake downloader. Never touches the network.
class FakeTtsDownloadClient implements TtsDownloadClient {
  FakeTtsDownloadClient({
    required this.payload,
    this.failStatus,
    this.chunkSize = 4096,
    this.delayPerChunk = Duration.zero,
  });

  final Uint8List payload;
  final int? failStatus;
  final int chunkSize;
  final Duration delayPerChunk;

  int requestCount = 0;
  final List<Uri> requestedUris = <Uri>[];

  @override
  Future<TtsDownloadOutcome> download({
    required Uri uri,
    required File destination,
    required int expectedTotalBytes,
    required TtsProgressCallback onProgress,
    required bool Function() isCancelled,
  }) async {
    requestCount++;
    requestedUris.add(uri);
    if (failStatus != null) {
      throw TtsException(
        TtsErrorCode.modelDownloadFailed,
        detail: 'HTTP $failStatus',
      );
    }
    var offset = await destination.exists() ? await destination.length() : 0;
    if (offset > payload.length) offset = 0;
    final resumed = offset > 0;
    final sink = destination.openWrite(
      mode: resumed ? FileMode.append : FileMode.write,
    );
    var received = offset;
    onProgress(received, payload.length);
    try {
      for (var i = offset; i < payload.length; i += chunkSize) {
        if (isCancelled()) {
          await sink.close();
          throw const TtsException(TtsErrorCode.cancelled);
        }
        final end = math.min(i + chunkSize, payload.length);
        sink.add(payload.sublist(i, end));
        received = end;
        onProgress(received, payload.length);
        if (delayPerChunk > Duration.zero) {
          await Future<void>.delayed(delayPerChunk);
        }
      }
      await sink.close();
    } on TtsException {
      await sink.close().catchError((_) {});
      rethrow;
    }
    return TtsDownloadOutcome(
      bytesWritten: received,
      resumed: resumed,
      totalBytes: payload.length,
    );
  }

  @override
  Future<void> close() async {}
}

/// Fake extractor that materializes the files a model install expects.
class FakeTtsArchiveExtractor implements TtsArchiveExtractor {
  const FakeTtsArchiveExtractor({this.traversal = false});

  final bool traversal;

  @override
  Future<void> extract({
    required File archive,
    required TtsArchiveFormat format,
    required Directory destinationDir,
  }) async {
    if (traversal) {
      // Write outside the staging root to simulate an unsafe archive.
      final outside = File('${destinationDir.parent.path}/escaped.txt');
      await outside.writeAsString('escaped');
      throw const TtsException(TtsErrorCode.modelArchiveInvalid);
    }
    final root = Directory('${destinationDir.path}/payload');
    await root.create(recursive: true);
    await File('${root.path}/tokens.txt').writeAsString('tokens');
    await File('${root.path}/voices.bin').writeAsString('voices');
    await Directory('${root.path}/espeak-ng-data').create(recursive: true);
    await File('${root.path}/model.onnx').writeAsString('model');
    await File('${root.path}/model.int8.onnx').writeAsString('model-int8');
  }
}
