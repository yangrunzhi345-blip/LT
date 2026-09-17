import '../../../../domain/resources/resource_revision.dart';

/// Loading state of the revision-history panel.
enum ResourceRevisionViewStatus { idle, loading, ready, error }

/// One row of the revision history, pre-formatted for display.
///
/// Formatting lives here rather than in the widget so the panel stays a pure
/// function of its state and can be widget-tested without a database.
final class ResourceRevisionItem {
  const ResourceRevisionItem({
    required this.revisionId,
    required this.causeLabel,
    required this.label,
    required this.createdAtLabel,
    required this.nodeCount,
    required this.charCount,
    required this.isHead,
  });

  final String revisionId;
  final String causeLabel;
  final String label;
  final String createdAtLabel;
  final int nodeCount;
  final int charCount;
  final bool isHead;

  String get title {
    if (label.trim().isNotEmpty) return label;
    return causeLabel;
  }

  String get subtitle => '$createdAtLabel · $nodeCount 个节点 · $charCount 字';

  @override
  String toString() => 'ResourceRevisionItem($revisionId, head=$isHead)';
}

/// What the panel shows.
final class ResourceRevisionViewState {
  const ResourceRevisionViewState({
    required this.status,
    this.resourceId = '',
    this.items = const <ResourceRevisionItem>[],
    this.errorMessage = '',
    this.statusMessage = '',
    this.canRestore = true,
  });

  const ResourceRevisionViewState.initial()
      : status = ResourceRevisionViewStatus.idle,
        resourceId = '',
        items = const <ResourceRevisionItem>[],
        errorMessage = '',
        statusMessage = '',
        canRestore = true;

  final ResourceRevisionViewStatus status;
  final String resourceId;
  final List<ResourceRevisionItem> items;
  final String errorMessage;

  /// Transient feedback ("已恢复到 AI 生成前的版本").
  final String statusMessage;

  /// False while a restore is in flight, so the panel cannot queue two.
  final bool canRestore;

  bool get isLoading => status == ResourceRevisionViewStatus.loading;

  bool get hasHistory => items.isNotEmpty;

  bool get hasError => status == ResourceRevisionViewStatus.error;

  ResourceRevisionViewState copyWith({
    ResourceRevisionViewStatus? status,
    String? resourceId,
    List<ResourceRevisionItem>? items,
    String? errorMessage,
    String? statusMessage,
    bool? canRestore,
    bool clearMessages = false,
  }) =>
      ResourceRevisionViewState(
        status: status ?? this.status,
        resourceId: resourceId ?? this.resourceId,
        items: items ?? this.items,
        errorMessage: clearMessages ? '' : (errorMessage ?? this.errorMessage),
        statusMessage:
            clearMessages ? '' : (statusMessage ?? this.statusMessage),
        canRestore: canRestore ?? this.canRestore,
      );
}

/// Result of one restore request, as the runtime reports it.
final class RevisionRestoreSummary {
  const RevisionRestoreSummary({
    required this.alreadyAtRevision,
    required this.message,
    this.headRevisionId = '',
    this.reopenedPartCount = 0,
  });

  final bool alreadyAtRevision;
  final String message;
  final String headRevisionId;
  final int reopenedPartCount;
}

/// Formats a revision row for the history list.
///
/// Kept next to the view state so the controller and the tests share one
/// formatter instead of each re-implementing the labels.
ResourceRevisionItem revisionItemOf(ResourceRevision revision) {
  final createdAt = DateTime.tryParse(revision.createdAtToken)?.toLocal();
  return ResourceRevisionItem(
    revisionId: revision.revisionId.value,
    causeLabel: revision.cause.displayLabel,
    label: revision.label,
    createdAtLabel: createdAt == null
        ? '未知时间'
        : '${createdAt.year}-${_pad(createdAt.month)}-${_pad(createdAt.day)} '
            '${_pad(createdAt.hour)}:${_pad(createdAt.minute)}',
    nodeCount: revision.nodeCount,
    charCount: revision.charCount,
    isHead: revision.isHead,
  );
}

String _pad(int value) => value.toString().padLeft(2, '0');
