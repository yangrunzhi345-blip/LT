import '../../../../application/resources/resource_trash_service.dart';
import '../../domain/models/resource_trash_view_state.dart';

/// Narrow recycle-bin boundary consumed by the Resource Library.
///
/// The sheet never sees the tree, SQLite or the retention rules; it asks for a
/// display list and for restore/permanent-delete actions, which keeps the UI
/// widget-testable and keeps the "delete first, purge explicitly" rule in one
/// place.
abstract interface class ResourceTrashRuntime {
  /// Unresolved bin entries, newest delete first.
  Future<List<ResourceTrashItem>> list();

  /// Restores one entry and reports where it landed.
  Future<TrashRestoreSummary> restore(String trashId);

  /// Permanently deletes one entry. This is the explicit second operation; a
  /// normal delete never reaches it.
  Future<int> permanentDelete(String trashId);

  /// Purges entries whose retention window has passed. Returns how many were
  /// removed. Entries still inside the window are never touched.
  Future<int> purgeExpired();

  void dispose();
}

/// Production adapter over [ResourceTrashService].
final class ResourceTrashServiceRuntime implements ResourceTrashRuntime {
  ResourceTrashServiceRuntime({
    required ResourceTrashService service,
    this.listLimit = 200,
  }) : _service = service;

  final ResourceTrashService _service;
  final int listLimit;

  @override
  Future<List<ResourceTrashItem>> list() async {
    final entries = await _service.list(limit: listLimit);
    return entries.map(trashItemOf).toList();
  }

  @override
  Future<TrashRestoreSummary> restore(String trashId) async {
    final result = await _service.restore(trashId);
    return TrashRestoreSummary(
      alreadyRestored: result.isIdempotentRepeat,
      usedFallback: result.placement.isFallback,
      placement: result.placement,
    );
  }

  @override
  Future<int> permanentDelete(String trashId) async {
    final result = await _service.permanentDelete(trashId);
    return result.deletedNodeIds.length;
  }

  @override
  Future<int> purgeExpired() => _service.purgeExpired();

  @override
  void dispose() {}
}
