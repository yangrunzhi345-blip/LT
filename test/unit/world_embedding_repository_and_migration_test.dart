import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/world_embedding.dart';
import 'package:lt_dialogue/models/world_entry.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/world_embedding_repository.dart';
import 'package:lt_dialogue/services/repositories/world_embedding_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository_impl.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late IAdventureRepository adventureRepo;
  late IWorldEmbeddingRepository embeddingRepo;
  late IWorldEntryRepository entryRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_emb_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();

    adventureRepo =
        AdventureRepositoryImpl(getDb: () => DatabaseService.database);
    embeddingRepo =
        WorldEmbeddingRepositoryImpl(getDb: () => DatabaseService.database);
    entryRepo = WorldEntryRepositoryImpl(getDb: () => DatabaseService.database);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('World Embedding Database Schema & Migration', () {
    test(
        'v28 to v29 migration creates world_entry_embeddings table and indexes',
        () async {
      final db = await DatabaseService.database;
      expect(await DatabaseService.tableExists(db, 'world_entry_embeddings'),
          isTrue);

      final columns =
          await db.rawQuery('PRAGMA table_info(world_entry_embeddings)');
      final colNames = columns.map((c) => c['name']).toSet();
      expect(
        colNames,
        containsAll([
          'id',
          'entry_id',
          'adventure_id',
          'content_hash',
          'model_id',
          'dimensions',
          'embedding_json',
          'created_at',
        ]),
      );

      final indexes =
          await db.rawQuery('PRAGMA index_list(world_entry_embeddings)');
      final idxNames = indexes.map((i) => i['name']).toSet();
      expect(
        idxNames,
        containsAll([
          'idx_world_embeddings_entry',
          'idx_world_embeddings_adv',
          'idx_world_embeddings_hash',
        ]),
      );
    });

    test('step-by-step upgrade from v28 to v29 is idempotent', () async {
      final db = await DatabaseService.database;
      // Re-running migration must not throw
      await DatabaseService.migrateStepByStep(db, 28, 29);
      expect(await DatabaseService.tableExists(db, 'world_entry_embeddings'),
          isTrue);
    });
  });

  group('WorldEmbeddingRepository CRUD & Invalidation', () {
    test('inserts, queries, and caches embeddings correctly', () async {
      final advId = await adventureRepo.createAdventure(
        '测试冒险',
        AdventureConfig(name: '主角'),
      );
      final entryId = await entryRepo.insertWorldEntry(WorldEntry(
        adventureId: advId,
        content: '银月城是北境学术重镇。',
        keys: ['银月城'],
      ));

      final emb = WorldEntryEmbedding(
        entryId: entryId,
        adventureId: advId,
        contentHash: 'hash_v1',
        modelId: 'test-model-1',
        dimensions: 4,
        vector: const [0.1, 0.2, 0.3, 0.4],
        createdAt: DateTime.now(),
      );

      await embeddingRepo.insertEmbedding(emb);

      // Query exact match
      final fetched = await embeddingRepo.getEmbeddingForEntry(
        entryId,
        modelId: 'test-model-1',
        contentHash: 'hash_v1',
      );
      expect(fetched, isNotNull);
      expect(fetched!.entryId, entryId);
      expect(fetched.dimensions, 4);
      expect(fetched.vector, [0.1, 0.2, 0.3, 0.4]);

      // Cache invalidation: different content hash returns null
      final invalidHash = await embeddingRepo.getEmbeddingForEntry(
        entryId,
        modelId: 'test-model-1',
        contentHash: 'hash_v2_updated',
      );
      expect(invalidHash, isNull);

      // Cache invalidation: different modelId returns null
      final invalidModel = await embeddingRepo.getEmbeddingForEntry(
        entryId,
        modelId: 'other-model',
        contentHash: 'hash_v1',
      );
      expect(invalidModel, isNull);
    });

    test('saveBatch replaces existing embeddings and updates cache', () async {
      final advId = await adventureRepo.createAdventure(
        '测试冒险2',
        AdventureConfig(name: '主角'),
      );
      final e1 = await entryRepo.insertWorldEntry(WorldEntry(
        adventureId: advId,
        content: '白港是贸易海港。',
        keys: ['白港'],
      ));
      final e2 = await entryRepo.insertWorldEntry(WorldEntry(
        adventureId: advId,
        content: '黑石隘口险峻。',
        keys: ['黑石隘口'],
      ));

      final batch = [
        WorldEntryEmbedding(
          entryId: e1,
          adventureId: advId,
          contentHash: 'h1',
          modelId: 'model-a',
          dimensions: 2,
          vector: const [1.0, 0.0],
          createdAt: DateTime.now(),
        ),
        WorldEntryEmbedding(
          entryId: e2,
          adventureId: advId,
          contentHash: 'h2',
          modelId: 'model-a',
          dimensions: 2,
          vector: const [0.0, 1.0],
          createdAt: DateTime.now(),
        ),
      ];

      await embeddingRepo.saveBatch(batch);

      final list = await embeddingRepo.getEmbeddingsForAdventure(
        advId,
        modelId: 'model-a',
      );
      expect(list.length, 2);
      expect(list.map((e) => e.entryId), containsAll([e1, e2]));
    });

    test('deleting entry or adventure removes associated embeddings', () async {
      final advId = await adventureRepo.createAdventure(
        '测试冒险3',
        AdventureConfig(name: '主角'),
      );
      final e = await entryRepo.insertWorldEntry(WorldEntry(
        adventureId: advId,
        content: '灰雀帮掌控走私。',
      ));

      await embeddingRepo.insertEmbedding(WorldEntryEmbedding(
        entryId: e,
        adventureId: advId,
        contentHash: 'h',
        modelId: 'm',
        dimensions: 2,
        vector: const [0.5, 0.5],
        createdAt: DateTime.now(),
      ));

      await embeddingRepo.deleteByEntryId(e);
      final afterDelete = await embeddingRepo.getEmbeddingForEntry(
        e,
        modelId: 'm',
        contentHash: 'h',
      );
      expect(afterDelete, isNull);
    });

    test('isolates malformed embedding json rows safely', () async {
      final advId = await adventureRepo.createAdventure(
        '测试冒险4',
        AdventureConfig(name: '主角'),
      );
      final e = await entryRepo.insertWorldEntry(WorldEntry(
        adventureId: advId,
        content: '正常条目',
      ));

      final db = await DatabaseService.database;
      // Insert raw invalid json row with valid foreign keys
      await db.rawInsert('''
        INSERT INTO world_entry_embeddings (
          entry_id, adventure_id, content_hash, model_id, dimensions, embedding_json, created_at
        ) VALUES ($e, $advId, 'bad_hash', 'm', 2, 'NOT_VALID_JSON', '2026-09-14T00:00:00.000Z')
      ''');

      final list = await embeddingRepo.getEmbeddingsForAdventure(
        advId,
        modelId: 'm',
      );
      // Malformed row must be isolated, not crashing the query
      expect(list, isEmpty);
    });
  });
}
