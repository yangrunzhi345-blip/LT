import '../../../../application/resource_library/edit_drafts.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../models/resource_library_mode.dart';
import '../../../../models/tracked_state_definition.dart';
import '../../../../services/repositories/library_repository.dart';
import '../../domain/models/character_status_library_view_state.dart';

/// Read-only projection source for the Character Status library surface.
///
/// It flattens the monitoring **definitions** already stored on character and
/// NPC resources. It never creates a definition, never persists anything and
/// never reads adventure runtime state.
abstract interface class CharacterStatusLibraryRuntime {
  Future<List<CharacterStatusLibraryEntry>> load(ResourceLibraryMode mode);
}

/// Production projection backed by the existing library repository.
///
/// Reads the character and NPC card lists in two batched queries (the same
/// lists the library itself loads) and decodes `tracked_state_definitions`
/// through the shared draft parsers, so a resource never needs a second
/// storage path for its definitions.
final class ProductionCharacterStatusLibraryRuntime
    implements CharacterStatusLibraryRuntime {
  const ProductionCharacterStatusLibraryRuntime({
    required ILibraryRepository repository,
  }) : _repository = repository;

  final ILibraryRepository _repository;

  @override
  Future<List<CharacterStatusLibraryEntry>> load(
      ResourceLibraryMode mode) async {
    final rows = await Future.wait(<Future<List<Map<String, dynamic>>>>[
      _repository.getCharacterCards(mode: mode),
      _repository.getNpcCards(mode: mode),
    ]);

    final entries = <CharacterStatusLibraryEntry>[];
    for (final group in <(ResourceType, List<Map<String, dynamic>>)>[
      (ResourceType.character, rows[0]),
      (ResourceType.npc, rows[1]),
    ]) {
      for (final row in group.$2) {
        final id = row['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final definitions = _definitions(group.$1, row);
        if (definitions.isEmpty) continue;
        entries.add(CharacterStatusLibraryEntry(
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
      // The character status surface never reads worldview definitions.
      ResourceType.worldview => const <TrackedStateDefinition>[],
    };
  }
}
