import '../../domain/errors/app_error.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../domain/read_aloud/read_aloud_contracts.dart';

/// Maps a typed failure to safe user-facing copy.
String localizeAppError(AppLocalizations l10n, AppDomainError error) {
  final p = error.parameters;
  switch (error.code) {
    case AppErrorCode.timeout:
      return l10n.errorRequestTimeout;
    case AppErrorCode.networkUnavailable:
      return l10n.errorNetworkUnavailable;
    case AppErrorCode.unauthorized:
      return l10n.errorUnauthorized;
    case AppErrorCode.paymentRequired:
      return l10n.errorPaymentRequired;
    case AppErrorCode.forbidden:
      return l10n.errorForbidden;
    case AppErrorCode.notFound:
      return l10n.errorNotFound;
    case AppErrorCode.rateLimited:
      return l10n.errorRateLimited;
    case AppErrorCode.serverError:
      return l10n.errorUnknown;
    case AppErrorCode.invalidRequest:
      return l10n.errorInvalidRequest;
    case AppErrorCode.resourceCapacityExceeded:
      return l10n.resourceErrorCapacityExceeded(
        (p['current'] as num?)?.toInt() ?? 0,
        (p['limit'] as num?)?.toInt() ?? 0,
      );
    case AppErrorCode.resourceValidationFailed:
      return l10n.resourceErrorValidationFailed(
        p['details']?.toString() ?? l10n.errorUnknown,
      );
    case AppErrorCode.resourceGenerationFailed:
      return l10n.resourceErrorGenerationFailed;
    case AppErrorCode.resourceConflict:
      return l10n.resourceErrorConflict;
    case AppErrorCode.adventureAssetMissing:
      return l10n.adventureErrorAssetMissing(
        p['name']?.toString() ?? l10n.resourceUnnamed,
      );
    case AppErrorCode.adventureAssetStale:
      return l10n.adventureErrorAssetStale(
        p['name']?.toString() ?? l10n.resourceUnnamed,
      );
    case AppErrorCode.ttsUnsupported:
      return l10n.ttsErrorUnsupported;
    case AppErrorCode.ttsEngineUnavailable:
      return l10n.ttsErrorEngineUnavailable;
    case AppErrorCode.ttsVoiceUnavailable:
      return l10n.ttsErrorVoiceUnavailable;
    case AppErrorCode.ttsPlaybackFailed:
      return l10n.ttsErrorPlaybackFailed;
    case AppErrorCode.unknown:
      return l10n.errorUnknown;
  }
}

/// Converts arbitrary failures to the safe generic presentation error.
AppDomainError asAppDomainError(Object error, [StackTrace? stackTrace]) {
  if (error is AppDomainError) return error;
  return AppDomainError(
    code: AppErrorCode.unknown,
    debugMessage: error.toString(),
    cause: error,
  );
}

String localizeReadAloudCapability(
  AppLocalizations l10n,
  ReadAloudCapability capability,
) {
  if (capability.supported) return '';
  final code = capability.reasonCode;
  return switch (code) {
    'unsupported_platform' || 'not_initialized' => l10n.ttsErrorUnsupported,
    'plugin_unavailable' ||
    'engine_unavailable' =>
      l10n.ttsErrorEngineUnavailable,
    'voice_unavailable' ||
    'language_unavailable' =>
      l10n.ttsErrorVoiceUnavailable,
    _ => l10n.ttsErrorPlaybackFailed,
  };
}
