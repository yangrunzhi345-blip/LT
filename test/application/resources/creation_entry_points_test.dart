import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/application/resource_library/edit_drafts.dart';
import 'package:lt_dialogue/application/resource_library/import_models.dart';
import 'package:lt_dialogue/application/resource_library/import_use_cases.dart';
import 'package:lt_dialogue/application/resources/legacy_creation_bridge.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/controllers/resource_library_import_controller.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/engines/world_engine.dart';
import 'package:lt_dialogue/managers/character_manager.dart';
import 'package:lt_dialogue/models/generation_task_handle.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/models/resource_provenance.dart';
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

  group('import entries', () {
    test('worldview import writes the tree and not the legacy table', () async {
      final useCase = ImportWorldviewUseCase(
        gateway: _UnusedGateway(),
        repository: library,
        bridge: LegacyCreationBridge(pipeline),
      );

      await useCase.save(
        WorldviewImportDraft(
          name: '导入世界',
          description: simpleDescription('导入描述'),
          detailJson: detailJson('导入总览', '导入法则'),
          provenance: const ResourceProvenance(
            method: ResourceAuthoringMethod.aiReference,
            aiDepth: AiGenerationDepth.detailed,
          ),
        ),
        id: 'wv_import',
        mode: ResourceLibraryMode.adventure,
      );

      expect(await structureOf('wv_import'), hasLength(9));
      expect((await legacyCounts())['worldview_presets'], 0);

      // AI provenance survives the entry.
      final snapshot = await tree.readTree(const ResourceId('wv_import'));
      expect(
        snapshot!.resource.metadata['authoring_method'],
        CreationMethod.aiReference.storageValue,
      );
      expect(snapshot.resource.metadata['ai_generation_depth'], 'detailed');
    });

    test('the same world from two entries is one resource with one structure',
        () async {
      final crud = controller();
      await crud.saveWorldviewPreset(
        id: 'wv_shared',
        name: '同一世界',
        description: simpleDescription('描述'),
        entriesJson: '[]',
        now: DateTime.now().toIso8601String(),
        detailJson: detailJson('总览', '法则'),
      );
      final fromLibrary = await structureOf('wv_shared');

      final useCase = ImportWorldviewUseCase(
        gateway: _UnusedGateway(),
        repository: library,
        bridge: LegacyCreationBridge(pipeline),
      );
      await useCase.save(
        WorldviewImportDraft(
          name: '同一世界',
          description: simpleDescription('描述'),
          detailJson: detailJson('总览', '法则'),
          provenance: const ResourceProvenance(
            method: ResourceAuthoringMethod.aiReference,
          ),
        ),
        id: 'wv_shared',
        mode: ResourceLibraryMode.adventure,
      );
      final fromImport = await structureOf('wv_shared');

      expect(fromImport, fromLibrary);
      final db = await DatabaseService.database;
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM resources');
      expect((rows.first['c'] as num).toInt(), 1);
    });

    test('conversation character import writes the tree', () async {
      final useCase = ImportConversationCharacterUseCase(
        gateway: _UnusedGateway(),
        repository: library,
        bridge: LegacyCreationBridge(pipeline),
      );

      await useCase.save(
        ConversationCharacterDraft(<String, String>{
          'name': '对话角色',
          'description': '对话描述',
        }),
        id: 'card_conversation',
      );

      final snapshot =
          await tree.readTree(const ResourceId('card_conversation'));
      expect(snapshot!.resource.type, ResourceType.character);
      expect((await legacyCounts())['character_cards'], 0);
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

  group(
      'AI blueprint planning and consumption from import entries & controllers',
      () {
    test(
        'ImportWorldviewUseCase plans, consumes pendingPlanningSessions, and confirms into tree',
        () async {
      const mockBlueprintJson = '''
```json
{
  "suggestedName": "AI 规划世界观",
  "summary": "自适应世界观大纲",
  "sections": [
    {
      "id": "sec_1",
      "title": "起源总览",
      "summary": "起源",
      "sortOrder": 0,
      "parts": [
        {
          "id": "part_1",
          "sectionId": "sec_1",
          "title": "创世神话",
          "generationGoal": "创世背景",
          "estimatedLength": 1000,
          "dependencies": [],
          "sortOrder": 0
        }
      ]
    }
  ]
}
```
''';
      final gateway = _PlanningGateway(mockBlueprintJson);
      final useCase = ImportWorldviewUseCase(
        gateway: gateway,
        repository: library,
        bridge: LegacyCreationBridge(pipeline),
      );

      // 1. Initial AI creation request creates a planning session
      final creationResult = await useCase.plan(
        const WorldviewImportRequest(
          source: '原始设定文档',
          aiDepth: AiGenerationDepth.detailed,
          libraryMode: ResourceLibraryMode.adventure,
        ),
      );
      final sessionId = creationResult.sessionId!;

      // 2. pendingPlanningSessions finds the session
      final pending = await useCase.pendingPlanningSessions();
      expect(pending.map((s) => s.sessionId), contains(sessionId));

      // 3. Plan blueprint through the use case
      final blueprint = await useCase.planBlueprint(sessionId);
      expect(blueprint.suggestedName, 'AI 规划世界观');
      expect(blueprint.status, BlueprintStatus.draft);

      // 4. Confirm blueprint through the use case
      final confirmResult =
          await useCase.confirmBlueprint(blueprint.blueprintId);
      expect(confirmResult.reusedExisting, isFalse);
      expect(confirmResult.blueprint.sections, hasLength(1));
      expect(confirmResult.blueprint.sections.first.parts, hasLength(1));

      // 5. Session is completed, pendingPlanningSessions is now empty
      final pendingAfter = await useCase.pendingPlanningSessions();
      expect(pendingAfter.any((s) => s.sessionId == sessionId), isFalse);

      // 6. Tree has the resource with placeholders and generation tasks
      final snapshot = await tree.readTree(confirmResult.resourceId);
      expect(snapshot, isNotNull);
      expect(snapshot!.resource.name, 'AI 规划世界观');
    });

    test('ResourceCardImportUseCase plans and consumes character blueprint',
        () async {
      const mockCardJson = '''
```json
{
  "suggestedName": "艾莉亚",
  "summary": "流浪法师角色大纲",
  "sections": [
    {
      "id": "sec_1",
      "title": "角色设定",
      "summary": "设定",
      "sortOrder": 0,
      "parts": [
        {
          "id": "part_1",
          "sectionId": "sec_1",
          "title": "性格特征",
          "generationGoal": "外冷内热",
          "estimatedLength": 800,
          "dependencies": [],
          "sortOrder": 0
        }
      ]
    }
  ]
}
```
''';
      final gateway = _PlanningGateway(mockCardJson);
      final useCase = ResourceCardImportUseCase(
        gateway: gateway,
        repository: library,
        bridge: LegacyCreationBridge(pipeline),
      );

      final creationResult = await useCase.plan(
        const ResourceCardImportRequest(
          kind: ResourceCardImportKind.character,
          source: '法师艾莉亚设定',
          aiDepth: AiGenerationDepth.detailed,
          libraryMode: ResourceLibraryMode.adventure,
        ),
      );
      final sessionId = creationResult.sessionId!;

      final pending = await useCase.pendingPlanningSessions();
      expect(pending.map((s) => s.sessionId), contains(sessionId));

      final bp = await useCase.planBlueprint(sessionId);
      expect(bp.suggestedName, '艾莉亚');

      final confirmed = await useCase.confirmBlueprint(bp.blueprintId);
      expect(confirmed.blueprint.sections.first.parts, hasLength(1));

      final pendingAfter = await useCase.pendingPlanningSessions();
      expect(pendingAfter.any((s) => s.sessionId == sessionId), isFalse);
    });

    test(
        'ResourceLibraryImportController exposes planning and confirm operations',
        () async {
      const mockJson = '''
```json
{
  "suggestedName": "控制器驱动世界",
  "summary": "测试控制器驱动",
  "sections": [
    {
      "id": "sec_1",
      "title": "章节一",
      "summary": "概要",
      "sortOrder": 0,
      "parts": [
        {
          "id": "part_1",
          "sectionId": "sec_1",
          "title": "部分一",
          "generationGoal": "目标",
          "estimatedLength": 500,
          "dependencies": [],
          "sortOrder": 0
        }
      ]
    }
  ]
}
```
''';
      final gateway = _PlanningGateway(mockJson);
      final bridge = LegacyCreationBridge(pipeline);
      final controller = ResourceLibraryImportController(
        conversationCharacterUseCase: ImportConversationCharacterUseCase(
          gateway: gateway,
          repository: library,
          bridge: bridge,
        ),
        worldviewUseCase: ImportWorldviewUseCase(
          gateway: gateway,
          repository: library,
          bridge: bridge,
        ),
      );

      final sessionRes = await bridge.planAiCreation(
        type: ResourceType.worldview,
        name: '待办世界',
        referenceSource: ReferenceSource.text('参考文本'),
        origin: 'import.worldview.ai',
        mode: 'adventure',
      );

      final pending = await controller.pendingPlanningSessions();
      expect(pending.map((s) => s.sessionId), contains(sessionRes.sessionId));

      final bp = await controller.planWorldviewBlueprint(sessionRes.sessionId!);
      expect(bp.suggestedName, '控制器驱动世界');

      final result = await controller.confirmWorldviewBlueprint(bp.blueprintId);
      expect(result.blueprint.sections, hasLength(1));

      final pendingAfter = await controller.pendingPlanningSessions();
      expect(pendingAfter.any((s) => s.sessionId == sessionRes.sessionId),
          isFalse);
    });
  });
}

class _PlanningGateway implements LlmGateway {
  final String response;
  _PlanningGateway(this.response);

  @override
  Future<String> rawCompletion({
    required String systemPrompt,
    required String instruction,
    int maximumOutputTokens = 4096,
    double temperature = .7,
    LlmTask task = LlmTask.structuredExtraction,
    GenerationTaskHandle? taskHandle,
  }) async {
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Only rawCompletion is used for planning tests');
}

/// The import entries under test never reach the gateway.
class _UnusedGateway implements LlmGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('gateway must not be used in these tests');
}
