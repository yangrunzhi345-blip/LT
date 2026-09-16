import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/legacy_creation_bridge.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Phase 3 entry rewiring: `updateResourceTree` plus the bridge that every
/// legacy entry now saves through.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ResourceTreeRepositoryImpl treeRepository;
  late ResourceCreationPipeline pipeline;
  late LegacyCreationBridge bridge;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_phase3_upsert_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    treeRepository =
        ResourceTreeRepositoryImpl(getDb: () => DatabaseService.database);
    pipeline = ResourceCreationPipeline(
      getDb: () => DatabaseService.database,
      hasAiCredentials: () => true,
      treeRepository: treeRepository,
    );
    bridge = LegacyCreationBridge(pipeline);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<Map<String, int>> counts() async {
    final db = await DatabaseService.database;
    Future<int> count(String table) async {
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
      return (rows.first['c'] as num).toInt();
    }

    return {
      'resources': await count('resources'),
      'sections': await count('resource_sections'),
      'parts': await count('resource_parts'),
      'sessions': await count(ResourceCreationPipeline.table),
    };
  }

  String worldviewDetail(String overview, String rules) => jsonEncode({
        'modules': {
          'overview': {'summary': overview, 'status': 'confirmed'},
          'world_rules': {'content': rules, 'status': 'confirmed'},
        },
      });

  group('updateResourceTree', () {
    test('replaces the tree in place and keeps the identity', () async {
      await treeRepository.createResourceTree(const ResourceTreeDraft(
        id: ResourceId('res_keep'),
        type: ResourceType.worldview,
        name: '原名',
        sections: [
          ResourceTreeSectionDraft(
            id: SectionId('sec_old'),
            title: '旧章节',
            parts: [ResourceTreePartDraft(title: '旧', content: '旧内容')],
          ),
        ],
      ));

      await treeRepository.updateResourceTree(const ResourceTreeDraft(
        id: ResourceId('res_keep'),
        type: ResourceType.worldview,
        name: '新名',
        sections: [
          ResourceTreeSectionDraft(
            id: SectionId('sec_new'),
            title: '新章节',
            parts: [
              ResourceTreePartDraft(title: '新一', content: '内容一'),
              ResourceTreePartDraft(title: '新二', content: '内容二'),
            ],
          ),
        ],
      ));

      final tree = await treeRepository.readTree(const ResourceId('res_keep'));
      expect(tree, isNotNull);
      expect(tree!.resource.name, '新名');
      expect(tree.sections.map((section) => section.title), ['新章节']);
      expect(tree.parts.map((part) => part.content), ['内容一', '内容二']);

      // The replaced rows are gone: no orphan section or part remains.
      final db = await DatabaseService.database;
      expect(
        await db.query('resource_sections',
            where: 'id = ?', whereArgs: ['sec_old']),
        isEmpty,
      );
      final total = await counts();
      expect(total['sections'], 1);
      expect(total['parts'], 2);
    });

    test('refuses to update a resource that does not exist', () async {
      await expectLater(
        treeRepository.updateResourceTree(const ResourceTreeDraft(
          id: ResourceId('res_missing'),
          type: ResourceType.worldview,
          name: 'X',
        )),
        throwsA(isA<ResourceTreeNotFoundException>()),
      );
    });
  });

  group('entry saves upsert instead of duplicating', () {
    test('saving the same worldview twice keeps one resource', () async {
      final first = await bridge.saveWorldview(
        id: 'wv_entry',
        name: '银月大陆',
        description: '描述',
        detailJson: worldviewDetail('总览', '法则'),
        entriesJson: '[]',
        mode: 'adventure',
        origin: 'test.entry',
      );
      expect(first.resourceId, const ResourceId('wv_entry'));

      final second = await bridge.saveWorldview(
        id: 'wv_entry',
        name: '银月大陆',
        description: '描述',
        detailJson: worldviewDetail('总览', '法则'),
        entriesJson: '[]',
        mode: 'adventure',
        origin: 'test.entry',
      );

      // Identical content is idempotent: same key, same result, one resource.
      expect(second.reusedExisting, isTrue);
      final after = await counts();
      expect(after['resources'], 1);
      expect(after['sessions'], 1);
    });

    test('editing an entry resource updates it in place', () async {
      await bridge.saveWorldview(
        id: 'wv_edit',
        name: '原名',
        description: '描述',
        detailJson: worldviewDetail('旧总览', '旧法则'),
        entriesJson: '[]',
        mode: 'adventure',
        origin: 'test.entry',
      );

      await bridge.saveWorldview(
        id: 'wv_edit',
        name: '新名',
        description: '描述',
        detailJson: worldviewDetail('新总览', '新法则'),
        entriesJson: '[]',
        mode: 'adventure',
        origin: 'test.entry',
      );

      final tree = await treeRepository.readTree(const ResourceId('wv_edit'));
      expect(tree!.resource.name, '新名');
      final text = tree.parts.map((part) => part.content).join('\n');
      expect(text, contains('新总览'));
      expect(text, contains('新法则'));
      expect(text.contains('旧法则'), isFalse);

      final after = await counts();
      expect(after['resources'], 1,
          reason: 'an edit must not create a second resource');
      expect(after['sections'], 2);
    });

    test('different entry points produce the same structure for one resource',
        () async {
      await bridge.saveWorldview(
        id: 'wv_same',
        name: '同一世界',
        description: '描述',
        detailJson: worldviewDetail('总览', '法则'),
        entriesJson: '[]',
        mode: 'adventure',
        origin: 'resource-crud.worldview',
      );
      final fromCrud = await treeRepository.readTree(
        const ResourceId('wv_same'),
      );

      await bridge.saveWorldview(
        id: 'wv_same',
        name: '同一世界',
        description: '描述',
        detailJson: worldviewDetail('总览', '法则'),
        entriesJson: '[]',
        mode: 'adventure',
        origin: 'import.worldview',
      );
      final fromImport = await treeRepository.readTree(
        const ResourceId('wv_same'),
      );

      // Same identity and same content regardless of which entry saved it.
      expect(fromImport!.resource.id, fromCrud!.resource.id);
      expect(
        fromImport.sections.map((section) => section.title),
        fromCrud.sections.map((section) => section.title),
      );
      expect(
        fromImport.parts.map((part) => part.content),
        fromCrud.parts.map((part) => part.content),
      );
      expect((await counts())['resources'], 1);
    });

    test('a card save keeps runtime prose as a single Part', () async {
      await bridge.saveCard(
        type: ResourceType.character,
        id: 'card_entry',
        name: '艾莲娜',
        jsonData: jsonEncode(<String, Object?>{
          'name': '艾莲娜',
          'description': '北境的学者',
          'first_mes': '你好',
        }),
        mode: 'adventure',
        origin: 'resource-crud.character',
      );

      final tree = await treeRepository.readTree(
        const ResourceId('card_entry'),
      );
      expect(tree!.resource.type, ResourceType.character);
      final refs =
          tree.resource.metadata['runtime_node_refs'] as Map<String, Object?>;
      final firstMesId = refs['first_mes'] as String;
      expect(
        tree.parts.where((part) => part.id.value == firstMesId),
        hasLength(1),
      );
      // The reference body is not duplicated into metadata.
      expect(jsonEncode(tree.resource.metadata).contains('你好'), isFalse);
    });

    test('legacy tables are never written by an entry save', () async {
      final db = await DatabaseService.database;
      await bridge.saveWorldview(
        id: 'wv_no_legacy',
        name: 'W',
        description: 'D',
        detailJson: worldviewDetail('总览', '法则'),
        entriesJson: '[]',
        mode: 'adventure',
        origin: 'test.entry',
      );
      await bridge.saveCard(
        type: ResourceType.npc,
        id: 'npc_no_legacy',
        name: 'NPC',
        jsonData:
            jsonEncode(<String, Object?>{'name': 'NPC', 'description': 'D'}),
        mode: 'adventure',
        origin: 'test.entry',
      );

      expect(await db.query('worldview_presets'), isEmpty);
      expect(await db.query('character_cards'), isEmpty);
      expect(await db.query('npc_cards'), isEmpty);
    });
  });
}
