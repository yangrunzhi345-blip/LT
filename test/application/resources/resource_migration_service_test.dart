import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/legacy_resource_mapper.dart';
import 'package:lt_dialogue/application/resources/resource_migration_service.dart';
import 'package:lt_dialogue/application/resources/resource_read_facade.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Phase 2 migration + compatibility-read tests against a real database.
///
/// Covers the properties the phase exists for: legacy rows migrate losslessly,
/// re-running changes nothing, a broken row only affects itself, and reads
/// prefer the tree while the legacy table remains the fallback.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ResourceTreeRepositoryImpl treeRepository;
  late ResourceMigrationService service;
  late ResourceReadFacade facade;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_phase2_migration_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    treeRepository =
        ResourceTreeRepositoryImpl(getDb: () => DatabaseService.database);
    service = ResourceMigrationService(
      getDb: () => DatabaseService.database,
      treeRepository: treeRepository,
    );
    facade = ResourceReadFacade(
      getDb: () => DatabaseService.database,
      treeRepository: treeRepository,
      migrationService: service,
    );
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  // ─── Fixtures mirroring the real legacy shapes ───

  String simpleWorldviewDetail(String summary) => jsonEncode(<String, Object?>{
        'format_version': 2,
        'mode': 'simple',
        'modules': <String, Object?>{
          'overview': <String, Object?>{
            'summary': summary,
            'status': 'confirmed',
          },
        },
      });

  String detailedWorldviewDetail() {
    final modules = <String, Object?>{
      for (final key in LegacyResourceMapper.worldviewModuleTitles.keys)
        key: <String, Object?>{
          key == 'overview' ? 'summary' : 'content': '$key 的正文内容文本',
          'status': 'confirmed',
        },
    };
    modules['locations'] = <String, Object?>{
      'content': '地点总述',
      'status': 'confirmed',
      'items': <Object?>[
        {'name': '银月城', 'description': '学术重镇'},
      ],
    };
    return jsonEncode(<String, Object?>{
      'format_version': 2,
      'mode': 'detailed',
      'modules': modules,
    });
  }

  Future<void> insertWorldview({
    required String id,
    required String name,
    required String description,
    String? detailJson,
    String entriesJson = '[]',
    String authoringMethod = 'manual',
    String aiDepth = '',
  }) async {
    final db = await DatabaseService.database;
    await db.insert('worldview_presets', {
      'id': id,
      'name': name,
      'description': description,
      'entries_json': entriesJson,
      'detail_json': detailJson ?? simpleWorldviewDetail(description),
      'created_at': '2026-09-15T00:00:00.000',
      'updated_at': '2026-09-15T00:00:00.000',
      'authoring_method': authoringMethod,
      'ai_generation_depth': aiDepth,
    });
  }

  Future<void> insertCard({
    required String table,
    required String id,
    required String name,
    required String jsonData,
    String source = '',
    String matchingWorldviewId = '',
  }) async {
    final db = await DatabaseService.database;
    await db.insert(table, {
      'id': id,
      'name': name,
      'json_data': jsonData,
      'source': source,
      'matching_worldview_id': matchingWorldviewId,
      'created_at': '2026-09-15T00:00:00.000',
      'updated_at': '2026-09-15T00:00:00.000',
      'authoring_method': 'manual',
      'ai_generation_depth': '',
    });
  }

  Future<Map<String, int>> treeCounts() async {
    final db = await DatabaseService.database;
    Future<int> count(String table) async {
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
      return (rows.first['c'] as num).toInt();
    }

    return {
      'resources': await count('resources'),
      'sections': await count('resource_sections'),
      'parts': await count('resource_parts'),
    };
  }

  group('migration schema (v32)', () {
    test('fresh install creates the audit table', () async {
      final db = await DatabaseService.database;
      expect(
        await DatabaseService.tableExists(db, 'resource_migration_records'),
        isTrue,
      );
      final columns = await db.rawQuery(
        'PRAGMA table_info(resource_migration_records)',
      );
      expect(
        columns.map((column) => column['name']),
        containsAll(<String>[
          'source_table',
          'source_id',
          'migration_version',
          'source_hash',
          'status',
          'resource_id',
          'error_reason',
          'raw_payload',
        ]),
      );
      final version = await db.rawQuery('PRAGMA user_version');
      expect(
        (version.first.values.first as num).toInt(),
        DatabaseService.schemaVersion,
      );
    });
  });

  group('migration', () {
    test('maps every legacy source and keeps the legacy rows intact', () async {
      await insertWorldview(
        id: 'wv_simple',
        name: '银月大陆',
        description: '北境学术重镇。' * 15,
      );
      await insertWorldview(
        id: 'wv_detailed',
        name: '详细世界观',
        description: '描述',
        detailJson: detailedWorldviewDetail(),
        entriesJson: jsonEncode(<Object?>[
          {
            'keys': ['银月城'],
            'content': '银月城正文',
            'probability': 80
          },
        ]),
        authoringMethod: 'aiReference',
        aiDepth: 'detailed',
      );
      await insertCard(
        table: 'character_cards',
        id: 'card_1',
        name: '艾莲娜',
        jsonData: jsonEncode(<String, Object?>{
          'spec': 'chara_card_v2',
          'data': <String, Object?>{
            'name': '艾莲娜',
            'description': '北境的学者。' * 20,
            'first_mes': '「你也来找那本书？」',
            'custom_attributes': <Object?>[
              {'name': '魔力', 'value': 'A 级', 'importance': 'high'},
            ],
          },
        }),
        source: 'chub.ai',
        matchingWorldviewId: 'wv_simple',
      );
      await insertCard(
        table: 'npc_cards',
        id: 'npc_1',
        name: '酒馆老板',
        jsonData: jsonEncode(<String, Object?>{
          'name': '酒馆老板',
          'description': '健谈的中年人',
        }),
        matchingWorldviewId: 'wv_simple',
      );

      final stats = await service.run();
      expect(stats.total, 4);
      expect(stats.migrated, 4);
      expect(stats.failed, 0);
      expect(stats.skipped, 0);

      final counts = await treeCounts();
      expect(counts['resources'], 4);

      // Names survive.
      final simple = await treeRepository.readTree(
        LegacyResourceMapper.resourceIdFor(
            LegacySourceTables.worldviewPresets, 'wv_simple'),
      );
      expect(simple!.resource.name, '银月大陆');
      expect(simple.resource.type, ResourceType.worldview);
      expect(
        simple.resource
            .metadata[LegacyResourceMapper.metadataMatchingWorldviewId],
        '',
      );

      final card = await treeRepository.readTree(
        LegacyResourceMapper.resourceIdFor(
            LegacySourceTables.characterCards, 'card_1'),
      );
      expect(card!.resource.name, '艾莲娜');
      expect(card.resource.type, ResourceType.character);
      expect(
        card.resource
            .metadata[LegacyResourceMapper.metadataMatchingWorldviewId],
        'wv_simple',
      );
      // The runtime prose exists once, as a Part referenced by metadata.
      final refs =
          card.resource.metadata[LegacyResourceMapper.metadataRuntimeNodeRefs]
              as Map<String, Object?>;
      final firstMesPartId = refs['first_mes'] as String;
      expect(
        card.parts.where((part) => part.id.value == firstMesPartId),
        hasLength(1),
      );

      final npc = await treeRepository.readTree(
        LegacyResourceMapper.resourceIdFor(
            LegacySourceTables.npcCards, 'npc_1'),
      );
      expect(npc!.resource.type, ResourceType.npc);
      expect(npc.resource.name, '酒馆老板');

      // Legacy rows are never modified or deleted.
      final db = await DatabaseService.database;
      expect(await db.query('worldview_presets'), hasLength(2));
      expect(await db.query('character_cards'), hasLength(1));
      expect(await db.query('npc_cards'), hasLength(1));
    });

    test('a second run adds no duplicate node and changes nothing', () async {
      await insertWorldview(id: 'wv_1', name: 'A', description: '描述 A');
      await insertCard(
        table: 'character_cards',
        id: 'card_1',
        name: 'B',
        jsonData:
            jsonEncode(<String, Object?>{'name': 'B', 'description': '描述 B'}),
      );

      final first = await service.run();
      expect(first.migrated, 2);
      final afterFirst = await treeCounts();

      final second = await service.run();
      expect(second.migrated, 0);
      expect(second.skipped, 2);
      expect(second.failed, 0);

      final afterSecond = await treeCounts();
      expect(afterSecond, equals(afterFirst));
    });

    test('a changed legacy row is recorded and never overwrites the tree',
        () async {
      await insertWorldview(id: 'wv_edit', name: 'A', description: '原描述');
      await service.run();
      final before = await treeCounts();
      final beforeTree = await treeRepository.readTree(
        LegacyResourceMapper.resourceIdFor(
            LegacySourceTables.worldviewPresets, 'wv_edit'),
      );
      final beforeText =
          beforeTree!.parts.map((part) => part.content).join('\n');

      final db = await DatabaseService.database;
      await db.update(
        'worldview_presets',
        {'description': '用户后来改的描述'},
        where: 'id = ?',
        whereArgs: ['wv_edit'],
      );

      final stats = await service.run();
      expect(stats.sourceChanged, 1);
      expect(stats.migrated, 0);
      expect(await treeCounts(), equals(before));

      final record = await service.readRecord(
        sourceTable: LegacySourceTables.worldviewPresets,
        sourceId: 'wv_edit',
      );
      expect(record!.outcome, ResourceMigrationOutcome.sourceChanged);

      // The migrated tree keeps the original content.
      final afterTree = await treeRepository.readTree(
        LegacyResourceMapper.resourceIdFor(
            LegacySourceTables.worldviewPresets, 'wv_edit'),
      );
      expect(
        afterTree!.parts.map((part) => part.content).join('\n'),
        beforeText,
      );

      // A compatible read shows the user's newest content from the legacy row.
      final read = await facade.readPreferringTree(
        type: ResourceType.worldview,
        legacyId: 'wv_edit',
      );
      expect(read.isFromTree, isFalse);
      expect(read.fallbackReason, ResourceReadFallbackReason.sourceChanged);
      expect(read.legacyRow!['description'], '用户后来改的描述');
    });

    test('a damaged row is isolated and reported without touching the row',
        () async {
      await insertWorldview(id: 'wv_ok', name: '正常', description: '正常描述');
      await insertCard(
        table: 'character_cards',
        id: 'card_broken',
        name: '坏卡',
        jsonData: '{"name": "坏卡"',
      );
      await insertCard(
        table: 'character_cards',
        id: 'card_ok',
        name: '正常卡',
        jsonData:
            jsonEncode(<String, Object?>{'name': '正常卡', 'description': '正常'}),
      );

      final stats = await service.run();
      expect(stats.total, 3);
      expect(stats.migrated, 2);
      expect(stats.failed, 1);
      expect(stats.hasFailures, isTrue);
      expect(stats.failures.single.sourceId, 'card_broken');

      // The broken row is still there, byte for byte, and no resource was made.
      final db = await DatabaseService.database;
      final broken = await db.query(
        'character_cards',
        where: 'id = ?',
        whereArgs: ['card_broken'],
      );
      expect(broken.single['json_data'], '{"name": "坏卡"');
      expect(
        await treeRepository.findResource(
          LegacyResourceMapper.resourceIdFor(
              LegacySourceTables.characterCards, 'card_broken'),
        ),
        isNull,
      );

      // The failure is diagnosable: reason and isolated raw payload.
      final record = await service.readRecord(
        sourceTable: LegacySourceTables.characterCards,
        sourceId: 'card_broken',
      );
      expect(record!.outcome, ResourceMigrationOutcome.failed);
      expect(record.errorReason, isNotEmpty);
      final rows = await db.query(
        'resource_migration_records',
        where: 'source_id = ?',
        whereArgs: ['card_broken'],
      );
      expect(rows.single['raw_payload'], '{"name": "坏卡"');

      // The healthy resources were unaffected.
      expect(
        await treeRepository.findResource(
          LegacyResourceMapper.resourceIdFor(
              LegacySourceTables.characterCards, 'card_ok'),
        ),
        isNotNull,
      );
    });

    test('a failure inside one resource rolls back only that resource',
        () async {
      // Seed a colliding Part id so the character migration fails mid-insert,
      // after its resource and section rows were written.
      final db = await DatabaseService.database;
      await db.insert('resources', {
        'id': 'res_placeholder',
        'type': 'npc',
        'name': '占位',
        'summary': '',
        'status': 'draft',
        'metadata_json': '{}',
        'schema_version': 1,
        'created_at': '2026-09-15T00:00:00.000',
        'updated_at': '2026-09-15T00:00:00.000',
      });
      await db.insert('resource_sections', {
        'id': 'sec_placeholder',
        'resource_id': 'res_placeholder',
        'title': 'T',
        'summary': '',
        'sort_order': 0,
        'status': 'draft',
        'created_at': '2026-09-15T00:00:00.000',
        'updated_at': '2026-09-15T00:00:00.000',
      });
      await db.insert('resource_parts', {
        'id': 'part_legacy_character_cards_card_clash_description',
        'section_id': 'sec_placeholder',
        'title': '撞击',
        'content': '占位内容',
        'sort_order': 0,
        'status': 'draft',
        'content_hash': 'h',
        'created_at': '2026-09-15T00:00:00.000',
        'updated_at': '2026-09-15T00:00:00.000',
      });

      await insertCard(
        table: 'character_cards',
        id: 'card_clash',
        name: '冲突卡',
        jsonData: jsonEncode(<String, Object?>{
          'name': '冲突卡',
          'description': '会被回滚的描述',
        }),
      );
      await insertWorldview(id: 'wv_fine', name: '正常', description: '正常描述');

      final stats = await service.run();
      expect(stats.failed, 1);
      expect(stats.migrated, 1);
      expect(stats.failures.single.sourceId, 'card_clash');

      // No half-written tree: the resource row that would own the clashing
      // Part is gone, while the placeholder tree is untouched.
      expect(
        await treeRepository.findResource(
          LegacyResourceMapper.resourceIdFor(
              LegacySourceTables.characterCards, 'card_clash'),
        ),
        isNull,
      );
      final orphanSections = await db.query(
        'resource_sections',
        where: 'resource_id = ?',
        whereArgs: [
          LegacyResourceMapper.resourceIdFor(
                  LegacySourceTables.characterCards, 'card_clash')
              .value,
        ],
      );
      expect(orphanSections, isEmpty);
      expect(
        await treeRepository.findResource(
          LegacyResourceMapper.resourceIdFor(
              LegacySourceTables.worldviewPresets, 'wv_fine'),
        ),
        isNotNull,
      );
    });

    test('migration statistics carry no resource body text', () async {
      await insertWorldview(
        id: 'wv_stats',
        name: '统计',
        description: '不应出现在统计里的正文内容',
      );
      final stats = await service.run();
      expect(stats.toString().contains('不应出现在统计里'), isFalse);
    });
  });

  group('compatibility read', () {
    test('falls back to the legacy row before any migration', () async {
      await insertWorldview(id: 'wv_pre', name: '未迁移', description: '描述');

      final read = await facade.readPreferringTree(
        type: ResourceType.worldview,
        legacyId: 'wv_pre',
      );
      expect(read.isFromTree, isFalse);
      expect(read.fallbackReason, ResourceReadFallbackReason.notMigrated);
      expect(read.tree, isNull);
      expect(read.legacyRow!['name'], '未迁移');
    });

    test('prefers the migrated tree once it is current', () async {
      await insertWorldview(id: 'wv_done', name: '已迁移', description: '描述');
      await service.run();

      final read = await facade.readPreferringTree(
        type: ResourceType.worldview,
        legacyId: 'wv_done',
      );
      expect(read.isFromTree, isTrue);
      expect(read.fallbackReason, ResourceReadFallbackReason.none);
      expect(read.tree!.resource.name, '已迁移');
      expect(read.legacyRow, isNull);
    });

    test('reports a failed migration and still serves the legacy row',
        () async {
      await insertCard(
        table: 'npc_cards',
        id: 'npc_broken',
        name: '坏 NPC',
        jsonData: 'not json at all',
      );
      await service.run();

      final read = await facade.readPreferringTree(
        type: ResourceType.npc,
        legacyId: 'npc_broken',
      );
      expect(read.isFromTree, isFalse);
      expect(read.fallbackReason, ResourceReadFallbackReason.migrationFailed);
      expect(read.legacyRow!['name'], '坏 NPC');
    });

    test('a resource that exists only in the new tree still reads', () async {
      // No legacy row and no audit record: the new model answered.
      await treeRepository.createResourceTree(ResourceTreeDraft(
        id: LegacyResourceMapper.resourceIdFor(
            LegacySourceTables.characterCards, 'card_tree_only'),
        type: ResourceType.character,
        name: '新模型角色',
        sections: const [
          ResourceTreeSectionDraft(
            title: '概述',
            parts: [ResourceTreePartDraft(title: '概述', content: '正文')],
          ),
        ],
      ));

      final read = await facade.readPreferringTree(
        type: ResourceType.character,
        legacyId: 'card_tree_only',
      );
      expect(read.isFromTree, isTrue);
      expect(read.tree!.resource.name, '新模型角色');
    });

    test('an unknown id reports the missing legacy record', () async {
      final read = await facade.readPreferringTree(
        type: ResourceType.worldview,
        legacyId: 'wv_missing',
      );
      expect(read.isFromTree, isFalse);
      expect(read.fallbackReason, ResourceReadFallbackReason.legacyMissing);
      expect(read.legacyRow, isNull);
    });

    test('the legacy table is never written by a compatibility read', () async {
      await insertWorldview(id: 'wv_readonly', name: '只读', description: '描述');
      final db = await DatabaseService.database;
      final before = await db.query('worldview_presets');
      await service.run();
      await facade.readPreferringTree(
        type: ResourceType.worldview,
        legacyId: 'wv_readonly',
      );
      final after = await db.query('worldview_presets');
      expect(after, equals(before));
    });
  });
}
