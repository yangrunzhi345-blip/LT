import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../../domain/tts/tts_errors.dart';
import 'neural_tts_engine.dart';

/// Serial worker owning the native model, including its acknowledged teardown.
void sherpaTtsWorkerEntry(SendPort mainPort) {
  final commands = ReceivePort();
  mainPort
      .send(<String, Object?>{'type': 'handshake', 'port': commands.sendPort});
  sherpa.OfflineTts? tts;
  String? loadedKey;
  var bindingsReady = false;
  var tail = Future<void>.value();

  Future<void> handle(Object? message) async {
    if (message is! Map) return;
    final requestId = message['requestId'];
    try {
      switch (message['type']) {
        case 'load':
          if (!bindingsReady) {
            await sherpa.initBindingsAsync();
            bindingsReady = true;
          }
          final key = message['cacheKey'] as String;
          if (tts == null || loadedKey != key) {
            tts?.free();
            tts = null;
            loadedKey = null;
            tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(
              model: sherpa.OfflineTtsModelConfig(
                kokoro: sherpa.OfflineTtsKokoroModelConfig(
                  model: message['modelPath'] as String,
                  voices: message['voicesPath'] as String,
                  tokens: message['tokensPath'] as String,
                  dataDir: message['dataDirPath'] as String,
                  lexicon: message['lexicon'] as String? ?? '',
                ),
                numThreads: 2,
                debug: false,
              ),
            ));
            loadedKey = key;
          }
          mainPort.send(<String, Object?>{
            'type': 'loaded',
            'requestId': requestId,
            'speakerCount': tts!.numSpeakers
          });
        case 'synth':
          final engine = tts;
          if (engine == null) {
            throw const TtsException(TtsErrorCode.modelUnavailable);
          }
          if (message['cacheKey'] != loadedKey) {
            throw const TtsException(TtsErrorCode.modelUnavailable);
          }
          final sid = message['sid'] as int;
          if (sid < 0 || sid >= engine.numSpeakers) {
            throw const TtsException(TtsErrorCode.voiceUnavailable);
          }
          final audio = engine.generateWithConfig(
            text: message['text'] as String,
            config: sherpa.OfflineTtsGenerationConfig(
              sid: sid,
              speed: (message['speed'] as num).toDouble(),
              silenceScale: (message['silenceScale'] as num).toDouble(),
            ),
          );
          final samples = audio.samples;
          mainPort.send(<String, Object?>{
            'type': 'audio',
            'requestId': requestId,
            'sampleRate': audio.sampleRate,
            'samples': TransferableTypedData.fromList(<Uint8List>[
              samples.buffer
                  .asUint8List(samples.offsetInBytes, samples.lengthInBytes),
            ]),
          });
        case 'dispose':
          tts?.free();
          tts = null;
          loadedKey = null;
          mainPort.send(
              <String, Object?>{'type': 'disposed', 'requestId': requestId});
          commands.close();
        default:
          throw StateError('unknown worker command');
      }
    } catch (error) {
      mainPort.send(<String, Object?>{
        'type': 'error',
        'requestId': requestId,
        'error': error.toString(),
        'code': error is TtsException
            ? error.code.name
            : TtsErrorCode.neuralGenerationFailed.name
      });
    }
  }

  // An async stream listener alone does not serialize commands: binding startup
  // yields, allowing a second load to allocate and overwrite the first model.
  commands.listen((message) => tail = tail.then((_) => handle(message)));
}

/// Supervises the native worker and rejects results from cancelled operations.
class SherpaOnnxNeuralTtsEngine implements NeuralTtsEngine {
  SherpaOnnxNeuralTtsEngine(
      {Duration? synthesisTimeout,
      Duration? shutdownTimeout,
      void Function(SendPort)? workerEntry})
      : _synthesisTimeout = synthesisTimeout ?? const Duration(seconds: 90),
        _shutdownTimeout = shutdownTimeout ??
            (synthesisTimeout ?? const Duration(seconds: 90)) +
                const Duration(seconds: 125),
        _workerEntry = workerEntry ?? sherpaTtsWorkerEntry;

