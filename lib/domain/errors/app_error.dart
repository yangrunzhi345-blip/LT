/// Stable, locale-neutral failures shared by application and presentation.
enum AppErrorCode {
  unknown,
  networkUnavailable,
  timeout,
  unauthorized,
  paymentRequired,
  forbidden,
  notFound,
  rateLimited,
  serverError,
  invalidRequest,
  resourceValidationFailed,
  resourceCapacityExceeded,
  resourceGenerationFailed,
  resourceConflict,
  adventureAssetMissing,
  adventureAssetStale,
  ttsUnsupported,
  ttsEngineUnavailable,
  ttsVoiceUnavailable,
  ttsPlaybackFailed,
}

/// A failure that can be rendered without exposing technical diagnostics.
final class AppDomainError implements Exception {
  const AppDomainError({
    required this.code,
    this.parameters = const <String, Object?>{},
    this.debugMessage,
    this.cause,
  });

  final AppErrorCode code;
  final Map<String, Object?> parameters;
  final String? debugMessage;
  final Object? cause;

  @override
  String toString() => 'AppDomainError(${code.name})';
}
