import '../../../../../application/resources/assembly_readiness_repository.dart';
import '../../../../../controllers/resource_crud_controller.dart';
import '../../../../../domain/resources/resource_contracts.dart';
import '../../../../../domain/resources/streaming_generation_runtime_contracts.dart';
import '../../../../../models/resource_library_mode.dart';
import '../../../resource_studio/application/use_cases/resource_studio_runtime.dart';
import '../../domain/models/resource_library_view_state.dart';

abstract interface class ResourceLibraryRuntime {
  Future<List<ResourceLibraryItem>> load(ResourceLibraryMode mode);

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
    required IAssemblyReadinessRepository readiness,
  })  : _crud = crud,
        _studio = studio,
        _readiness = readiness;

  final ResourceCrudController _crud;
  final ResourceStudioRuntime _studio;
  final IAssemblyReadinessRepository _readiness;

  @override
  Future<List<ResourceLibraryItem>> load(ResourceLibraryMode mode) async {
    final results = await Future.wait(<Future<List<Map<String, dynamic>>>>[
      _crud.loadWorldviewPresets(mode: mode),
      _crud.loadCharacterCards(mode: mode),
      _crud.loadNpcCards(mode: mode),
    ]);
    final studioResources = await _studio.listResources();
    final studioById = <String, Resource>{
      for (final resource in studioResources) resource.id.value: resource,
    };
    final items = <ResourceLibraryItem>[];
    for (final entry in <(ResourceType, List<Map<String, dynamic>>)>[
      (ResourceType.worldview, results[0]),
      (ResourceType.character, results[1]),
      (ResourceType.npc, results[2]),
    ]) {
      for (final row in entry.$2) {
        final id = row['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final resource = studioById[id];
        items.add(ResourceLibraryItem(
          id: id,
          type: entry.$1,
          name: row['name']?.toString().trim().isNotEmpty == true
              ? row['name'].toString().trim()
              : '未命名资源',
          summary: _summary(entry.$1, row, resource),
          updatedAt: row['updated_at']?.toString() ?? '',
          status: await _displayStatus(id, resource != null),
          isStudioAvailable: resource != null,
        ));
      }
    }
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
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

  Future<ResourceDisplayStatus> _displayStatus(
    String resourceId,
    bool hasTree,
  ) async {
    if (!hasTree) return ResourceDisplayStatus.saved;
    final session = await _studio.getLatestSessionForResource(resourceId);
    final readiness = await _readiness.read(resourceId);
    return resolveResourceDisplayStatus(
      hasTree: hasTree,
      session: session,
      readiness: readiness,
    );
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
