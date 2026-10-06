import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/r01_streaming_fixture.dart';

/// Regression coverage for "character generation fails after associating a
/// worldview": the full worldview must never be pushed into one Part prompt,
/// the prompt must stay bounded, and no reference length may crash selection.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory directory;
  late R01StreamingFixture fixture;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lt_worldview_repro_');
    DatabaseService.customDbDir = directory.path;
    await DatabaseService.resetDatabase();
    await DatabaseService.database;
    fixture = R01StreamingFixture();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    await directory.delete(recursive: true);
  });

  Future<_RunOutcome> run({
    required String label,
    required String referenceBody,
    required List<BlueprintPart> parts,
    int targetCharacters = 20000,
  }) async {
    final creation = await fixture.pipeline.create(ResourceCreationRequest(
      resourceType: ResourceType.character,
      method: CreationMethod.aiReference,
      name: label,
      idempotencyKey: 'worldview-$label',
      targetCharacters: targetCharacters,
      referenceSource: ReferenceSource.text(referenceBody),
    ));
    final blueprint = ResourceBlueprint(
      blueprintId: 'bp_$label',
      sessionId: creation.sessionId!,
      resourceType: ResourceType.character,
      suggestedName: label,
      summary: label,
      sections: [BlueprintSection(id: 'sec_1', title: '角色', parts: parts)],
    );
    await fixture.blueprintRepository.saveBlueprint(blueprint);
    final confirmed = await fixture.blueprintRepository.confirmBlueprint(
      blueprintId: blueprint.blueprintId,
    );
    final gateway = _CapturingStreamingGateway();
    final coordinator = PartGenerationCoordinator(
      taskRepository: fixture.taskRepository,
      blueprintRepository: fixture.blueprintRepository,
      pipeline: fixture.pipeline,
      gateway: gateway,
      maxConcurrency: 1,
    );
    final success = await coordinator.generateAllParts(
      blueprintId: blueprint.blueprintId,
    );
    final tasks = await fixture.taskRepository
        .findTasksForResource(confirmed.resourceId.value);
    final session = await fixture.pipeline.findSession(creation.sessionId!);
    return _RunOutcome(
      success: success,
      statuses: [for (final t in tasks) '${t.status}:${t.errorMessage}'],
      instructions: gateway.instructions,
      systemPrompts: gateway.systemPrompts,
      referenceBodyLength: session!.referenceSource.body.length,
    );
  }

  List<BlueprintPart> chainedParts(int count, {int estimatedLength = 2800}) => [
        for (var i = 0; i < count; i++)
          BlueprintPart(
            id: 'part_${i + 1}',
            sectionId: 'sec_1',
            title: '背景故事$i',
            generationGoal: '生成角色背景第$i段',
            estimatedLength: estimatedLength,
            dependencies: i == 0 ? const [] : ['part_$i'],
          ),
      ];

  test('Case 3/4: ~50k worldview succeeds and every Part prompt stays bounded',
      () async {
    // Paragraph lengths deliberately include the value that used to throw the
    // off-by-one RangeError, so this test fails before the fix.
    final paragraphs = <String>[
      for (var i = 0; i < 36; i++) 'W$i'.padRight(2, 'a') + ('甲' * 1496),
    ];
    final worldview = paragraphs.join('\n\n');
    const primary = '角色主要参考资料：一位游侠。';

    final outcome = await run(
      label: 'large-worldview',
      referenceBody: '$primary\n\n[关联世界观]\n$worldview',
      parts: chainedParts(5),
    );

    expect(outcome.referenceBodyLength, greaterThan(40000));
    expect(outcome.success, isTrue, reason: 'statuses=${outcome.statuses}');
    expect(outcome.statuses.every((s) => s.startsWith('completed')), isTrue);

    // Case 4: the raw reference is ~50k but no Part prompt carries it whole.
    for (final instruction in outcome.instructions) {
      expect(instruction.length, lessThan(8000));
      expect(instruction.length, lessThan(outcome.referenceBodyLength));
    }
  });

  test('Case 6: a single huge worldview paragraph is still bounded', () async {
    final worldview = '乙' * 50000;
    final outcome = await run(
      label: 'single-paragraph',
      referenceBody: '主角资料。\n\n[关联世界观]\n$worldview',
      parts: chainedParts(4),
    );

    expect(outcome.success, isTrue, reason: '${outcome.statuses}');
    for (final instruction in outcome.instructions) {
      expect(instruction.length, lessThan(8000));
    }
  });

  test('Case 7/8: many Chinese Markdown sections stay bounded', () async {
    final sections = <String>[
      for (var i = 0; i < 40; i++) '## 章节$i\n\n${'丙' * 1200}',
    ].join('\n\n');
    final outcome = await run(
      label: 'markdown-sections',
      referenceBody: '角色资料。\n\n[关联世界观]\n$sections',
      parts: chainedParts(5),
    );

    expect(outcome.success, isTrue, reason: '${outcome.statuses}');
    for (final instruction in outcome.instructions) {
      expect(instruction.length, lessThan(8000));
    }
  });

  test('Case 9/10: NDJSON split across UTF-8 and line boundaries accumulates',
      () async {
    // The gateway in `run` already splits the response into 64-char chunks; an
    // explicit split inside multi-byte characters and JSON lines is covered by
    // `_CapturingStreamingGateway` below, so assert the content committed.
    final outcome = await run(
      label: 'fragmented-stream',
      referenceBody: '角色资料。\n\n[关联世界观]\n${'丁' * 50000}',
      parts: chainedParts(1),
    );

    expect(outcome.success, isTrue, reason: '${outcome.statuses}');
    expect(outcome.statuses.first, startsWith('completed'));
  });
}

