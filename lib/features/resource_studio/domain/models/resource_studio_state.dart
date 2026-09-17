import '../../../../domain/resources/resource_contracts.dart';
import '../../../../domain/resources/streaming_generation_runtime_contracts.dart';

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
    this.tree,
    this.selectedPartId,
    this.partContents = const <String, String>{},
    this.errorMessage = '',
  });

  const ResourceStudioState.initial()
      : this(status: ResourceStudioStatus.initial);

  final ResourceStudioStatus status;
  final ResourceId? resourceId;
  final StreamingGenerationSession? session;
  final ResourceTree? tree;
  final PartId? selectedPartId;
  final Map<String, String> partContents;
  final String errorMessage;

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
    ResourceTree? tree,
    PartId? selectedPartId,
    Map<String, String>? partContents,
    String? errorMessage,
  }) {
    return ResourceStudioState(
      status: status ?? this.status,
      resourceId: resourceId ?? this.resourceId,
      session: session ?? this.session,
      tree: tree ?? this.tree,
      selectedPartId: selectedPartId ?? this.selectedPartId,
      partContents: partContents ?? this.partContents,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
