import 'dart:typed_data';

/// Resolved on-disk paths for a loaded neural model.
class NeuralTtsModelPaths {
  const NeuralTtsModelPaths({
    required this.modelId,
    required this.modelPath,
    required this.voicesPath,
    required this.tokensPath,
    required this.dataDirPath,
    required this.lexicon,
    required this.speakerCount,
  });

  final String modelId;
  final String modelPath;
  final String voicesPath;
  final String tokensPath;
  final String dataDirPath;

  /// Comma-separated lexicon paths (may be empty).
  final String lexicon;

  final int speakerCount;

  /// Cache key: two requests with the same key reuse the loaded model.
  String get cacheKey => modelId;
}

/// Synthesized audio: mono float samples in `[-1, 1]` plus the sample rate.
class NeuralSynthesisResult {
  const NeuralSynthesisResult({
    required this.samples,
    required this.sampleRate,
  });

  static final NeuralSynthesisResult empty =
      NeuralSynthesisResult(samples: Float32List(0), sampleRate: 0);

  final Float32List samples;
  final int sampleRate;

  bool get isEmpty => samples.isEmpty || sampleRate <= 0;
}

/// A local neural TTS backend (sherpa-onnx).
///
/// This is the *only* boundary allowed to touch `package:sherpa_onnx`. The
/// read-aloud authority talks to it through the routing engine; UI, providers
/// and controllers never import sherpa directly.
///
/// Implementations must not block the Flutter UI isolate: real synthesis runs
/// on a dedicated worker isolate. They must also cache the loaded model and
/// only switch the speaker id when the model is unchanged.
abstract class NeuralTtsEngine {
  bool get isInitialized;

  /// Prepares native bindings. Safe to call repeatedly.
  Future<void> initialize();

  /// Loads (or reuses) [paths]. Switching speakers of the same model must NOT
  /// reload the model.
  Future<void> loadModel(NeuralTtsModelPaths paths);

  /// The model id currently loaded, if any.
  String? get loadedModelId;

  /// Generates audio. Returns empty audio on an empty input.
  Future<NeuralSynthesisResult> synthesize({
    required String text,
    required int speakerId,
    double speed = 1.0,
    double silenceScale = 0.2,
  });

  /// Discards any in-flight result. Native inference already running completes
  /// but its result is dropped.
  Future<void> stop();

  Future<void> dispose();
}
