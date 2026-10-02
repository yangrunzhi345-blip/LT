/// Stable, localizable failure categories for the neural TTS subsystem.
///
/// Infrastructure code stores the technical detail inside [TtsException.detail]
/// (or `cause`) for diagnostics. Presentation must never render raw exceptions,
/// URLs or filesystem paths; it maps [TtsErrorCode] to localized copy.
enum TtsErrorCode {
  /// The model download request failed (network / non-2xx / timeout).
  modelDownloadFailed,

  /// The downloaded archive did not match the expected digest / size.
  modelIntegrityFailed,

  /// The archive could not be decoded, or contained an unsafe entry.
  modelArchiveInvalid,

  /// Verification passed but installation (move / rename) failed.
  modelInstallFailed,

  /// The model the user selected is not installed.
  modelUnavailable,

  /// The requested voice does not exist in the installed model.
  voiceUnavailable,

  /// The neural runtime (sherpa-onnx bindings) could not be initialized.
  neuralRuntimeUnavailable,

  /// Inference failed while generating audio.
  neuralGenerationFailed,

  /// The generated audio could not be played.
  audioPlaybackFailed,

  /// There is not enough free disk space to download / install the model.
  insufficientStorage,

  /// The network is unreachable.
  networkUnavailable,

  /// The user cancelled the operation.
  cancelled,
}

/// Typed exception raised by the neural TTS subsystem.
///
/// [detail] is a machine/diagnostic string (HTTP status, path, native message).
/// It is intentionally kept out of user-visible UI state.
class TtsException implements Exception {
  const TtsException(this.code, {this.detail, this.cause});

  final TtsErrorCode code;
  final String? detail;
  final Object? cause;

  @override
  String toString() =>
      'TtsException(${code.name})${detail == null ? '' : ': $detail'}';
}
