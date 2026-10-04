import '../../../../domain/resources/resource_contracts.dart';
import '../../../../domain/resources/resource_generation_protocol.dart';
import '../../../../domain/resources/streaming_generation_runtime_contracts.dart';
import '../../../../domain/errors/app_error.dart';

/// Presentation lifecycle of the Resource Studio.
enum ResourceStudioStatus {
  initial,
  loading,
  ready,
  generating,
  validating,
  paused,
  completed,
  retrying,
  failed,
}

/// Immutable state exposed by the Resource Studio controller.
final class ResourceStudioState {
  const ResourceStudioState({
    required this.status,
    this.resourceId,
    this.session,
    this.canAcceptGeneratedCharacter = false,
    this.tree,
    this.selectedPartId,
    this.partContents = const <String, String>{},
    this.partTaskStatuses = const <String, PartTaskStatus>{},
    this.retryingPartIds = const <String>{},
    this.errorMessage = '',
    this.error,
  });

  const ResourceStudioState.initial()
      : this(status: ResourceStudioStatus.initial);

  final ResourceStudioStatus status;
  final ResourceId? resourceId;
  final StreamingGenerationSession? session;
  final bool canAcceptGeneratedCharacter;
  final ResourceTree? tree;
  final PartId? selectedPartId;
  final Map<String, String> partContents;

  /// Persisted per-Part generation task status, keyed by Part id.
  ///
  /// Absent for a Part with no generation task (e.g. a manually authored one);
  /// the UI then falls back to content-derived labels.
  final Map<String, PartTaskStatus> partTaskStatuses;

  /// Parts whose targeted regeneration is currently in flight.
  final Set<String> retryingPartIds;
  final String errorMessage;
  final AppDomainError? error;

  bool get isBusy => switch (status) {
        ResourceStudioStatus.loading ||
        ResourceStudioStatus.generating ||
        ResourceStudioStatus.validating ||
        ResourceStudioStatus.retrying =>
          true,
        _ => false,
      };

  ResourceStudioState copyWith({
    ResourceStudioStatus? status,
    ResourceId? resourceId,
    StreamingGenerationSession? session,
    bool? canAcceptGeneratedCharacter,
    ResourceTree? tree,
    PartId? selectedPartId,
    Map<String, String>? partContents,
    Map<String, PartTaskStatus>? partTaskStatuses,
    Set<String>? retryingPartIds,
    String? errorMessage,
    AppDomainError? error,
    bool clearError = false,
  }) {
    return ResourceStudioState(
      status: status ?? this.status,
      resourceId: resourceId ?? this.resourceId,
      session: session ?? this.session,
      canAcceptGeneratedCharacter:
          canAcceptGeneratedCharacter ?? this.canAcceptGeneratedCharacter,
      tree: tree ?? this.tree,
      selectedPartId: selectedPartId ?? this.selectedPartId,
      partContents: partContents ?? this.partContents,
      partTaskStatuses: partTaskStatuses ?? this.partTaskStatuses,
      retryingPartIds: retryingPartIds ?? this.retryingPartIds,
      errorMessage: errorMessage ?? this.errorMessage,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
