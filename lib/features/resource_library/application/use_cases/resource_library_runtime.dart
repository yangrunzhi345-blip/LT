import '../../../../../application/resources/assembly_readiness_repository.dart';
import '../../../../../application/resources/resource_lifecycle_projection.dart';
import '../../../../../application/resources/resource_lifecycle_reconciler.dart';
import '../../../../../controllers/resource_crud_controller.dart';
import '../../../../../domain/resources/resource_contracts.dart';
import '../../../../../domain/resources/streaming_generation_runtime_contracts.dart';
import '../../../../../models/resource_library_mode.dart';
import '../../../resource_studio/application/use_cases/resource_studio_runtime.dart';
import '../../domain/models/resource_library_view_state.dart';

abstract interface class ResourceLibraryRuntime {
  Future<List<ResourceLibraryItem>> load(ResourceLibraryMode mode);

  Future<ResourceOperationResult> moveToTrash({
    required ResourceLibraryItem item,
    required ResourceLibraryMode mode,
  });

  Future<String> createManual({
    required ResourceType type,
    required String name,
    required String summary,
    required ResourceLibraryMode mode,
  });
}

/// Resolves the library status with an active generation taking precedence.
ResourceDisplayStatus resolveResourceDisplayStatus({
  required bool hasTree,
  required StreamingGenerationSession? session,
  required AssemblyReadinessRecord? readiness,
}) {
  if (!hasTree) return ResourceDisplayStatus.saved;
  if (session != null &&
      !<StreamingLifecycleStatus>{
        StreamingLifecycleStatus.completed,
        StreamingLifecycleStatus.failed,
        StreamingLifecycleStatus.cancelled,
        StreamingLifecycleStatus.paused,
      }.contains(session.status)) {
    return ResourceDisplayStatus.generating;
  }
  if (readiness == null) return ResourceDisplayStatus.saved;
  return switch (readiness.state) {
    ReadinessState.preparing => ResourceDisplayStatus.optimizing,
    ReadinessState.ready => ResourceDisplayStatus.ready,
    ReadinessState.failed => ResourceDisplayStatus.optimizationFailed,
    ReadinessState.stale => ResourceDisplayStatus.optimizationSuggested,
  };
}

final class ProductionResourceLibraryRuntime implements ResourceLibraryRuntime {
  const ProductionResourceLibraryRuntime({
    required ResourceCrudController crud,
    required ResourceStudioRuntime studio,
    required ResourceLifecycleReconciler reconciler,
  })  : _crud = crud,
        _studio = studio,
        _reconciler = reconciler;

  final ResourceCrudController _crud;
  final ResourceStudioRuntime _studio;
  final ResourceLifecycleReconciler _reconciler;

  @override
  Future<List<ResourceLibraryItem>> load(ResourceLibraryMode mode) async {
    // FATAL boundary: the three root projections. A failure here means the
    // resource tables themselves are unreadable, which is a genuine
    // library-level error and must surface (with retry) rather than be hidden.
    final results = await Future.wait(<Future<List<Map<String, dynamic>>>>[
      _crud.loadWorldviewPresets(mode: mode),
      _crud.loadCharacterCards(mode: mode),
      _crud.loadNpcCards(mode: mode),
    ]);

    // Best-effort Studio index. A single unmappable legacy row inside the tree
    // enumeration must not blind the whole list, so this enrichment degrades
    // instead of failing the load.
    final studioById = await _studioIndex();

    final items = <ResourceLibraryItem>[];
    for (final entry in <(ResourceType, List<Map<String, dynamic>>)>[
      (ResourceType.worldview, results[0]),
      (ResourceType.character, results[1]),
      (ResourceType.npc, results[2]),
    ]) {
      for (final row in entry.$2) {
        final id = row['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        items.add(await _itemOf(
          type: entry.$1,
          id: id,
          row: row,
          resource: studioById[id],
        ));
      }
    }
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  /// Builds one library item, isolating every per-resource failure so a single
  /// corrupt / legacy-incompatible resource becomes a terminal item instead of
  /// aborting the whole list. Database-level failures still propagate.
  Future<ResourceLibraryItem> _itemOf({
    required ResourceType type,
    required String id,
    required Map<String, dynamic> row,
    required Resource? resource,
  }) async {
    final resourceId = ResourceId(id);
    // One reconciled read drives both the lifecycle state and consumability;
    // it never manufactures `ready` — a completed-but-stuck resource is
    // converged through the assembly readiness authority here, and a per
    // resource read fault is reported as a terminal `failed` state.
    ResourceLifecycleProjectionResult projection;
    try {
      projection = await _reconciler.read(resourceId);
    } catch (error) {
      if (!isIsolatableLifecycleReadError(error)) rethrow;
      return _terminalItem(type: type, id: id, row: row, resource: resource);
    }
    try {
      return ResourceLibraryItem(
        id: id,
        type: type,
        name: row['name']?.toString().trim().isNotEmpty == true
            ? row['name'].toString().trim()
            : '',
        summary: _summary(type, row, resource),
        updatedAt: row['updated_at']?.toString() ?? '',
        status: _displayStatusOf(projection.state),
        isStudioAvailable: resource != null,
        isConsumable: projection.isConsumable,
        lifecycleState: projection.state,
        originWorldviewId: _originWorldviewId(row, resource),
      );
    } catch (error) {
      if (!isIsolatableLifecycleReadError(error)) rethrow;
      return _terminalItem(type: type, id: id, row: row, resource: resource);
    }
  }

