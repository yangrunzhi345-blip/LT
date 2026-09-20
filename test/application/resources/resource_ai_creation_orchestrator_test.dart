import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/controllers/streaming_resource_generation_controller.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';
import 'package:lt_dialogue/features/resource_studio/application/use_cases/resource_ai_creation_orchestrator.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/r01_streaming_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory directory;
  late R01StreamingFixture fixture;
  late Completer<void> allowGeneration;
  late Completer<void> generationStarted;
  late StreamingResourceGenerationController controller;
  late ResourceAiCreationOrchestrator orchestrator;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lt_ai_orchestrator_');
    DatabaseService.customDbDir = directory.path;
    await DatabaseService.resetDatabase();
    await DatabaseService.database;
    fixture = R01StreamingFixture();
    allowGeneration = Completer<void>();
    generationStarted = Completer<void>();
    final service = fixture.buildService(({
      required String systemPrompt,
      required String instruction,
      required LlmTask task,
      GenerationTaskHandle? taskHandle,
    }) async {
      if (!generationStarted.isCompleted) generationStarted.complete();
      await allowGeneration.future;
      return r01Completion(systemPrompt, '统一 Authority 生成的正文。');
    });
    controller = StreamingResourceGenerationController(
      service: service,
      sessionRepository: fixture.sessionRepository,
    );
    orchestrator = ResourceAiCreationOrchestrator(
      controller: controller,
      sessionRepository: fixture.sessionRepository,
      treeRepository: fixture.treeRepository,
      blueprintRepository: fixture.blueprintRepository,
      pipeline: fixture.pipeline,
      gateway: const _PlanningGateway(),
    );
  });

  tearDown(() async {
    if (!allowGeneration.isCompleted) allowGeneration.complete();
    controller.dispose();
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    await directory.delete(recursive: true);
  });

  test('returns stable identities before terminal generation and reuses them',
      () async {
    const draft = ResourceAiCreationDraft(
      resourceType: ResourceType.worldview,
      name: '统一创建入口',
      referenceSource: ReferenceSource(
        kind: ReferenceSourceKind.text,
        body: '山海之间的城市。',
        characterCount: 8,
      ),
      targetCharacters: 5000,
      idempotencyKey: 'stable-submit-key',
      origin: 'orchestrator-test',
      libraryMode: 'adventure',
    );

    final first = await orchestrator.createAndStart(draft);
    await generationStarted.future.timeout(const Duration(seconds: 2));
    final running =
        await fixture.sessionRepository.findSession(first.generationSessionId);
    expect(running, isNotNull);
    expect(running!.status, isNot(StreamingLifecycleStatus.completed));

    final repeatedSubmit = await orchestrator.createAndStart(draft);
    final continued =
        await orchestrator.continueAndStart(first.creationSessionId);
    expect(repeatedSubmit.creationSessionId, first.creationSessionId);
    expect(repeatedSubmit.resourceId, first.resourceId);
    expect(repeatedSubmit.generationSessionId, first.generationSessionId);
    expect(continued.creationSessionId, first.creationSessionId);
    expect(continued.resourceId, first.resourceId);
    expect(continued.generationSessionId, first.generationSessionId);

    final db = await DatabaseService.database;
    expect(await db.query('resource_creation_sessions'), hasLength(1));
    expect(await db.query('resource_blueprints'), hasLength(1));
    expect(await db.query('resources'), hasLength(1));
    expect(await db.query('resource_generation_tasks'), hasLength(1));
    expect(await db.query('resource_generation_sessions'), hasLength(1));

    allowGeneration.complete();
    await _waitForStatus(
      fixture,
      first.generationSessionId,
      StreamingLifecycleStatus.completed,
    );
  });
}

Future<void> _waitForStatus(
  R01StreamingFixture fixture,
  String sessionId,
  StreamingLifecycleStatus expected,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final session = await fixture.sessionRepository.findSession(sessionId);
    if (session?.status == expected) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  final session = await fixture.sessionRepository.findSession(sessionId);
  fail('会话未进入 ${expected.storageValue}，当前为 ${session?.status}');
}

final class _PlanningGateway implements LlmGateway {
  const _PlanningGateway();

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
  }) async {
    final sectionId =
        RegExp(r'允许的 Section ID：([^,\n]+)').firstMatch(systemPrompt)!.group(1)!;
    final partId =
        RegExp(r'允许的 Part ID：([^,\n]+)').firstMatch(systemPrompt)!.group(1)!;
    return jsonEncode({
      'suggestedName': '统一创建入口',
      'summary': '测试统一创建编排',
      'sections': [
        {
          'id': sectionId,
          'title': '概览',
          'summary': '世界概览',
          'sortOrder': 0,
          'parts': [
            {
              'id': partId,
              'sectionId': sectionId,
              'title': '正文',
              'generationGoal': '生成世界观正文',
              'estimatedLength': 5000,
              'dependencies': <String>[],
              'sortOrder': 0,
            },
          ],
        },
      ],
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}
