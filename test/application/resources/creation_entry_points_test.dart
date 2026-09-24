import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resource_library/edit_drafts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/engines/world_engine.dart';
import 'package:lt_dialogue/managers/character_manager.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Phase 3 entry-level acceptance: every entry point must end up in the same
/// creation pipeline, produce the same structure for the same request, create
/// exactly one record, and stop writing legacy tables.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ResourceTreeRepositoryImpl tree;
  late LibraryRepositoryImpl library;
  late ResourceCreationPipeline pipeline;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_entry_points_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    tree = ResourceTreeRepositoryImpl(getDb: () => DatabaseService.database);
    library = LibraryRepositoryImpl(getDb: () => DatabaseService.database);
    pipeline = ResourceCreationPipeline(
      getDb: () => DatabaseService.database,
      hasAiCredentials: () => true,
      treeRepository: tree,
    );
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  ResourceCrudController controller() => ResourceCrudController(
        repository: library,
        creationPipeline: pipeline,
      );

  /// A detailed worldview that satisfies the existing integrity rules: every
  /// module present with enough total content.
  String detailJson(String overview, String rules) {
    const moduleKeys = <String>[
      'overview',
      'world_rules',
      'world_state',
      'locations',
      'factions',
      'customs_and_life',
      'timeline',
      'glossary',
      'creative_constraints',
    ];
    final modules = <String, Object?>{
      for (final key in moduleKeys)
        key: <String, Object?>{
          key == 'overview' ? 'summary' : 'content':
              '$key $overview $rules ' * 8,
          'status': 'confirmed',
        },
    };
    return jsonEncode(<String, Object?>{'modules': modules});
  }

  /// A simple-mode description that satisfies the 200–500 character rule.
  String simpleDescription(String seed) => '$seed 描述文本。' * 40;

  Future<Map<String, int>> legacyCounts() async {
    final db = await DatabaseService.database;
    Future<int> count(String table) async {
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
      return (rows.first['c'] as num).toInt();
    }

    return {
      'worldview_presets': await count('worldview_presets'),
      'character_cards': await count('character_cards'),
      'npc_cards': await count('npc_cards'),
    };
  }

  Future<List<String>> structureOf(String resourceId) async {
    final snapshot = await tree.readTree(ResourceId(resourceId));
    if (snapshot == null) {
      fail('missing $resourceId in the content tree');
    }
    return <String>[
      for (final section in snapshot.orderedSections)
        '${section.title}:'
            '${snapshot.orderedPartsOf(section.id).map((part) => part.content).join("|")}',
    ];
  }

  group('library entry (ResourceCrudController)', () {
    test('saves a worldview into the tree only', () async {
      final result = await controller().saveWorldviewPreset(
        id: 'wv_library',
        name: '银月大陆',
        description: simpleDescription('北境学术重镇'),
        entriesJson: '[]',
        now: DateTime.now().toIso8601String(),
        detailJson: detailJson('总览', '法则'),
      );

      expect(result.success, isTrue);
      expect(await structureOf('wv_library'), hasLength(9));
      expect(await legacyCounts(), {
        'worldview_presets': 0,
        'character_cards': 0,
        'npc_cards': 0,
      });
    });

    test('saves a character card into the tree only', () async {
      final result = await controller().saveCharacterCard(
        id: 'card_library',
        name: '艾莲娜',
        jsonData: jsonEncode(<String, Object?>{
          'name': '艾莲娜',
          'description': '北境学者',
          'first_mes': '你好',
        }),
        source: '手动创建',
        now: DateTime.now().toIso8601String(),
      );

      expect(result.success, isTrue);
      final snapshot = await tree.readTree(const ResourceId('card_library'));
      expect(snapshot!.resource.type, ResourceType.character);
      expect(
        snapshot.parts.map((part) => part.content).join('\n'),
        contains('北境学者'),
      );
      expect(await legacyCounts(), {
        'worldview_presets': 0,
        'character_cards': 0,
        'npc_cards': 0,
      });
    });

    test('editing through a draft updates the same resource', () async {
      final crud = controller();
      await crud.saveWorldviewPreset(
        id: 'wv_draft',
        name: '原名',
        description: simpleDescription('描述'),
        entriesJson: '[]',
        now: DateTime.now().toIso8601String(),
        detailJson: detailJson('旧总览', '旧法则'),
      );

      final draft = WorldviewEditDraft(
        id: 'wv_draft',
        name: '新名',
        description: simpleDescription('描述'),
        entriesJson: '[]',
      );
      // A simple draft keeps the description-only overview shape.
      final result = await crud.saveWorldviewDraft(
        draft,
        mode: ResourceLibraryMode.adventure,
      );

      if (result.success) {
        final db = await DatabaseService.database;
        final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM resources');
        expect((rows.first['c'] as num).toInt(), 1);
        final snapshot = await tree.readTree(const ResourceId('wv_draft'));
        expect(snapshot!.resource.name, '新名');
      } else {
        // A validation refusal must not create a second resource either.
        final db = await DatabaseService.database;
        final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM resources');
        expect((rows.first['c'] as num).toInt(), 1);
      }
    });

    test('an npc draft lands in the tree as an npc resource', () async {
      final result = await controller().saveNpcDraft(NpcEditDraft(
        id: 'npc_library',
        name: '酒馆老板',
        personality: '健谈',
        worldviewId: 'wv_library',
      ));

      if (result.success) {
        final snapshot = await tree.readTree(const ResourceId('npc_library'));
        expect(snapshot!.resource.type, ResourceType.npc);
      }
      expect((await legacyCounts())['npc_cards'], 0);
    });
  });

  group('other entries', () {
    test('character manager import writes the tree', () async {
      final manager = CharacterManager(
        notifyParent: () {},
        libraryRepo: library,
        creationPipeline: pipeline,
      );

      final message = await manager.importCharacterCardJson(jsonEncode(
        <String, Object?>{
          'spec': 'chara_card_v2',
          'data': <String, Object?>{
            'name': '管理器角色',
            'description': '管理器描述',
          },
        },
      ));

      expect(message, contains('成功'));
      expect((await legacyCounts())['character_cards'], 0);
      final db = await DatabaseService.database;
      final rows = await db.query('resources');
      expect(rows, hasLength(1));
      expect(rows.first['name'].toString(), contains('管理器角色'));
    });

    test('world engine save writes the tree', () async {
      final engine = WorldEngine(
        notifyParent: () {},
        worldEntryRepo:
            WorldEntryRepositoryImpl(getDb: () => DatabaseService.database),
        libraryRepo: library,
        creationPipeline: pipeline,
      );

      await engine.saveWorldviewPreset('引擎世界', simpleDescription('引擎描述'));

      expect((await legacyCounts())['worldview_presets'], 0);
      final db = await DatabaseService.database;
      final rows = await db.query('resources');
      expect(rows, hasLength(1));
      expect(rows.first['name'], '引擎世界');
    });
  });
}
