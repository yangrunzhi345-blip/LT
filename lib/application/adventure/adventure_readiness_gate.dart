import '../../domain/errors/app_error.dart';
import '../../models/adventure_config.dart';
import '../resources/resource_readiness_contracts.dart';

/// Gate status of one asset referenced by an Adventure.
enum AdventureAssetGateStatus {
  /// The asset is ready to start.
  ready,

  /// Preparation is running (or waiting for compression).
  preparing,

  /// The last preparation failed.
  failed,

  /// No assembly revision has ever been published.
  noReadyRevision,

  /// The resource changed after the last ready assembly; the previous ready
  /// revision still exists and may be chosen explicitly.
  staleWithPreviousReady,

  /// The id does not resolve to a managed asset (a pure legacy asset).
  notManaged;

  bool get blocksStart =>
      this == preparing ||
      this == failed ||
      this == noReadyRevision ||
      this == staleWithPreviousReady;
}

/// Stable reason for a readiness result. The legacy [message] remains only
/// for reading old callers and persisted diagnostics.
enum AdventureReadinessIssueCode {
  notManaged,
  noSavedRevision,
  preparing,
  preparationFailed,
  ready,
  noAssemblyRevision,
  staleWithPreviousReady,
}

/// Typed readiness of one asset.
///
/// [message] remains only for legacy callers. New application paths leave it
/// empty and presentation maps [issueCode] and [parameters] to localizations.
final class AdventureAssetReadiness {
  const AdventureAssetReadiness({
    required this.assetId,
    required this.status,
    this.message = '',
    this.issueCode,
    this.parameters = const <String, Object?>{},
    this.assemblyRevisionId = '',
    this.assemblyContentHash = '',
  });

  final String assetId;
  final AdventureAssetGateStatus status;
  @Deprecated('Use issueCode and parameters in presentation.')
  final String message;
  final AdventureReadinessIssueCode? issueCode;
  final Map<String, Object?> parameters;

  /// The consumable (or previously ready) assembly revision, when one exists.
  final String assemblyRevisionId;
  final String assemblyContentHash;

  bool get isManaged => status != AdventureAssetGateStatus.notManaged;

  AdventureReadinessIssueCode get effectiveIssueCode =>
      issueCode ??
      switch (status) {
        AdventureAssetGateStatus.notManaged =>
          AdventureReadinessIssueCode.notManaged,
        AdventureAssetGateStatus.noReadyRevision =>
          AdventureReadinessIssueCode.noSavedRevision,
        AdventureAssetGateStatus.preparing =>
          AdventureReadinessIssueCode.preparing,
        AdventureAssetGateStatus.failed =>
          AdventureReadinessIssueCode.preparationFailed,
        AdventureAssetGateStatus.ready => AdventureReadinessIssueCode.ready,
        AdventureAssetGateStatus.staleWithPreviousReady =>
          AdventureReadinessIssueCode.staleWithPreviousReady,
      };
}

/// Interface of the Adventure start-boundary gate. Exists so UI/test layers
/// can substitute the production gate without touching SQLite.
abstract interface class IAdventureReadinessGate {
  Future<AssemblyPrepareOutcome> prepare(String assetId);

  Future<Map<String, AdventureAssetReadiness>> resolve(
    Iterable<String> assetIds,
  );

  Future<Map<String, AdventureAssetReadiness>> resolveConfig(
    AdventureConfig config,
  );

  Future<AdventureConfig> enforceAndFreeze(AdventureConfig config);
}

/// Thrown when an Adventure must not start (fail closed).
///
/// [messages] are user-presentable Chinese reasons, one per blocked asset.
class AdventureReadinessGateException implements Exception {
  AdventureReadinessGateException({
    this.messages = const [],
    this.issues = const [],
    this.error,
  });

  /// Legacy display strings retained for old persisted/caller compatibility.
  final List<String> messages;
  final List<AdventureAssetReadiness> issues;
  final AppDomainError? error;

  @override
  String toString() => messages.join('；');
}
