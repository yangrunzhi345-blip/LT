import 'package:sqflite/sqflite.dart';

import '../../domain/resources/character_relationship.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../models/adventure_config.dart';
import '../../services/repositories/character_relationship_repository.dart';
import '../resources/legacy_resource_mapper.dart';
import 'adventure_character_identity.dart';

/// The resource edges and identity map resolved at Adventure creation time.
final class AdventureResourceRelationshipSelection {
  const AdventureResourceRelationshipSelection({
    required this.relationships,
    required this.selectedResourceIds,
    required this.resourceIdToAdventureId,
  });

  final List<CharacterRelationship> relationships;
  final Set<String> selectedResourceIds;
  final Map<String, String> resourceIdToAdventureId;
}

/// Resolves the legacy character-card ids used by the wizard to live resource
/// ids before projecting library relationships into an Adventure snapshot.
///
/// Unresolved legacy rows are skipped. They cannot be used as relationship
/// endpoints, and preserving the existing wizard-only relationship data is
/// safer than inventing a resource identity.
final class AdventureResourceRelationshipLoader {
  const AdventureResourceRelationshipLoader({
    required this.getDb,
    required this.relationshipRepository,
  });

  final Future<Database> Function() getDb;
  final CharacterRelationshipRepository relationshipRepository;

  Future<AdventureResourceRelationshipSelection> load(
    AdventureConfig config,
  ) async {
    final selectedResourceIds = <String>{};
    final resourceIdToAdventureId = <String, String>{};
    final db = await getDb();

    for (final selected in config.selectedCharacters) {
      final adventureId = AdventureCharacterIdentity.effectiveId(selected);
      if (adventureId.isEmpty) continue;
      ResourceId? resourceId;
      if (adventureId.startsWith('res_')) {
        resourceId = ResourceId(adventureId);
      } else {
        for (final sourceTable in const [
          LegacySourceTables.characterCards,
          LegacySourceTables.npcCards,
        ]) {
          try {
            resourceId =
                await LegacyResourceMapper.resolveLiveCharacterResourceId(
              db,
              sourceTable: sourceTable,
              legacyId: adventureId,
            );
            break;
          } on LegacyResourceUnresolvedException {
            // The same legacy id may come from either card table. Keep trying
            // the explicit mappings before treating it as unavailable.
          }
        }
        if (resourceId == null) continue;
      }
      selectedResourceIds.add(resourceId.value);
      resourceIdToAdventureId[resourceId.value] = adventureId;
    }

    final relationshipsById = <String, CharacterRelationship>{};
    for (final resourceId in selectedResourceIds) {
      for (final relationship in await relationshipRepository.listForResource(
        ResourceId(resourceId),
      )) {
        relationshipsById[relationship.id] = relationship;
      }
    }

    return AdventureResourceRelationshipSelection(
      relationships: List.unmodifiable(relationshipsById.values),
      selectedResourceIds: Set.unmodifiable(selectedResourceIds),
      resourceIdToAdventureId: Map.unmodifiable(resourceIdToAdventureId),
    );
  }
}