  final Duration _synthesisTimeout;
  final Duration _shutdownTimeout;
  final void Function(SendPort) _workerEntry;
  Isolate? _isolate;
  ReceivePort? _fromWorker;
  ReceivePort? _errors;
  ReceivePort? _exits;
  SendPort? _toWorker;
  Completer<void>? _handshake;
  Future<void>? _starting;
  Future<void> _loads = Future<void>.value();
  Future<void>? _disposing;
  final Map<int, _PendingRequest> _pending = <int, _PendingRequest>{};
  int _nextRequestId = 1;
  int _generation = 0;
  int _workerGeneration = 0;
  bool _disposed = false;
  NeuralTtsModelPaths? _loadedPaths;
  int? _speakerCount;

  @override
  bool get isInitialized => _toWorker != null;
  @override
  String? get loadedModelId => _loadedPaths?.modelId;

  @override
  Future<void> initialize() async {
    if (_disposed) throw const TtsException(TtsErrorCode.cancelled);
    if (_toWorker != null) return;
    final starting = _starting ??= _startWorker();
    try {
      await starting;
    } finally {
      if (identical(starting, _starting)) _starting = null;
    }
  }

  Future<void> _startWorker() async {
    final generation = ++_workerGeneration;
    final receive = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    final handshake = Completer<void>();
    // Dispose can cancel during Isolate.spawn, before its await installs the
    // handshake error listener. Keep this early completion observed as well.
    handshake.future.ignore();
    _fromWorker = receive;
    _errors = errors;
    _exits = exits;
    _handshake = handshake;
    receive.listen((message) {
      if (generation == _workerGeneration) _handleMessage(message);
    });
    void failed(String reason) {
      if (generation != _workerGeneration) return;
      _invalidateWorker(
          TtsException(TtsErrorCode.neuralRuntimeUnavailable, detail: reason));
    }

    errors.listen((error) => failed('worker error: $error'));
    exits.listen((_) => failed('worker exited'));
    try {
      final isolate = await Isolate.spawn(_workerEntry, receive.sendPort,
          onError: errors.sendPort,
          onExit: exits.sendPort,
          errorsAreFatal: true,
          debugName: 'lt-neural-tts');
      if (_disposed || generation != _workerGeneration) {
        isolate.kill(priority: Isolate.immediate);
        throw TtsException(_disposed
            ? TtsErrorCode.cancelled
            : TtsErrorCode.neuralRuntimeUnavailable);
      }
      _isolate = isolate;
      await handshake.future.timeout(const Duration(seconds: 20));
    } catch (error) {
      if (generation == _workerGeneration) {
        _invalidateWorker(error is TtsException
            ? error
            : TtsException(TtsErrorCode.neuralRuntimeUnavailable,
                cause: error));
      }
      // _invalidateWorker may complete the handshake with an error before spawn
      // returns. Observe it even if this branch did not reach its await above.
      await handshake.future.catchError((Object _) {});
      rethrow;
    }
  }

  @override
  Future<void> loadModel(NeuralTtsModelPaths paths) {
    final generation = _generation;
    final loading = _loads.then((_) async {
      _checkGeneration(generation);
      if (_loadedPaths?.cacheKey == paths.cacheKey) return;
      await initialize();
      _checkGeneration(generation);
      _loadedPaths = null;
      _speakerCount = null;
      await _request(
          'load',
          <String, Object?>{
            'cacheKey': paths.cacheKey,
            'modelPath': paths.modelPath,
            'voicesPath': paths.voicesPath,
            'tokensPath': paths.tokensPath,
            'dataDirPath': paths.dataDirPath,
            'lexicon': paths.lexicon,
          },
          const Duration(seconds: 120));
      _checkGeneration(generation);
      _loadedPaths = paths;
      _speakerCount ??= paths.speakerCount;
    });
    // Observe failure without poisoning the serialization tail for future loads.
    _loads = loading.then((_) {}, onError: (Object _, StackTrace __) {});
    return loading;
  }

  void _checkGeneration(int generation) {
    if (_disposed || generation != _generation) {
      throw const TtsException(TtsErrorCode.cancelled);
    }
  }

  @override
  Future<NeuralSynthesisResult> synthesize(
      {required String text,
      required int speakerId,
      double speed = 1,
      double silenceScale = 0.2}) async {
    if (_disposed) throw const TtsException(TtsErrorCode.cancelled);
    if (text.trim().isEmpty) return NeuralSynthesisResult.empty;
    final paths = _loadedPaths;
    if (paths == null) throw const TtsException(TtsErrorCode.modelUnavailable);
    if (speakerId < 0 || speakerId >= (_speakerCount ?? paths.speakerCount)) {
      throw const TtsException(TtsErrorCode.voiceUnavailable);
    }
    if (!speed.isFinite ||
        speed <= 0 ||
        !silenceScale.isFinite ||
        silenceScale < 0) {
      throw const TtsException(TtsErrorCode.neuralGenerationFailed);
    }
    return _request(
        'synth',
        <String, Object?>{
          'text': text,
          'cacheKey': paths.cacheKey,
          'sid': speakerId,
          'speed': speed,
          'silenceScale': silenceScale
        },
        _synthesisTimeout);
  }

