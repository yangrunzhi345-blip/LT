import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/adventure_resource_relationship_loader.dart';
import 'package:lt_dialogue/application/adventure/resource_relationship_projection.dart';
import 'package:lt_dialogue/application/resources/legacy_resource_mapper.dart';
import 'package:lt_dialogue/domain/resources/character_relationship.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/runtime_relationship_state.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/character_relationship_repository.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
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

  test(
      'should isolate the frozen runtime from resource edits, deletion and purge',
      () async {
    final trees =
        ResourceTreeRepositoryImpl(getDb: () => DatabaseService.database);
    final relationships = CharacterRelationshipRepositoryImpl(
        getDb: () => DatabaseService.database);
    final adventures =
        AdventureRepositoryImpl(getDb: () => DatabaseService.database);
    final a =
        await trees.createResource(type: ResourceType.character, name: 'Alice');
    final b =
        await trees.createResource(type: ResourceType.character, name: 'Bob');
    final edge = await relationships.create(
      firstResourceId: a.id,
      firstRole: 'friend',
      secondResourceId: b.id,
      secondRole: 'friend',
      relationType: CharacterRelationshipType.friend,
      description: 'frozen ally',
    );
    final roster = AdventureConfig(name: 'Alice', selectedCharacters: [
      AdventureSelectedCharacter(
          id: 'a',
          characterId: a.id.value,
          characterName: 'Alice',
          isProtagonist: true),
      AdventureSelectedCharacter(
          id: 'b', characterId: b.id.value, characterName: 'Bob'),
    ]);
    final selection = await AdventureResourceRelationshipLoader(
      getDb: () => DatabaseService.database,
      relationshipRepository: relationships,
    ).load(roster);
    final config = roster.copyWith(
        characterRelationships: ResourceRelationshipProjection.project(
      relationships: selection.relationships,
      selectedResourceIds: selection.selectedResourceIds,
      resourceIdToAdventureId: selection.resourceIdToAdventureId,
    ));
    final id = await adventures.createAdventure('frozen relationships', config);
    await adventures.seedRuntimeEntity(
        adventureId: id,
        branchId: 0,
        entityType: RuntimeEntityType.relationship,
        entityId: edge.id);
    await adventures.commitRuntimeMutation(RuntimeStateMutation(
      requestId: 'isolated-runtime',
      adventureId: id,
      branchId: 0,
      draft: RuntimeStateCommitDraft(
          expectedRevision: 0,
          summary: 'Runtime enemy',
          changes: [
            RuntimeStateChangeProposal(
                entityType: RuntimeEntityType.relationship,
                entityId: edge.id,
                changeKind: RuntimeChangeKind.primary,
                operation: RuntimeChangeOperation.set,
                path: 'relationship',
                value: 'enemy',
                reason: 'Story change'),
          ]),
    ));
    expect((await relationships.getById(edge.id))!.relationType,
        CharacterRelationshipType.friend);
    await relationships.update(
        id: edge.id,
        relationType: CharacterRelationshipType.rival,
        endpointARole: 'rival',
        endpointBRole: 'rival',
        description: 'resource rival');

    Future<void> verifyFrozenRuntime() async {
      final row = await adventures.getAdventureById(id);
      final frozen = AdventureConfig.fromJson(
          jsonDecode(row!['config'] as String) as Map<String, dynamic>);
      expect(frozen.characterRelationships.single.description, 'frozen ally');
      expect(frozen.characterRelationships.single.relationType,
          AdventureRelationType.friend);
      final current =
          await adventures.getCurrentRuntimeState(adventureId: id, branchId: 0);
      final projected = RuntimeRelationshipProjection.project(
          snapshot: frozen.characterRelationships,
          runtimeEntities: current.entities.values,
          runtimeRevision: current.revision);
      expect(projected.single.effectiveRelation, 'enemy');
      expect(projected.single.effectiveNotes, 'frozen ally');
      expect(
          (await adventures.getRuntimeStateAtRevision(
                  adventureId: id, branchId: 0, revision: 1))
              .entities['relationship:${edge.id}']!
              .overlay['relationship'],
          'enemy');
    }

    await verifyFrozenRuntime();
    final node = await trees.readNodeState(a.id);
    await trees.softDeleteNode(id: a.id, expectedUpdatedAt: node!.updatedAt);
    expect(await relationships.listForResource(b.id), isEmpty);
    await verifyFrozenRuntime();
    final db = await DatabaseService.database;
    await db.transaction((txn) async {
      await relationships.deleteForResourcePurge(txn, a.id);
      await trees.purgeNodeInTransaction(txn, a.id);
    });
    expect(await relationships.getById(edge.id), isNull);
    await verifyFrozenRuntime();
  });
}
