import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/generation_patch_parser.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/application/resources/part_generation_parser.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_patch.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Contract tests authored by the independent Phase 5 reviewer.
///
/// These intentionally assert the published Phase 5 protocol rather than the
/// executor implementation. A failure is acceptance evidence, not a request
/// to weaken the contract.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  group('Phase 5 independent acceptance — strict JSON boundary', () {
    const base = '''
{
  "protocol_version": 1,
  "generation_id": "gen_1",
  "resource_id": "res_1",
  "section_id": "sec_1",
  "part_id": "part_1",
  "attempt_id": "att_1",
  "content": "body"
}
''';

    test('rejects non-canonical protocol-version types', () {
      expect(
        () => PartGenerationParser.parse(base.replaceFirst('1,', '"1",')),
        throwsA(isA<PartGenerationParseException>()),
      );
    });

    test('rejects duplicate snake_case and camelCase semantic fields', () {
      expect(
        () => PartGenerationParser.parse(base.replaceFirst(
          '"part_id": "part_1",',
          '"part_id": "part_1", "partId": "other_part",',
        )),
        throwsA(isA<PartGenerationParseException>()),
      );
    });

    test('rejects ambiguous prose containing two JSON objects', () {
      expect(
        () => PartGenerationParser.parse('$base\n$base'),
        throwsA(isA<PartGenerationParseException>()),
      );
    });
  });

  group('Phase 5 independent acceptance — patch cursor integrity', () {
    test('rejects complete_part whose cursor differs from accumulated text',
        () {
      final accumulator = GenerationPatchAccumulator(
        expectedGenerationId: 'gen_1',
        expectedResourceId: const ResourceId('res_1'),
        expectedSectionId: const SectionId('sec_1'),
        expectedPartId: const PartId('part_1'),
        expectedAttemptId: 'att_1',
      );
      accumulator.applyPatch(const ResourceGenerationPatch(
        protocolVersion: 1,
        generationId: 'gen_1',
        resourceId: ResourceId('res_1'),
        sectionId: SectionId('sec_1'),
        partId: PartId('part_1'),
        attemptId: 'att_1',
        sequence: 0,
        op: ResourcePatchOp.startPart,
      ));
      accumulator.applyPatch(const ResourceGenerationPatch(
        protocolVersion: 1,
        generationId: 'gen_1',
        resourceId: ResourceId('res_1'),
        sectionId: SectionId('sec_1'),
        partId: PartId('part_1'),
        attemptId: 'att_1',
        sequence: 1,
        op: ResourcePatchOp.appendText,
        textDelta: 'text',
        cursor: 0,
      ));

      expect(
        () => accumulator.applyPatch(const ResourceGenerationPatch(
          protocolVersion: 1,
          generationId: 'gen_1',
          resourceId: ResourceId('res_1'),
          sectionId: SectionId('sec_1'),
          partId: PartId('part_1'),
          attemptId: 'att_1',
          sequence: 2,
          op: ResourcePatchOp.completePart,
          cursor: 0,
        )),
        throwsA(isA<PatchCursorMismatchException>()),
      );
    });
  });

  group('Phase 5 independent acceptance — one request, one part', () {
    late Directory tempDir;
    late ResourceCreationPipeline pipeline;
    late ResourceBlueprintRepositoryImpl blueprintRepository;
    late PartGenerationTaskRepositoryImpl taskRepository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lt_phase5_review_');
      DatabaseService.customDbDir = tempDir.path;
      await DatabaseService.resetDatabase();
      final treeRepository = ResourceTreeRepositoryImpl(
        getDb: () => DatabaseService.database,
      );
      pipeline = ResourceCreationPipeline(
        getDb: () => DatabaseService.database,
        hasAiCredentials: () => true,
        treeRepository: treeRepository,
      );
      blueprintRepository = ResourceBlueprintRepositoryImpl(
        getDb: () => DatabaseService.database,
        treeRepository: treeRepository,
      );
      taskRepository = PartGenerationTaskRepositoryImpl(
        getDb: () => DatabaseService.database,
      );
    });

    tearDown(() async {
      await DatabaseService.resetDatabase();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('rejects a multiple-Part payload before any content is committed',
        () async {
      final session = await pipeline.create(ResourceCreationRequest(
        resourceType: ResourceType.worldview,
        method: CreationMethod.aiReference,
        name: 'Review fixture',
        idempotencyKey:
            'phase5-review-${DateTime.now().microsecondsSinceEpoch}',
      ));
      final blueprint = ResourceBlueprint(
        blueprintId: 'bp_review',
        sessionId: session.sessionId!,
        resourceType: ResourceType.worldview,
        suggestedName: 'Review fixture',
        summary: 'fixture',
        sections: [
          BlueprintSection(
            id: 'sec_1',
            title: 'Section',
            parts: [
              const BlueprintPart(
                id: 'part_1',
                sectionId: 'sec_1',
                title: 'Part',
                generationGoal: 'Generate only this part',
                estimatedLength: 100,
              ),
            ],
          ),
        ],
      );
      await blueprintRepository.saveBlueprint(blueprint);
      final confirmed = await blueprintRepository.confirmBlueprint(
        blueprintId: blueprint.blueprintId,
      );

      final coordinator = PartGenerationCoordinator(
        taskRepository: taskRepository,
        blueprintRepository: blueprintRepository,
        pipeline: pipeline,
        completer: ({
          required String systemPrompt,
          required String instruction,
          required LlmTask task,
          GenerationTaskHandle? taskHandle,
        }) async {
          String field(String name) =>
              RegExp('"$name": "(.*?)"').firstMatch(systemPrompt)?.group(1) ??
              '';
          return '''
{
  "protocol_version": 1,
  "generation_id": "${field('generation_id')}",
  "resource_id": "${field('resource_id')}",
  "section_id": "${field('section_id')}",
  "part_id": "${field('part_id')}",
  "attempt_id": "${field('attempt_id')}",
  "content": "authorized body",
  "parts": [{"part_id": "unauthorized", "content": "other body"}]
}
''';
        },
      );

      final completed = await coordinator.generateAllParts(
        blueprintId: blueprint.blueprintId,
        maxRetriesPerPart: 0,
      );

      expect(completed, isFalse);
      final content = await taskRepository.getPartsContent([
        '${confirmed.resourceId.value}_part_1',
      ]);
      expect(content.values.single.content, isEmpty);
    });
  });
}
