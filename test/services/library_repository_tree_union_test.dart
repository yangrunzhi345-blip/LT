import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/legacy_resource_mapper.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Phase 3 makes new resources exist only in the unified tree, so the library
/// must keep seeing them. These tests pin the transitional list/search union and
/// the tree → legacy row projection.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late LibraryRepositoryImpl library;
  late ResourceCreationPipeline pipeline;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_phase3_union_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    library = LibraryRepositoryImpl(getDb: () => DatabaseService.database);
    pipeline = ResourceCreationPipeline(
      getDb: () => DatabaseService.database,
      hasAiCredentials: () => true,
    );
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<void> insertLegacyWorldview({
    required String id,
    required String name,
    required String description,
    String mode = 'adventure',
  }) async {
    final db = await DatabaseService.database;
    await db.insert('worldview_presets', {
      'id': id,
      'name': name,
      'description': description,
      'entries_json': '[]',
      'detail_json': jsonEncode(<String, Object?>{
        'format_version': 2,
        'mode': 'simple',
        'modules': <String, Object?>{
          'overview': {'summary': description, 'status': 'confirmed'},
        },
      }),
      'created_at': '2026-09-15T00:00:00.000',
      'updated_at': '2026-09-15T00:00:00.000',
      'mode': mode,
    });
  }

  group('tree-only resources are visible in the library', () {
    test('a pipeline-created worldview appears as a legacy-shaped row',
        () async {
      final created = await pipeline.create(const ResourceCreationRequest(
        resourceType: ResourceType.worldview,
        method: CreationMethod.manual,
        name: '树中世界',
        idempotencyKey: 'union-1',
        summary: '来自待规划创建的描述',
        origin: 'library',
        initialSections: [
          ResourceTreeSectionDraft(
            title: '规则与边界',
            parts: [ResourceTreePartDraft(title: '规则与边界', content: '魔法需要媒介')],
          ),
          ResourceTreeSectionDraft(
            title: '自定义补充',
            parts: [ResourceTreePartDraft(title: '自定义补充', content: '未被识别的资料')],
          ),
        ],
      ));

      final rows = await library.getWorldviewPresets();
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row['id'], created.resourceId!.value);
      expect(row['name'], '树中世界');
      expect(row['description'], '来自待规划创建的描述');

      final detail = jsonDecode(row['detail_json'] as String) as Map;
      final modules = detail['modules'] as Map;
      expect(modules.keys, contains('world_rules'));
      expect(
        (modules['world_rules'] as Map)['content'],
        '魔法需要媒介',
      );

      // An unrecognised section is preserved as an entry instead of vanishing.
      final entries = jsonDecode(row['entries_json'] as String) as List;
      expect(entries, hasLength(1));
      expect((entries.single as Map)['keys'], ['自定义补充']);
      expect((entries.single as Map)['content'], '未被识别的资料');
    });

    test('characters and NPCs appear in their own listings', () async {
      await pipeline.create(const ResourceCreationRequest(
        resourceType: ResourceType.character,
        method: CreationMethod.manual,
        name: '树中角色',
        idempotencyKey: 'union-char',
        initialSections: [
          ResourceTreeSectionDraft(
            title: '剧情',
            parts: [ResourceTreePartDraft(title: '开场白', content: '你好')],
          ),
        ],
      ));
      await pipeline.create(const ResourceCreationRequest(
        resourceType: ResourceType.npc,
        method: CreationMethod.manual,
        name: '树中 NPC',
        idempotencyKey: 'union-npc',
      ));

      final characters = await library.getCharacterCards();
      expect(characters.map((row) => row['name']), ['树中角色']);
      final data = (jsonDecode(characters.single['json_data'] as String)
          as Map)['data'] as Map;
      expect(data['first_mes'], '你好');

      final npcs = await library.getNpcCards();
      expect(npcs.map((row) => row['name']), ['树中 NPC']);
    });

    test('the library mode filters tree-only resources', () async {
      await pipeline.create(const ResourceCreationRequest(
        resourceType: ResourceType.worldview,
        method: CreationMethod.manual,
        name: '冒险模式资源',
        idempotencyKey: 'union-mode',
        libraryMode: 'adventure',
      ));

      expect(
        await library.getWorldviewPresets(mode: ResourceLibraryMode.adventure),
        hasLength(1),
      );
      expect(
        await library.getWorldviewPresets(mode: ResourceLibraryMode.creation),
        isEmpty,
      );
    });
  });

  group('existing legacy behaviour is unchanged', () {
    test('a legacy row is returned untouched', () async {
      await insertLegacyWorldview(
        id: 'wv_legacy',
        name: '旧世界观',
        description: '旧描述',
      );

      final rows = await library.getWorldviewPresets();
      expect(rows, hasLength(1));
      expect(rows.single['id'], 'wv_legacy');
      expect(rows.single['name'], '旧世界观');
      expect(
        jsonDecode(rows.single['detail_json'] as String),
        jsonDecode(jsonEncode(<String, Object?>{
          'format_version': 2,
          'mode': 'simple',
          'modules': <String, Object?>{
            'overview': {'summary': '旧描述', 'status': 'confirmed'},
          },
        })),
      );
    });

    test('legacy rows and tree-only rows coexist, newest first', () async {
      await insertLegacyWorldview(
        id: 'wv_legacy',
        name: '旧世界观',
        description: '旧描述',
      );
      await pipeline.create(const ResourceCreationRequest(
        resourceType: ResourceType.worldview,
        method: CreationMethod.manual,
        name: '新世界观',
        idempotencyKey: 'union-both',
      ));

      final rows = await library.getWorldviewPresets();
      expect(rows.map((row) => row['name']), containsAll(['旧世界观', '新世界观']));
      // The tree resource was written later, so it sorts first.
      expect(rows.first['name'], '新世界观');
    });

    test('search finds tree-only resources by name', () async {
      await pipeline.create(const ResourceCreationRequest(
        resourceType: ResourceType.worldview,
        method: CreationMethod.manual,
        name: '银月大陆',
        idempotencyKey: 'union-search',
      ));
      await insertLegacyWorldview(
        id: 'wv_other',
        name: '白港群岛',
        description: '贸易海港',
      );

      final hits = await library.searchWorldviewPresets('银月');
      expect(hits.map((row) => row['name']), ['银月大陆']);

      final miss = await library.searchWorldviewPresets('不存在');
      expect(miss, isEmpty);
    });
  });

  group('round-trip through the mapper stays faithful', () {
    test('a mapped legacy worldview can be read back with its modules',
        () async {
      const mapper = LegacyResourceMapper();
      final draft = mapper.mapWorldview(<String, Object?>{
        'id': 'wv_round',
        'name': '往返世界',
        'description': '往返描述',
        'entries_json': '[]',
        'detail_json': jsonEncode(<String, Object?>{
          'modules': <String, Object?>{
            'overview': {'summary': '总览正文', 'status': 'confirmed'},
            'world_rules': {'content': '法则正文', 'status': 'confirmed'},
          },
        }),
      });

      await pipeline.create(ResourceCreationRequest(
        resourceType: ResourceType.worldview,
        method: CreationMethod.manual,
        name: draft.name,
        idempotencyKey: 'union-round',
        summary: draft.summary,
        initialSections: draft.sections,
      ));

      final row = (await library.getWorldviewPresets()).single;
      final modules =
          (jsonDecode(row['detail_json'] as String) as Map)['modules'] as Map;
      expect(modules.keys, containsAll(['overview', 'world_rules']));
      expect((modules['overview'] as Map)['summary'], '总览正文');
      expect((modules['world_rules'] as Map)['content'], '法则正文');
    });
  });
}
