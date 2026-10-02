/// Pure data contracts for the optional neural TTS subsystem.
///
/// This layer describes models, voices and installation state. It has no
/// Flutter / IO / network dependency, so presentation can reference it without
/// touching `lib/services/**`.
library;

import 'tts_errors.dart';

/// Which synthesis backend should read a given segment.
enum TtsBackendKind {
  /// The built-in system TTS (flutter_tts / Linux Speech Dispatcher).
  /// Always available and always the default.
  system,

  /// A user-downloaded local neural model (sherpa-onnx).
  neural,
}

/// The real, per-voice control surface of a backend.
///
/// UI must only expose controls that the active voice/engine truly supports.
/// The system TTS supports pitch; not every neural model does, and faking
/// success would be a lie.
class TtsVoiceCapabilities {
  const TtsVoiceCapabilities({
    required this.supportsRate,
    required this.supportsPitch,
    required this.supportsVolume,
    required this.supportsLanguageOverride,
  });

  /// System TTS exposes rate, pitch, volume and language selection.
  static const TtsVoiceCapabilities system = TtsVoiceCapabilities(
    supportsRate: true,
    supportsPitch: true,
    supportsVolume: true,
    supportsLanguageOverride: true,
  );

  /// Kokoro controls rate (length scale) and volume; it does not expose pitch
  /// and its language follows the text, not a per-utterance override.
  static const TtsVoiceCapabilities kokoro = TtsVoiceCapabilities(
    supportsRate: true,
    supportsPitch: false,
    supportsVolume: true,
    supportsLanguageOverride: false,
  );

  final bool supportsRate;
  final bool supportsPitch;
  final bool supportsVolume;
  final bool supportsLanguageOverride;
}

/// A single required file (or directory) inside a model archive.
class TtsFileSpec {
  const TtsFileSpec({required this.name, this.sizeBytes});

  /// Path relative to the model root, using `/` separators.
  final String name;

  /// Expected size, when the official source publishes one.
  final int? sizeBytes;
}

/// Integrity metadata attached to a model release.
class TtsModelIntegrity {
  const TtsModelIntegrity({
    required this.algorithm,
    required this.digest,
    required this.source,
  });

  /// Copies the release digest published by the official source.
  const TtsModelIntegrity.officialSha256(this.digest)
      : algorithm = 'sha256',
        source = TtsIntegritySource.official;

  /// A digest computed locally after download, when no official digest exists.
  const TtsModelIntegrity.localSha256(this.digest)
      : algorithm = 'sha256',
        source = TtsIntegritySource.local;

  static const String algorithmSha256 = 'sha256';

  final String algorithm;

  /// Lower-case hex digest.
  final String digest;

  final TtsIntegritySource source;
}

/// Whether a digest came from the official release or was computed locally.
enum TtsIntegritySource { official, local }

/// Archive container format supported by the installer.
enum TtsArchiveFormat { tarBz2, tarGz, zip }

/// Immutable description of a downloadable neural TTS model.
///
/// The catalog only ever contains descriptors whose download URL, size and
/// digest have been verified against the official sherpa-onnx release. Nothing
/// here is guessed.
class TtsModelDescriptor {
  const TtsModelDescriptor({
    required this.modelId,
    required this.version,
    required this.displayName,
    required this.engineFamily,
    required this.voiceFamily,
    required this.languages,
    required this.speakerCount,
    required this.downloadUri,
    required this.downloadSizeBytes,
    required this.license,
    required this.licenseUri,
    required this.archiveFormat,
    required this.requiredFiles,
    required this.modelFileName,
    required this.capabilities,
    required this.integrity,
    this.installSizeBytes,
    this.lexiconFileNames = const <String>[],
  });

  /// Stable model identity (e.g. `kokoro-int8-multi-lang-v1_1`).
  final String modelId;

  /// Model release version (e.g. `v1_1`).
  final String version;

  /// Human display name. Dynamic content: never used as an i18n key.
  final String displayName;

  /// sherpa-onnx engine family (`kokoro`, future: `vits`, `piper`, ...).
  final String engineFamily;

  /// Voice family shared by compatible model releases / quantizations. Voices
  /// are identified by `voiceFamily` + speaker, so a binding survives
  /// re-downloading a compatible release (e.g. int8 vs fp32 v1_1).
  final String voiceFamily;

  /// Normalized BCP-47 language tags this model can speak.
  final List<String> languages;

  /// Number of speakers exposed by the model.
  final int speakerCount;

  /// Official HTTPS download URL.
  final Uri downloadUri;

  /// Exact compressed download size advertised by the release.
  final int downloadSizeBytes;

  /// Approximate installed on-disk size, when known.
  final int? installSizeBytes;

  /// License identifier (e.g. `Apache-2.0`).
  final String license;

  /// Optional license URL.
  final Uri? licenseUri;

  final TtsArchiveFormat archiveFormat;

  /// Files that must exist after extraction for the install to be valid.
  final List<TtsFileSpec> requiredFiles;

  /// Accepted ONNX model file names (first match wins).
  final List<String> modelFileName;

  /// Lexicon files used for G2P, if any (relative to the model root).
  final List<String> lexiconFileNames;

  final TtsVoiceCapabilities capabilities;

  final TtsModelIntegrity integrity;

  /// `modelId/version`, the stable install directory key.
  String get installKey => '$modelId/$version';
}

/// Installation lifecycle state of a catalog model.
enum TtsModelInstallState {
  notInstalled,
  downloading,
  paused,
  verifying,
  installing,
  installed,
  failed,
  updateAvailable,
}

/// Immutable snapshot of a model's installation progress.
class TtsModelInstallStatus {
  const TtsModelInstallStatus({
    required this.modelId,
    required this.state,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.errorCode,
  });

  const TtsModelInstallStatus.notInstalled(this.modelId)
      : state = TtsModelInstallState.notInstalled,
        downloadedBytes = 0,
        totalBytes = 0,
        errorCode = null;

  final String modelId;
  final TtsModelInstallState state;
  final int downloadedBytes;
  final int totalBytes;

  /// Stable failure category; technical detail stays inside the manager.
  final TtsErrorCode? errorCode;

  bool get isInstalled => state == TtsModelInstallState.installed;

  bool get isBusy =>
      state == TtsModelInstallState.downloading ||
      state == TtsModelInstallState.verifying ||
      state == TtsModelInstallState.installing;

  /// Progress in the range 0..1, or null when the total size is unknown.
  double? get progress {
    if (totalBytes <= 0) return null;
    final value = downloadedBytes / totalBytes;
    return value.clamp(0.0, 1.0);
  }

  TtsModelInstallStatus copyWith({
    TtsModelInstallState? state,
    int? downloadedBytes,
    int? totalBytes,
    TtsErrorCode? errorCode,
    bool clearError = false,
  }) {
    return TtsModelInstallStatus(
      modelId: modelId,
      state: state ?? this.state,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
    );
  }
}
