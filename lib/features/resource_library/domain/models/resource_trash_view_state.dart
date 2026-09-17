import '../../../../domain/resources/resource_trash.dart';

/// Loading state of the recycle-bin sheet.
enum ResourceTrashViewStatus { idle, loading, ready, error }

/// One recycle-bin row, pre-formatted for display.
///
/// Formatting lives here so the sheet is a pure function of its state and can
/// be widget-tested without a database.
final class ResourceTrashItem {
  const ResourceTrashItem({
    required this.trashId,
    required this.resourceId,
    required this.title,
    required this.kindLabel,
    required this.reasonLabel,
    required this.deletedAtLabel,
    required this.expiresAtLabel,
    required this.isRestored,
  });

  final String trashId;
  final String resourceId;
  final String title;
  final String kindLabel;
  final String reasonLabel;
  final String deletedAtLabel;
  final String expiresAtLabel;
  final bool isRestored;

  String get subtitle =>
      '$kindLabel · $reasonLabel · 删除于 $deletedAtLabel · 保留至 $expiresAtLabel';
}

/// What the recycle-bin sheet shows.
final class ResourceTrashViewState {
  const ResourceTrashViewState({
    required this.status,
    this.items = const <ResourceTrashItem>[],
    this.errorMessage = '',
    this.statusMessage = '',
    this.busyTrashId = '',
  });

  const ResourceTrashViewState.initial()
      : status = ResourceTrashViewStatus.idle,
        items = const <ResourceTrashItem>[],
        errorMessage = '',
        statusMessage = '',
        busyTrashId = '';

  final ResourceTrashViewStatus status;
  final List<ResourceTrashItem> items;
  final String errorMessage;
  final String statusMessage;

  /// Entry currently being restored or purged, so its row can show a spinner
  /// and the other actions can be disabled.
  final String busyTrashId;

  bool get isLoading => status == ResourceTrashViewStatus.loading;

  bool get hasError => status == ResourceTrashViewStatus.error;

  bool get isEmpty => items.isEmpty;

  ResourceTrashViewState copyWith({
    ResourceTrashViewStatus? status,
    List<ResourceTrashItem>? items,
    String? errorMessage,
    String? statusMessage,
    String? busyTrashId,
    bool clearMessages = false,
  }) =>
      ResourceTrashViewState(
        status: status ?? this.status,
        items: items ?? this.items,
        errorMessage: clearMessages ? '' : (errorMessage ?? this.errorMessage),
        statusMessage:
            clearMessages ? '' : (statusMessage ?? this.statusMessage),
        busyTrashId: busyTrashId ?? this.busyTrashId,
      );
}

/// Outcome of one restore, as the runtime reports it.
final class TrashRestoreSummary {
  const TrashRestoreSummary({
    required this.alreadyRestored,
    required this.usedFallback,
    required this.message,
  });

  final bool alreadyRestored;

  /// True when the node could not return to its original parent and was placed
  /// in a freshly created section instead. The sheet always shows this, so a
  /// fallback restore is never silent.
  final bool usedFallback;

  final String message;
}

/// Formats one bin entry for the sheet.
ResourceTrashItem trashItemOf(ResourceTrashEntry entry) => ResourceTrashItem(
      trashId: entry.trashId,
      resourceId: entry.resourceId.value,
      title: entry.originalTitle.trim().isEmpty
          ? entry.nodeId
          : entry.originalTitle,
      kindLabel: _kindLabel(entry.nodeKind),
      reasonLabel: entry.reason.displayLabel,
      deletedAtLabel: _formatTimestamp(entry.deletedAtToken),
      expiresAtLabel: _formatTimestamp(entry.expiresAtToken),
      isRestored: entry.isRestored,
    );

String _kindLabel(RevisionNodeKindRef kind) => switch (kind) {
      RevisionNodeKindRef.resource => '资源',
      RevisionNodeKindRef.section => '章节',
      RevisionNodeKindRef.part => '段落',
    };

String _formatTimestamp(String token) {
  final parsed = DateTime.tryParse(token)?.toLocal();
  if (parsed == null) return '未知时间';
  return '${parsed.year}-${_pad(parsed.month)}-${_pad(parsed.day)} '
      '${_pad(parsed.hour)}:${_pad(parsed.minute)}';
}

String _pad(int value) => value.toString().padLeft(2, '0');
