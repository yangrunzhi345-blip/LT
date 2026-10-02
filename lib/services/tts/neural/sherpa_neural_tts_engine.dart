import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../../domain/tts/tts_errors.dart';
import 'neural_tts_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Worker isolate
//
// sherpa-onnx inference is synchronous native work. To keep the Flutter UI
// responsive it runs entirely inside this dedicated worker isolate, which owns
// the loaded model for the lifetime of the session.
// ─────────────────────────────────────────────────────────────────────────────

/// Entry point of the neural TTS worker isolate.
///
/// Must be top-level so it can be used with [Isolate.spawn]. Each isolate has
/// its own FFI binding state, so bindings are initialized here.
void sherpaTtsWorkerEntry(SendPort mainPort) {
  final commandPort = ReceivePort();
  mainPort.send(<String, Object?>{
    'type': 'handshake',
    'port': commandPort.sendPort,
  });

  sherpa.OfflineTts? tts;
  String? loadedKey;
  var bindingsReady = false;

  Future<sherpa.OfflineTts> ensureBindings() async {
    if (!bindingsReady) {
      await sherpa.initBindingsAsync();
      bindingsReady = true;
    }
    final current = tts;
    if (current == null) {
      throw StateError('model not loaded');
    }
    return current;
  }

  commandPort.listen((message) async {
    if (message is! Map) return;
    final type = message['type'];
    final requestId = message['requestId'];
    try {
      switch (type) {
        case 'load':
          if (!bindingsReady) {
            await sherpa.initBindingsAsync();
            bindingsReady = true;
          }
          final key = message['cacheKey'] as String;
          if (tts != null && loadedKey == key) {
            mainPort.send(<String, Object?>{
              'type': 'loaded',
              'requestId': requestId,
              'ok': true,
            });
            return;
          }
          tts?.free();
          tts = null;
          final config = sherpa.OfflineTtsConfig(
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
          );
          tts = sherpa.OfflineTts(config);
          loadedKey = key;
          mainPort.send(<String, Object?>{
            'type': 'loaded',
            'requestId': requestId,
            'ok': true,
          });
        case 'synth':
          final engine = await ensureBindings();
          final audio = engine.generateWithConfig(
            text: message['text'] as String,
            config: sherpa.OfflineTtsGenerationConfig(
              sid: message['sid'] as int? ?? 0,
              speed: (message['speed'] as num?)?.toDouble() ?? 1.0,
              silenceScale:
                  (message['silenceScale'] as num?)?.toDouble() ?? 0.2,
            ),
          );
          final samples = audio.samples;
          mainPort.send(<String, Object?>{
            'type': 'audio',
            'requestId': requestId,
            'sampleRate': audio.sampleRate,
            'samples': TransferableTypedData.fromList(<Uint8List>[
              samples.buffer.asUint8List(
                samples.offsetInBytes,
                samples.lengthInBytes,
              ),
            ]),
          });
        case 'dispose':
          tts?.free();
          tts = null;
          loadedKey = null;
          commandPort.close();
        default:
          mainPort.send(<String, Object?>{
            'type': 'error',
            'requestId': requestId,
            'error': 'unknown command',
          });
      }
    } catch (error) {
      mainPort.send(<String, Object?>{
        'type': 'error',
        'requestId': requestId,
        'error': error.toString(),
      });
    }
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Main-isolate facade
// ─────────────────────────────────────────────────────────────────────────────

/// sherpa-onnx implementation of [NeuralTtsEngine].
///
/// This file is the single place in the app allowed to import
/// `package:sherpa_onnx`. An architecture test enforces the boundary.
class SherpaOnnxNeuralTtsEngine implements NeuralTtsEngine {
  SherpaOnnxNeuralTtsEngine({Duration? synthesisTimeout})
      : _synthesisTimeout = synthesisTimeout ?? const Duration(seconds: 90);

  final Duration _synthesisTimeout;

  Isolate? _isolate;
  ReceivePort? _fromWorker;
  SendPort? _toWorker;
  final Completer<SendPort> _handshake = Completer<SendPort>();
  final Map<int, _PendingRequest> _pending = <int, _PendingRequest>{};
  int _nextRequestId = 1;
  int _generation = 0;
  bool _disposed = false;
  String? _loadedModelId;
  Object? _lastError;

  @override
  bool get isInitialized => _isolate != null && _loadedModelId != null;

  @override
  String? get loadedModelId => _loadedModelId;

  @override
  Future<void> initialize() async {
    if (_disposed) return;
    if (_isolate != null) {
      await _handshake.future;
      return;
    }
    final receive = ReceivePort();
    _fromWorker = receive;
    receive.listen(_handleMessage);
    try {
      _isolate = await Isolate.spawn(
        sherpaTtsWorkerEntry,
        receive.sendPort,
        debugName: 'lt-neural-tts',
      );
    } catch (error) {
      _lastError = error;
      throw TtsException(
        TtsErrorCode.neuralRuntimeUnavailable,
        cause: error,
      );
    }
    await _handshake.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw const TtsException(
        TtsErrorCode.neuralRuntimeUnavailable,
        detail: 'worker handshake timeout',
      ),
    );
  }

  @override
  Future<void> loadModel(NeuralTtsModelPaths paths) async {
    if (_disposed) return;
    if (_loadedModelId == paths.modelId) return;
    await initialize();
    final requestId = _nextRequestId++;
    final pending = _PendingRequest('load', _generation);
    _pending[requestId] = pending;
    _send(<String, Object?>{
      'type': 'load',
      'requestId': requestId,
      'cacheKey': paths.cacheKey,
      'modelPath': paths.modelPath,
      'voicesPath': paths.voicesPath,
      'tokensPath': paths.tokensPath,
      'dataDirPath': paths.dataDirPath,
      'lexicon': paths.lexicon,
    });
    await pending.completer.future.timeout(
      const Duration(seconds: 120),
      onTimeout: () {
        _pending.remove(requestId);
        throw const TtsException(
          TtsErrorCode.neuralRuntimeUnavailable,
          detail: 'model load timeout',
        );
      },
    );
    _loadedModelId = paths.modelId;
  }

  @override
  Future<NeuralSynthesisResult> synthesize({
    required String text,
    required int speakerId,
    double speed = 1.0,
    double silenceScale = 0.2,
  }) async {
    if (_disposed || text.trim().isEmpty) return NeuralSynthesisResult.empty;
    if (_loadedModelId == null) {
      throw const TtsException(TtsErrorCode.modelUnavailable);
    }
    final requestId = _nextRequestId++;
    final pending = _PendingRequest('synth', _generation);
    _pending[requestId] = pending;
    _send(<String, Object?>{
      'type': 'synth',
      'requestId': requestId,
      'text': text,
      'sid': speakerId,
      'speed': speed,
      'silenceScale': silenceScale,
    });
    try {
      return await pending.completer.future.timeout(_synthesisTimeout);
    } on TimeoutException {
      throw const TtsException(
        TtsErrorCode.neuralGenerationFailed,
        detail: 'synthesis timeout',
      );
    } finally {
      _pending.remove(requestId);
    }
  }

  @override
  Future<void> stop() async {
    // Native inference cannot be aborted mid-call without threads inside the
    // worker, so we discard its result instead: the generation bump makes any
    // late audio resolve to nothing.
    _generation++;
    for (final entry in _pending.entries.toList()) {
      if (entry.value.kind == 'synth' && !entry.value.completer.isCompleted) {
        entry.value.completer.complete(NeuralSynthesisResult.empty);
        _pending.remove(entry.key);
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _send(<String, Object?>{'type': 'dispose'});
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _fromWorker?.close();
    _fromWorker = null;
    _toWorker = null;
    _failAllPending('disposed');
  }

  void _send(Map<String, Object?> message) {
    final port = _toWorker;
    if (port == null) {
      throw TtsException(
        TtsErrorCode.neuralRuntimeUnavailable,
        detail:
            'worker unavailable${_lastError == null ? '' : ': $_lastError'}',
      );
    }
    port.send(message);
  }

  void _handleMessage(Object? message) {
    if (message is! Map) return;
    final type = message['type'];
    if (type == 'handshake') {
      _toWorker = message['port'] as SendPort?;
      if (!_handshake.isCompleted && _toWorker != null) {
        _handshake.complete(_toWorker);
      }
      return;
    }
    final requestId = message['requestId'];
    if (requestId is! int) return;
    final pending = _pending[requestId];
    switch (type) {
      case 'loaded':
        pending?.completer.complete(NeuralSynthesisResult.empty);
      case 'audio':
        final data = message['samples'];
        if (pending == null || pending.completer.isCompleted) return;
        if (pending.generation != _generation) {
          // Late result from a stopped generation: drop it.
          pending.completer.complete(NeuralSynthesisResult.empty);
          return;
        }
        final bytes = data is TransferableTypedData
            ? data.materialize().asUint8List()
            : Uint8List(0);
        final samples = Float32List.view(
          bytes.buffer,
          bytes.offsetInBytes,
          bytes.lengthInBytes ~/ 4,
        );
        pending.completer.complete(
          NeuralSynthesisResult(
            samples: samples,
            sampleRate: (message['sampleRate'] as int?) ?? 0,
          ),
        );
      case 'error':
        pending?.completer.completeError(
          TtsException(
            TtsErrorCode.neuralGenerationFailed,
            detail: message['error'] as String?,
          ),
        );
    }
  }

  void _failAllPending(String reason) {
    for (final pending in _pending.values) {
      if (pending.completer.isCompleted) continue;
      if (pending.kind == 'synth') {
        pending.completer.complete(NeuralSynthesisResult.empty);
      } else {
        pending.completer.completeError(
          TtsException(
            TtsErrorCode.neuralRuntimeUnavailable,
            detail: reason,
          ),
        );
      }
    }
    _pending.clear();
  }
}

class _PendingRequest {
  _PendingRequest(this.kind, this.generation);

  final String kind;
  final int generation;
  final Completer<NeuralSynthesisResult> completer =
      Completer<NeuralSynthesisResult>();
}
