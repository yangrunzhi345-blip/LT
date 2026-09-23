import '../../../../application/resources/resource_revision_service.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../domain/models/resource_revision_view_state.dart';

/// Narrow revision boundary consumed by the Studio history panel.
///
/// The widget layer never sees SQLite, the revision chain or the delta format:
/// it asks for a display list and a restore, which keeps the panel
/// widget-testable and keeps the "record before / record after" rule in one
/// place.
abstract interface class ResourceRevisionRuntime {
  /// Newest-first history of [resourceId].
  Future<List<ResourceRevisionItem>> listHistory(
    String resourceId, {
    int limit = 30,
  });

  /// Current optimistic token of [resourceId], for the restore CAS.
  Future<String?> readResourceUpdatedAt(String resourceId);

  /// Rolls [revisionId] back and reports what happened.
  ///
  /// [expectedUpdatedAt] is the token read before the user confirmed: a restore
  /// overwrites confirmed content, so it is guarded like every other write
  /// (audit P9-M5).
  Future<RevisionRestoreSummary> restoreRevision(
    String revisionId, {
    String expectedUpdatedAt,
  });

  void dispose();
}

/// Production adapter over [ResourceRevisionService].
final class ResourceRevisionServiceRuntime implements ResourceRevisionRuntime {
  ResourceRevisionServiceRuntime({required ResourceRevisionService service})
      : _service = service;

  final ResourceRevisionService _service;

  @override
  Future<List<ResourceRevisionItem>> listHistory(
    String resourceId, {
    int limit = 30,
  }) async {
    final revisions = await _service.history(
      ResourceId(resourceId),
      kind: ResourceRevisionKind.latestHead,
      limit: limit,
    );
    return revisions.map(revisionItemOf).toList();
  }

  @override
  Future<String?> readResourceUpdatedAt(String resourceId) =>
      _service.resourceUpdatedAt(ResourceId(resourceId));

  @override
  Future<RevisionRestoreSummary> restoreRevision(
    String revisionId, {
    String expectedUpdatedAt = '',
  }) async {
    final result = await _service.restoreRevision(
      ResourceRevisionId(revisionId),
      expectedUpdatedAt: expectedUpdatedAt,
    );
    if (result.alreadyAtRevision) {
      return RevisionRestoreSummary(
        alreadyAtRevision: true,
        sourceCause: result.sourceCause,
        headRevisionId: result.headRevisionId?.value ?? '',
      );
    }
    return RevisionRestoreSummary(
      alreadyAtRevision: false,
      sourceCause: result.sourceCause,
      headRevisionId: result.headRevisionId?.value ?? '',
      reopenedPartCount: result.reopenedPartIds.length,
    );
  }

  @override
  void dispose() {}
}
