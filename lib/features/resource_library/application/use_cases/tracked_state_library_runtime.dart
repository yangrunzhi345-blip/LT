import '../../../../application/resource_library/edit_drafts.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../models/resource_library_mode.dart';
import '../../../../models/tracked_state_definition.dart';
import '../../../../services/repositories/library_repository.dart';
import '../../domain/models/tracked_state_library_view_state.dart';

/// Read-only projection source for the Resource Library「检测项目」surface.
///
/// It flattens the monitoring **definitions** already stored on character, NPC
/// and worldview resources. It never creates a definition, never persists
/// anything and never reads adventure runtime state.
abstract interface class TrackedStateLibraryRuntime {
  /// Owner resources (character / NPC / worldview) that declare definitions.
  Future<List<TrackedStateLibraryEntry>> load(ResourceLibraryMode mode);

  /// The raw stored row of one owner resource, for the focused definition
  /// editor. It returns the row the projection itself reads, so editing never
  /// needs a second storage path. Null when the resource cannot be found.
  Future<Map<String, dynamic>?> loadOwnerRow({
    required ResourceType type,
    required String resourceId,
    required ResourceLibraryMode mode,
  });
}

/// Production projection backed by the existing library repository.
///
/// Reads the character, NPC and worldview lists in three batched queries (the
/// same lists the library itself loads) and decodes `tracked_state_definitions`
/// through the shared draft parsers, so a resource never needs a second storage
/// path for its definitions.
final class ProductionTrackedStateLibraryRuntime
    implements TrackedStateLibraryRuntime {
  const ProductionTrackedStateLibraryRuntime({
    required ILibraryRepository repository,
  }) : _repository = repository;

  final ILibraryRepository _repository;

  @override
  Future<List<TrackedStateLibraryEntry>> load(ResourceLibraryMode mode) async {
    final rows = await _loadRows(mode);

    final entries = <TrackedStateLibraryEntry>[];
    for (final group in rows) {
      for (final row in group.$2) {
        final id = row['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final definitions = _definitions(group.$1, row);
        if (definitions.isEmpty) continue;
        entries.add(TrackedStateLibraryEntry(
          resourceId: id,
          ownerType: group.$1,
          ownerName: row['name']?.toString().trim() ?? '',
          updatedAt: row['updated_at']?.toString() ?? '',
          definitions: List<TrackedStateDefinition>.unmodifiable(definitions),
        ));
      }
    }
    return entries;
  }

  @override
  Future<Map<String, dynamic>?> loadOwnerRow({
    required ResourceType type,
    required String resourceId,
    required ResourceLibraryMode mode,
  }) async {
    final rows = await _loadRows(mode);
    for (final group in rows) {
      if (group.$1 != type) continue;
      for (final row in group.$2) {
        if (row['id']?.toString() == resourceId) {
          return Map<String, dynamic>.from(row);
        }
      }
    }
    return null;
  }

  /// One batched read per resource type, so listing N owners never becomes N
  /// queries.
  Future<List<(ResourceType, List<Map<String, dynamic>>)>> _loadRows(
    ResourceLibraryMode mode,
  ) async {
    final results = await Future.wait(<Future<List<Map<String, dynamic>>>>[
      _repository.getCharacterCards(mode: mode),
      _repository.getNpcCards(mode: mode),
      _repository.getWorldviewPresets(mode: mode),
    ]);
    return [
      (ResourceType.character, results[0]),
      (ResourceType.npc, results[1]),
      (ResourceType.worldview, results[2]),
    ];
  }

  List<TrackedStateDefinition> _definitions(
    ResourceType type,
    Map<String, dynamic> row,
  ) {
    final map = Map<String, dynamic>.from(row);
    return switch (type) {
      ResourceType.character =>
        CharacterCardEditDraft.fromExisting(map).trackedStateDefinitions,
      ResourceType.npc =>
        NpcEditDraft.fromExisting(map).trackedStateDefinitions,
      ResourceType.worldview =>
        WorldviewEditDraft.fromExisting(map).trackedStateDefinitions,
    };
  }
}