  Future<NeuralSynthesisResult> _request(
      String kind, Map<String, Object?> arguments, Duration timeout) async {
    final requestId = _nextRequestId++;
    final pending = _PendingRequest(kind, _generation);
    _pending[requestId] = pending;
    try {
      final port = _toWorker;
      if (port == null) {
        throw const TtsException(TtsErrorCode.neuralRuntimeUnavailable);
      }
      port.send(<String, Object?>{
        'type': kind,
        'requestId': requestId,
        ...arguments
      });
      return await pending.completer.future.timeout(timeout);
    } on TimeoutException catch (error) {
      final failure = TtsException(TtsErrorCode.neuralRuntimeUnavailable,
          detail: '$kind timeout', cause: error);
      _invalidateWorker(failure);
      throw failure;
    } finally {
      _pending.remove(requestId);
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    for (final entry in _pending.entries.toList()) {
      if (entry.value.kind == 'dispose') continue;
      if (!entry.value.completer.isCompleted) {
        entry.value.completer
            .completeError(const TtsException(TtsErrorCode.cancelled));
      }
      _pending.remove(entry.key);
    }
  }

  @override
  Future<void> dispose() => _disposing ??= _disposeWorker();

  Future<void> _disposeWorker() async {
    _disposed = true;
    await stop();
    final starting = _starting;
    if (starting != null) {
      _invalidateWorker(const TtsException(TtsErrorCode.cancelled));
      try {
        await starting;
      } on TtsException {
        // Startup cancellation already closes ports and its spawned isolate.
      }
    }
    try {
      if (_toWorker != null) {
        await _request('dispose', const <String, Object?>{}, _shutdownTimeout);
      }
    } on TtsException {
      // A dead or hung worker is forcibly shut down after bounded graceful free.
    } finally {
      _invalidateWorker(const TtsException(TtsErrorCode.cancelled));
    }
  }

  void _invalidateWorker(TtsException error) {
    _workerGeneration++;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _toWorker = null;
    _loadedPaths = null;
    _speakerCount = null;
    _fromWorker?.close();
    _errors?.close();
    _exits?.close();
    _fromWorker = null;
    _errors = null;
    _exits = null;
    final handshake = _handshake;
    _handshake = null;
    if (handshake != null && !handshake.isCompleted) {
      handshake.completeError(error);
    }
    for (final pending in _pending.values) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(error);
      }
    }
    _pending.clear();
  }

  void _handleMessage(Object? message) {
    if (message is! Map) return;
    if (message['type'] == 'handshake') {
      _toWorker = message['port'] as SendPort?;
      if (_toWorker != null && _handshake?.isCompleted == false) {
        _handshake!.complete();
      }
      return;
    }
    final pending = _pending[message['requestId']];
    if (pending == null || pending.completer.isCompleted) return;
    if (pending.generation != _generation && pending.kind != 'dispose') {
      pending.completer
          .completeError(const TtsException(TtsErrorCode.cancelled));
      return;
    }
    switch (message['type']) {
      case 'loaded':
        _speakerCount = message['speakerCount'] as int?;
        pending.completer.complete(NeuralSynthesisResult.empty);
      case 'disposed':
        pending.completer.complete(NeuralSynthesisResult.empty);
      case 'audio':
        final data = message['samples'];
        final bytes = data is TransferableTypedData
            ? data.materialize().asUint8List()
            : Uint8List(0);
        pending.completer.complete(NeuralSynthesisResult(
            samples: Float32List.view(
                bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes ~/ 4),
            sampleRate: message['sampleRate'] as int? ?? 0));
      case 'error':
        final name = message['code'];
        final code = TtsErrorCode.values
                .where((value) => value.name == name)
                .firstOrNull ??
            TtsErrorCode.neuralGenerationFailed;
        pending.completer.completeError(
            TtsException(code, detail: message['error'] as String?));
    }
  }
}

class _PendingRequest {
  _PendingRequest(this.kind, this.generation);
  final String kind;
  final int generation;
  final completer = Completer<NeuralSynthesisResult>();
}
