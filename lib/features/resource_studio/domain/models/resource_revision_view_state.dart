import '../../../../domain/resources/resource_revision.dart';

/// Loading state of the revision-history panel.
enum ResourceRevisionViewStatus { idle, loading, ready, error }

enum RevisionRestoreNoticeType { alreadyAtRevision, restored }

final class RevisionRestoreNotice {
  const RevisionRestoreNotice({
    required this.type,
    this.sourceCause,
  });

  final RevisionRestoreNoticeType type;
  final RevisionCause? sourceCause;
}

/// One row of the revision history, pre-formatted for display.
///
/// Formatting lives here rather than in the widget so the panel stays a pure
/// function of its state and can be widget-tested without a database.
final class ResourceRevisionItem {
  const ResourceRevisionItem({
    required this.revisionId,
    required this.cause,
    required this.label,
    required this.createdAt,
    required this.nodeCount,
    required this.charCount,
    required this.isHead,
  });

  final String revisionId;
  final RevisionCause cause;
  final String label;
  final DateTime? createdAt;
  final int nodeCount;
  final int charCount;
  final bool isHead;

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
    this.notice,
    this.canRestore = true,
  });

  const ResourceRevisionViewState.initial()
      : status = ResourceRevisionViewStatus.idle,
        resourceId = '',
        items = const <ResourceRevisionItem>[],
        errorMessage = '',
        notice = null,
        canRestore = true;

  final ResourceRevisionViewStatus status;
  final String resourceId;
  final List<ResourceRevisionItem> items;
  final String errorMessage;

  /// Transient restore feedback rendered in the active UI locale.
  final RevisionRestoreNotice? notice;

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
    RevisionRestoreNotice? notice,
    bool clearNotice = false,
    bool? canRestore,
    bool clearMessages = false,
  }) =>
      ResourceRevisionViewState(
        status: status ?? this.status,
        resourceId: resourceId ?? this.resourceId,
        items: items ?? this.items,
        errorMessage: clearMessages ? '' : (errorMessage ?? this.errorMessage),
        notice: clearMessages || clearNotice ? null : (notice ?? this.notice),
        canRestore: canRestore ?? this.canRestore,
      );
}

/// Result of one restore request, as the runtime reports it.
final class RevisionRestoreSummary {
  const RevisionRestoreSummary({
    required this.alreadyAtRevision,
    this.sourceCause,
    this.headRevisionId = '',
    this.reopenedPartCount = 0,
  });

  final bool alreadyAtRevision;
  final RevisionCause? sourceCause;
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
    cause: revision.cause,
    label: revision.label,
    createdAt: createdAt,
    nodeCount: revision.nodeCount,
    charCount: revision.charCount,
    isHead: revision.isHead,
  );
}