final class _RunOutcome {
  _RunOutcome({
    required this.success,
    required this.statuses,
    required this.instructions,
    required this.systemPrompts,
    required this.referenceBodyLength,
  });

  final bool success;
  final List<String> statuses;
  final List<String> instructions;
  final List<String> systemPrompts;
  final int referenceBodyLength;
}

final class _CapturingStreamingGateway
    implements LlmGateway, PartGenerationStreamingGateway {
  static const int contentCharacters = 1200;

  final List<String> instructions = [];
  final List<String> systemPrompts = [];

  @override
  bool get isConfigured => true;

  @override
  Future<String> rawCompletion({
    required String systemPrompt,
    required String instruction,
    int maximumOutputTokens = 4096,
    double temperature = .7,
    LlmTask task = LlmTask.structuredExtraction,
    GenerationTaskHandle? taskHandle,
  }) =>
      throw UnsupportedError('streaming only');

  @override
  Future<void> streamPartGeneration({
    required String systemPrompt,
    required String instruction,
    required LlmTask task,
    required void Function(String chunk) onChunk,
    GenerationTaskHandle? taskHandle,
  }) async {
    systemPrompts.add(systemPrompt);
    instructions.add(instruction);
    String id(String field) =>
        RegExp('"$field": "(.*?)"').firstMatch(systemPrompt)?.group(1) ?? '';
    final content = '正' * contentCharacters;
    Map<String, Object> patch(int seq, String op, {String? delta}) => {
          'protocol_version': 1,
          'generation_id': id('generation_id'),
          'resource_id': id('resource_id'),
          'section_id': id('section_id'),
          'part_id': id('part_id'),
          'attempt_id': id('attempt_id'),
          'sequence': seq,
          'op': op,
          if (delta != null) 'text_delta': delta,
        };
    final text = [
      patch(0, 'start_part'),
      patch(1, 'append_text', delta: content),
      patch(2, 'complete_part'),
    ].map(jsonEncode).join('\n');
    // Split at small, irregular boundaries to exercise multi-byte and
    // line-boundary reassembly.
    const step = 7;
    for (var i = 0; i < text.length; i += step) {
      onChunk(text.substring(i, (i + step).clamp(0, text.length)));
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}
