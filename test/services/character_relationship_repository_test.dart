import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/character_relationship.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/application/resources/legacy_resource_mapper.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/character_relationship_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ResourceTreeRepositoryImpl resources;
  late CharacterRelationshipRepositoryImpl relationships;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_relationships_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    resources =
        ResourceTreeRepositoryImpl(getDb: () => DatabaseService.database);
    relationships = CharacterRelationshipRepositoryImpl(
      getDb: () => DatabaseService.database,
    );
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('canonicalization keeps roles attached to their original endpoint', () {
    final endpoints = CharacterRelationshipEndpoints.canonicalize(
      firstResourceId: const ResourceId('res_b'),
      firstRole: 'mentor',
      secondResourceId: const ResourceId('res_a'),
      secondRole: 'student',
    );
    expect(endpoints.aResourceId.value, 'res_a');
    expect(endpoints.bResourceId.value, 'res_b');
    expect(endpoints.aRole, 'student');
    expect(endpoints.bRole, 'mentor');
  });

  test('creates, reads from either side, rejects duplicates, and updates',
      () async {
    final a =
        await resources.createResource(type: ResourceType.character, name: 'A');
    final b =
        await resources.createResource(type: ResourceType.character, name: 'B');
    final relation = await relationships.create(
      firstResourceId: b.id,
      firstRole: 'student',
      secondResourceId: a.id,
      secondRole: 'mentor',
      relationType: CharacterRelationshipType.mentorStudent,
      description: 'teaches',
    );
    expect(relation.endpointAResourceId, a.id);
    expect(relation.endpointARole, 'mentor');
    expect((await relationships.listForResource(b.id)).single.id, relation.id);
    await expectLater(
      relationships.create(
        firstResourceId: a.id,
        firstRole: 'mentor',
        secondResourceId: b.id,
        secondRole: 'student',
        relationType: CharacterRelationshipType.mentorStudent,
      ),
      throwsA(isA<CharacterRelationshipConflictException>()),
    );
    final updated = await relationships.update(
      id: relation.id,
      relationType: CharacterRelationshipType.custom,
      endpointARole: 'teacher',
      endpointBRole: 'learner',
      description: 'updated',
    );
    expect(updated.endpointAResourceId, a.id);
    expect(updated.description, 'updated');
  });

  test(
      'hidden while an endpoint is trashed and purge removes only touching edges',
      () async {
    final a =
        await resources.createResource(type: ResourceType.character, name: 'A');
    final b =
        await resources.createResource(type: ResourceType.character, name: 'B');
    final c =
        await resources.createResource(type: ResourceType.character, name: 'C');
    await relationships.create(
      firstResourceId: a.id,
      firstRole: 'friend',
      secondResourceId: b.id,
      secondRole: 'friend',
      relationType: CharacterRelationshipType.friend,
    );
    await relationships.create(
      firstResourceId: b.id,
      firstRole: 'friend',
      secondResourceId: c.id,
      secondRole: 'friend',
      relationType: CharacterRelationshipType.friend,
    );
    final db = await DatabaseService.database;
    await db.update('resources', {'deleted_at': 'trash'},
        where: 'id = ?', whereArgs: [a.id.value]);
    expect(await relationships.listForResource(b.id), hasLength(1));
    expect(
        (await relationships.listForResource(b.id)).single.endpointBResourceId,
        c.id);
    await relationships.deleteForResourcePurge(db, a.id);
    expect(await relationships.listForResource(b.id), hasLength(1));
  });

  test('fresh schema has relationship table, indexes, and constraints',
      () async {
    final db = await DatabaseService.database;
    expect(
        await DatabaseService.tableExists(
            db, 'resource_character_relationships'),
        isTrue);
    final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'resource_character_relationships'");
    expect(
        indexes.map((row) => row['name']),
        containsAll(<String>[
          'idx_resource_character_relationships_a',
          'idx_resource_character_relationships_b',
        ]));
    expect(DatabaseService.schemaVersion, 47);
    await expectLater(
      db.insert('resource_character_relationships', {
        'id': 'bad',
        'endpoint_a_resource_id': 'same',
        'endpoint_b_resource_id': 'same',
        'relation_type': 'friend',
        'endpoint_a_role': 'friend',
        'endpoint_b_role': 'friend',
        'description': '',
        'created_at': 'now',
        'updated_at': 'now',
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('v46 database upgrades without fabricating relationships', () async {
    final path = p.join(tempDir.path, 'upgrade.db');
    final old = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
          version: 46,
          onCreate: (db, _) async {
            await DatabaseService.createV44Schema(db);
            await DatabaseService.createRuntimeCheckpointSchema(db);
            await DatabaseService.createCreationLibrarySchema(db);
            await db.insert('character_cards', {
              'id': 'legacy-card',
              'name': 'Preserved',
              'json_data': '{}',
              'source': '',
              'created_at': 'now',
              'updated_at': 'now',
            });
          }),
    );
    await old.close();
    final upgraded = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 47,
        onUpgrade: (db, oldVersion, newVersion) =>
            DatabaseService.migrateStepByStep(db, oldVersion, newVersion),
      ),
    );
    expect(
        await DatabaseService.tableExists(
            upgraded, 'resource_character_relationships'),
        isTrue);
    expect(
        (await upgraded.query('character_cards')).single['id'], 'legacy-card');
    final count = await upgraded.rawQuery(
        'SELECT COUNT(*) AS count FROM resource_character_relationships');
    expect(count.single['count'], 0);
    await upgraded.close();
  });

  test('legacy resolver requires a live mapped unified resource', () async {
    final db = await DatabaseService.database;
    final mapped = LegacyResourceMapper.resourceIdFor(
      LegacySourceTables.characterCards,
      'legacy-1',
    );
    await db.insert('resources', {
      'id': mapped.value,
      'type': 'character',
      'name': 'Mapped',
      'summary': '',
      'status': 'draft',
      'metadata_json': '{}',
      'schema_version': 1,
      'created_at': 'now',
      'updated_at': 'now',
      'deleted_at': null,
    });
    expect(
      await LegacyResourceMapper.resolveLiveCharacterResourceId(
        db,
        sourceTable: LegacySourceTables.characterCards,
        legacyId: 'legacy-1',
      ),
      mapped,
    );
    await expectLater(
      LegacyResourceMapper.resolveLiveCharacterResourceId(
        db,
        sourceTable: LegacySourceTables.characterCards,
        legacyId: 'missing',
      ),
      throwsA(isA<LegacyResourceUnresolvedException>()),
    );
  });
}
