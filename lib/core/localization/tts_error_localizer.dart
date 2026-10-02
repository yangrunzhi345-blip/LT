import '../../domain/tts/tts_errors.dart';
import '../../l10n/generated/app_localizations.dart';

/// Maps a stable [TtsErrorCode] to localized user copy.
///
/// Technical detail (URLs, status codes, paths) never reaches the UI.
String localizeTtsError(AppLocalizations l10n, TtsErrorCode? code) {
  switch (code) {
    case TtsErrorCode.modelDownloadFailed:
      return l10n.ttsErrorModelDownloadFailed;
    case TtsErrorCode.modelIntegrityFailed:
      return l10n.ttsErrorModelIntegrityFailed;
    case TtsErrorCode.modelArchiveInvalid:
      return l10n.ttsErrorModelArchiveInvalid;
    case TtsErrorCode.modelInstallFailed:
      return l10n.ttsErrorModelInstallFailed;
    case TtsErrorCode.modelUnavailable:
      return l10n.ttsErrorModelUnavailable;
    case TtsErrorCode.voiceUnavailable:
      return l10n.ttsErrorVoiceUnavailable;
    case TtsErrorCode.neuralRuntimeUnavailable:
      return l10n.ttsErrorNeuralRuntimeUnavailable;
    case TtsErrorCode.neuralGenerationFailed:
      return l10n.ttsErrorNeuralGenerationFailed;
    case TtsErrorCode.audioPlaybackFailed:
      return l10n.ttsErrorAudioPlaybackFailed;
    case TtsErrorCode.insufficientStorage:
      return l10n.ttsErrorInsufficientStorage;
    case TtsErrorCode.networkUnavailable:
      return l10n.ttsErrorNetworkUnavailable;
    case TtsErrorCode.cancelled:
      return l10n.ttsErrorCancelled;
    case null:
      return l10n.ttsErrorNeuralGenerationFailed;
  }
}

/// Formats a byte count into a short human string (e.g. `147 MB`).
///
/// Kept dependency-free and locale-neutral: the unit suffix is part of a
/// numeric measurement, not a translatable sentence.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final rounded = value >= 100 || unit == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$rounded ${units[unit]}';
}
