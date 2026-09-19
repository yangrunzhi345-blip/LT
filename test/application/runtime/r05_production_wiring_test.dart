import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/adventure_readiness_gate.dart';
import 'package:lt_dialogue/application/resources/blueprint_prompt_builder.dart';
import 'package:lt_dialogue/application/resources/generation_patch_parser.dart';
import 'package:lt_dialogue/application/resources/part_generation_prompt_builder.dart';
import 'package:lt_dialogue/application/resource_library/import_models.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/models/resource_provenance.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// R05-B regression: production and tests must be wired from the same
/// composition root. These tests read the real provider graph over a real
/// SQLite database and assert actual side effects, not mock invocations.
/// A detailed worldview that satisfies the integrity validator: every module
/// present with enough content, plus a description inside the length window.
String _validDetailJson(String seed) {
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
        key == 'overview' ? 'summary' : 'content': '$key $seed ' * 8,
        'status': 'confirmed',
      },
  };
  return jsonEncode(<String, Object?>{'modules': modules});
}

String _validDescription(String seed) => '\$seed 描述文本。' * 40;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_r05_wiring_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('R05-B production wiring', () {
    test('B3 CRUD controller uses the single production creation pipeline',
        () async {
      final crud = container.read(resourceCrudControllerProvider);
      final productionPipeline =
          container.read(resourceCreationPipelineProvider);

      expect(crud.creationBridge.pipeline, same(productionPipeline));
    });

    test('B4 a CRUD overwrite captures a revision', () async {
      final crud = container.read(resourceCrudControllerProvider);

      final first = await crud.saveWorldviewPreset(
        id: 'wv_r05_b4',
        name: 'R05 世界观',
        description: _validDescription('初版'),
        entriesJson: '[]',
        now: DateTime(2026).toIso8601String(),
        detailJson: _validDetailJson('初版'),
      );
      expect(first.success, isTrue, reason: first.errorMessage);

      final second = await crud.saveWorldviewPreset(
        id: 'wv_r05_b4',
        name: 'R05 世界观',
        description: _validDescription('修改后'),
        entriesJson: '[]',
        now: DateTime(2026).toIso8601String(),
        detailJson: _validDetailJson('修改后'),
      );
      expect(second.success, isTrue, reason: second.errorMessage);
      // Let the library-changed notification chain settle while the
      // provider graph is still alive.
      await pumpEventQueue();

      final db = await DatabaseService.database;
      var revisions = await db.query(
        'resource_revisions',
        where: 'resource_id = ?',
        whereArgs: ['wv_r05_b4'],
      );
      // Acceptance strengthening: the save future resolves only after the
      // capture transaction commits, so the rows are guaranteed; under full
      // -suite load the observation itself may lag the real async DB write,
      // so settle the event queue briefly before asserting.
      for (var i = 0; i < 100 && revisions.isEmpty; i++) {
        await pumpEventQueue();
        revisions = await db.query(
          'resource_revisions',
          where: 'resource_id = ?',
          whereArgs: ['wv_r05_b4'],
        );
      }
      expect(revisions, isNotEmpty,
          reason: 'an overwrite of confirmed content must be recoverable');
    });

    test(
        'B5 worldview import writes the unified tree through the '
        'production bridge', () async {
      final useCase = container.read(worldviewImportUseCaseProvider);

      await useCase.save(
        WorldviewImportDraft(
          name: 'R05 导入世界',
          description: '导入描述',
          detailJson: '{"overview":{"text":"总览"},"rules":{"text":"法则"}}',
          provenance: const ResourceProvenance(
            method: ResourceAuthoringMethod.aiReference,
          ),
        ),
        id: 'wv_r05_b5',
        mode: ResourceLibraryMode.adventure,
      );

      // Real DB side effect: the tree exists with the import provenance.
      final tree = await ResourceTreeRepositoryImpl(
        getDb: () => DatabaseService.database,
      ).readTree(const ResourceId('wv_r05_b5'));
      expect(tree, isNotNull);
      expect(tree!.resource.name, 'R05 导入世界');

      final db = await DatabaseService.database;
      expect((await db.query('resources')).length, 1);
      // The legacy table is not dual-written by the import path.
      expect((await db.query('worldview_presets')), isEmpty);
    });

    test('B6 adventure start fails closed for an unprepared resource',
        () async {
      final crud = container.read(resourceCrudControllerProvider);
      final saved = await crud.saveWorldviewPreset(
        id: 'wv_r05_b6',
        name: '未准备的世界',
        description: _validDescription('未准备'),
        entriesJson: '[]',
        now: DateTime(2026).toIso8601String(),
        detailJson: _validDetailJson('未准备'),
      );
      expect(saved.success, isTrue, reason: saved.errorMessage);
      await pumpEventQueue();

      final gate = container.read(adventureReadinessGateProvider);
      final config = AdventureConfig(
        name: '测试冒险',
        worldviewSnapshot: {'source_id': 'wv_r05_b6'},
      );

      await expectLater(
        gate.enforceAndFreeze(config),
        throwsA(isA<AdventureReadinessGateException>()),
      );
    });

    test('B7 adventure start succeeds once the assembly is ready', () async {
      final crud = container.read(resourceCrudControllerProvider);
      final saved = await crud.saveWorldviewPreset(
        id: 'wv_r05_b7',
        name: '已准备的世界',
        description: _validDescription('已准备'),
        entriesJson: '[]',
        now: DateTime(2026).toIso8601String(),
        detailJson: _validDetailJson('已准备'),
      );
      expect(saved.success, isTrue, reason: saved.errorMessage);
      await pumpEventQueue();

      final coordinator = container.read(assemblyReadinessCoordinatorProvider);
      final outcome = await coordinator.prepare(const ResourceId('wv_r05_b7'));
      expect(outcome.record.state, ReadinessState.ready,
          reason: outcome.record.failureReason);

      final gate = container.read(adventureReadinessGateProvider);
      final config = AdventureConfig(
        name: '测试冒险',
        worldviewSnapshot: {'source_id': 'wv_r05_b7'},
      );
      final frozen = await gate.enforceAndFreeze(config);
      expect(
        frozen.worldviewSnapshot?['source_id'],
        'wv_r05_b7',
      );
      expect(frozen.resourceBindings, isNotEmpty);
    });

    test('B8 prompt-declared protocol keys all have parser consumers',
        () async {
      // Every quoted key the part-generation prompt promises must be
      // accepted by the strict parser allowlist.
      final systemPrompt = PartGenerationPromptBuilder.buildSystemPrompt(
        _partRequest(),
      );
      final declaredKeys = RegExp('"([a-z_]+)"\\s*:')
          .allMatches(systemPrompt)
          .map((m) => m.group(1)!)
          .toSet();
      expect(declaredKeys, isNotEmpty);
      for (final key in declaredKeys) {
        expect(
          GenerationPatchParser.allowedPatchKeys,
          contains(key),
          reason: 'prompt declares "$key" but the parser would reject it',
        );
      }

      // Round-trip: a patch carrying every declared key parses cleanly.
      final line = jsonEncode({
        'protocol_version': 1,
        'generation_id': 'gen_b8',
        'resource_id': 'res_b8',
        'section_id': 'sec_b8',
        'part_id': 'part_b8',
        'attempt_id': 'attempt_b8',
        'sequence': 0,
        'op': 'start_part',
        'cursor': 0,
        'text_delta': '',
        'summary': '',
      });
      final patch = GenerationPatchParser.parsePatchLine(line);
      expect(patch.partId.value, 'part_b8');

      // Blueprint prompt: every declared output key is consumed by the
      // blueprint parser.
      final blueprintPrompt = BlueprintPromptBuilder.buildSystemPrompt(
        resourceType: ResourceType.worldview,
        idPool: const BlueprintIdPool(
          allowedSectionIds: ['sec_1'],
          allowedPartIds: ['part_1'],
        ),
      );
      final blueprintKeys = RegExp('"([a-zA-Z]+)"\\s*:')
          .allMatches(blueprintPrompt)
          .map((m) => m.group(1)!)
          .toSet();
      const consumedByParser = {
        'suggestedName',
        'summary',
        'sections',
        'id',
        'title',
        'sortOrder',
        'parts',
        'sectionId',
        'generationGoal',
        'estimatedLength',
        'dependencies',
      };
      for (final key in blueprintKeys) {
        expect(
          consumedByParser,
          contains(key),
          reason: 'blueprint prompt declares "$key" with no parser consumer',
        );
      }
      expect(blueprintKeys, containsAll(consumedByParser));
    });

    test('B9 production fallback attaches the real compression link', () async {
      final coordinator = container.read(assemblyReadinessCoordinatorProvider);
      // The link provider runs at startup; reading it wires the coordinator.
      container.read(assemblyReadinessCompressionLinkProvider);
      expect(coordinator.compressionAttached, isTrue,
          reason: 'an OVERFLOW head in production must reach a compression '
              'worker, not dead-end silently');
    });
  });
}

PartGenerationRequest _partRequest() {
  return const PartGenerationRequest(
    generationId: 'gen_b8',
    resourceId: ResourceId('res_b8'),
    sectionId: SectionId('sec_b8'),
    partId: PartId('part_b8'),
    attemptId: 'attempt_b8',
    promptGoal: '目标',
    targetBudget: 100,
    context: PartGenerationContext(
      resourceName: '资源',
      resourceType: ResourceType.worldview,
      resourceSummary: '',
      sectionTitle: '章节',
      sectionSummary: '',
      partTitle: '部件',
    ),
  );
}