  /// A resource whose lifecycle cannot be read: still listed, with a clear
  /// terminal「校验失败 / 不可用于冒险」state rather than hidden or escalated.
  ResourceLibraryItem _terminalItem({
    required ResourceType type,
    required String id,
    required Map<String, dynamic> row,
    required Resource? resource,
  }) =>
      ResourceLibraryItem(
        id: id,
        type: type,
        name: row['name']?.toString().trim() ?? '',
        summary: '',
        updatedAt: row['updated_at']?.toString() ?? '',
        status: ResourceDisplayStatus.optimizationFailed,
        isStudioAvailable: resource != null,
        isConsumable: false,
        lifecycleState: ResourceLifecycleState.failed,
        originWorldviewId: _originWorldviewId(row, resource),
      );

  Future<Map<String, Resource>> _studioIndex() async {
    try {
      final studioResources = await _studio.listResources();
      return <String, Resource>{
        for (final resource in studioResources) resource.id.value: resource,
      };
    } catch (error) {
      if (!isIsolatableLifecycleReadError(error)) rethrow;
      // Per-resource mapping fault inside the tree enumeration: keep listing
      // the raw rows that did resolve rather than failing the library.
      return const <String, Resource>{};
    }
  }

  String _originWorldviewId(Map<String, dynamic> row, Resource? resource) {
    final rowValue = row['matching_worldview_id']?.toString().trim();
    if (rowValue != null && rowValue.isNotEmpty) return rowValue;
    final resourceValue =
        resource?.metadata['matching_worldview_id']?.toString().trim();
    return resourceValue ?? '';
  }

  @override
  Future<String> createManual({
    required ResourceType type,
    required String name,
    required String summary,
    required ResourceLibraryMode mode,
  }) async {
    final resource = await _studio.createManual(
      resourceType: type,
      name: name,
      summary: summary,
      libraryMode: mode.storageValue,
    );
    return resource.id.value;
  }

  @override
  Future<ResourceOperationResult> moveToTrash({
    required ResourceLibraryItem item,
    required ResourceLibraryMode mode,
  }) =>
      switch (item.type) {
        ResourceType.worldview =>
          _crud.deleteWorldviewPreset(item.id, mode: mode),
        ResourceType.character =>
          _crud.deleteCharacterCard(item.id, mode: mode),
        ResourceType.npc => _crud.deleteNpcCard(item.id, mode: mode),
      };

  ResourceDisplayStatus _displayStatusOf(ResourceLifecycleState state) {
    return switch (state) {
      ResourceLifecycleState.ready => ResourceDisplayStatus.ready,
      ResourceLifecycleState.validating => ResourceDisplayStatus.optimizing,
      ResourceLifecycleState.generating ||
      ResourceLifecycleState.planning ||
      ResourceLifecycleState.recovering =>
        ResourceDisplayStatus.generating,
      ResourceLifecycleState.failed ||
      ResourceLifecycleState.paused =>
        ResourceDisplayStatus.optimizationFailed,
      ResourceLifecycleState.draft ||
      ResourceLifecycleState.missing ||
      ResourceLifecycleState.archived =>
        ResourceDisplayStatus.saved,
    };
  }

  String _summary(
    ResourceType type,
    Map<String, dynamic> row,
    Resource? resource,
  ) {
    final treeSummary = resource?.summary.trim() ?? '';
    if (treeSummary.isNotEmpty) return treeSummary;
    if (type == ResourceType.worldview) {
      return row['description']?.toString().trim() ?? '';
    }
    final data = _crud.decodeCardData(row);
    for (final key in const <String>[
      'description',
      'background',
      'personality'
    ]) {
      final value = data[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }
}
