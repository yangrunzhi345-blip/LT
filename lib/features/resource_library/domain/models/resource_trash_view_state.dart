import '../../../../domain/resources/resource_trash.dart';
import '../../../../domain/errors/app_error.dart';

/// Loading state of the recycle-bin sheet.
enum ResourceTrashViewStatus { idle, loading, ready, error }

enum ResourceTrashErrorKind { load, restore, permanentDelete }

enum ResourceTrashNoticeKind { restored, permanentlyDeleted }

final class ResourceTrashNotice {
  const ResourceTrashNotice({
    required this.kind,
    this.placement,
  });

  final ResourceTrashNoticeKind kind;
  final TrashRestorePlacement? placement;
}

/// One recycle-bin row, pre-formatted for display.
///
/// Formatting lives here so the sheet is a pure function of its state and can
/// be widget-tested without a database.
final class ResourceTrashItem {
  const ResourceTrashItem({
    required this.trashId,
    required this.resourceId,
    required this.title,
    required this.nodeKind,
    required this.reason,
    required this.deletedAt,
    required this.expiresAt,
    required this.isRestored,
  });

  final String trashId;
  final String resourceId;
  final String title;
  final RevisionNodeKindRef nodeKind;
  final TrashReason reason;
  final DateTime? deletedAt;
  final DateTime? expiresAt;
  final bool isRestored;
}

/// What the recycle-bin sheet shows.
final class ResourceTrashViewState {
  const ResourceTrashViewState({
    required this.status,
    this.items = const <ResourceTrashItem>[],
    this.errorMessage = '',
    this.notice,
    this.errorKind,
    this.busyTrashId = '',
    this.error,
  });

  const ResourceTrashViewState.initial()
      : status = ResourceTrashViewStatus.idle,
        items = const <ResourceTrashItem>[],
        errorMessage = '',
        notice = null,
        errorKind = null,
        busyTrashId = '',
        error = null;

  final ResourceTrashViewStatus status;
  final List<ResourceTrashItem> items;
  final String errorMessage;
  final ResourceTrashNotice? notice;
  final ResourceTrashErrorKind? errorKind;

  /// Entry currently being restored or purged, so its row can show a spinner
  /// and the other actions can be disabled.
  final String busyTrashId;
  final AppDomainError? error;

  bool get isLoading => status == ResourceTrashViewStatus.loading;

  bool get hasError => status == ResourceTrashViewStatus.error;

  bool get isEmpty => items.isEmpty;

  ResourceTrashViewState copyWith({
    ResourceTrashViewStatus? status,
    List<ResourceTrashItem>? items,
    String? errorMessage,
    ResourceTrashNotice? notice,
    ResourceTrashErrorKind? errorKind,
    String? busyTrashId,
    bool clearMessages = false,
    AppDomainError? error,
  }) =>
      ResourceTrashViewState(
        status: status ?? this.status,
        items: items ?? this.items,
        errorMessage: clearMessages ? '' : (errorMessage ?? this.errorMessage),
        notice: clearMessages ? null : (notice ?? this.notice),
        errorKind: clearMessages ? null : (errorKind ?? this.errorKind),
        busyTrashId: busyTrashId ?? this.busyTrashId,
        error: error ?? this.error,
      );
}

/// Outcome of one restore, as the runtime reports it.
final class TrashRestoreSummary {
  const TrashRestoreSummary({
    required this.alreadyRestored,
    required this.usedFallback,
    required this.placement,
  });

  final bool alreadyRestored;

  /// True when the node could not return to its original parent and was placed
  /// in a freshly created section instead. The sheet always shows this, so a
  /// fallback restore is never silent.
  final bool usedFallback;

  final TrashRestorePlacement placement;
}

/// Formats one bin entry for the sheet.
ResourceTrashItem trashItemOf(ResourceTrashEntry entry) => ResourceTrashItem(
      trashId: entry.trashId,
      resourceId: entry.resourceId.value,
      title: entry.originalTitle.trim().isEmpty
          ? entry.nodeId
          : entry.originalTitle,
      nodeKind: entry.nodeKind,
      reason: entry.reason,
      deletedAt: DateTime.tryParse(entry.deletedAtToken)?.toLocal(),
      expiresAt: DateTime.tryParse(entry.expiresAtToken)?.toLocal(),
      isRestored: entry.isRestored,
    );
