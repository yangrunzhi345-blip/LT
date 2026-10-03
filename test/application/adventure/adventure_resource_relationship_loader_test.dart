import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/adventure_resource_relationship_loader.dart';
import 'package:lt_dialogue/application/resources/legacy_resource_mapper.dart';
import 'package:lt_dialogue/domain/resources/character_relationship.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/character_relationship_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;

  setUp(() async {
    tempDir =
        await Directory.systemTemp.createTemp('lt_adventure_relationships_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('loads unified and legacy NPC identities at creation time', () async {
    final trees =
        ResourceTreeRepositoryImpl(getDb: () => DatabaseService.database);
    final relationships = CharacterRelationshipRepositoryImpl(
      getDb: () => DatabaseService.database,
    );
    final unified = await trees.createResource(
      type: ResourceType.character,
      name: '统一角色',
    );
    final legacyNpcId = LegacyResourceMapper.resourceIdFor(
      LegacySourceTables.npcCards,
      'npc-1',
    );
    await trees.createResourceTree(ResourceTreeDraft(
      id: legacyNpcId,
      type: ResourceType.npc,
      name: '旧 NPC',
    ));
    await relationships.create(
      firstResourceId: unified.id,
      firstRole: 'friend',
      secondResourceId: legacyNpcId,
      secondRole: 'friend',
      relationType: CharacterRelationshipType.friend,
    );

    final config = AdventureConfig(
      selectedCharacters: [
        AdventureSelectedCharacter(
          id: 'slot-a',
          characterId: unified.id.value,
          characterName: '统一角色',
        ),
        AdventureSelectedCharacter(
          id: 'slot-npc',
          characterId: 'npc-1',
          characterName: '旧 NPC',
        ),
      ],
    );
    final selection = await AdventureResourceRelationshipLoader(
      getDb: () => DatabaseService.database,
      relationshipRepository: relationships,
    ).load(config);

    expect(selection.relationships, hasLength(1));
    expect(selection.selectedResourceIds, contains(legacyNpcId.value));
    expect(selection.resourceIdToAdventureId[legacyNpcId.value], 'npc-1');
  });
}
