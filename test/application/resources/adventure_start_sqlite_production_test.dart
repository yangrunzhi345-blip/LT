import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lt_dialogue/application/adventure/adventure_readiness_gate.dart';
import 'package:lt_dialogue/application/resources/resource_migration_service.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_port.dart';
import 'package:lt_dialogue/application/resources/part_content_commit_service.dart';
import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/models/adventure_response.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/domain/errors/diagnostic_envelope.dart';
import 'package:flutter/foundation.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalHttpOverrides = HttpOverrides.current;
  // Real production HTTP transport talks only to the local response fixture.
  HttpOverrides.global = null;
  tearDownAll(() => HttpOverrides.global = originalHttpOverrides);
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  late Directory directory;
  late ProviderContainer container;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/connectivity'),
            (_) async => ['wifi']);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(
                'dev.fluttercommunity.plus/connectivity_status'),
            (_) async => null);
    directory = await Directory.systemTemp.createTemp('lt_start_production_');
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = directory.path;
    container = ProviderContainer();
  });
  tearDown(() async {
    container.dispose();
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    directory.deleteSync(recursive: true);
  });

  Map<String, Object?> card(String name) => {
        'spec': 'chara_card_v2',
        'data': {
          'name': name,
          'description': '回归测试背景',
          'first_mes': '序章开场',
          'gender': '女',
          'age': 24,
          'personality': '冷静',
          'custom_attributes': [
            {'name': '心情', 'value': '平静'}
          ],
        },
      };
  AdventureConfig config(String id) => AdventureConfig(
        name: '测试冒险',
        openingScene: '序章开场',
        openingOptions: ['继续'],
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: id,
            characterId: id,
            characterName: '测试角色',
            isProtagonist: true,
          )
        ],
      );

  for (final method in ['import', 'manual']) {
    test('$method save → real readiness → freeze → session → prologue',
        () async {
      const id = '角色-生产链路';
      final port = container.read(resourceCreationPortProvider);
      await port.saveCharacter(
          id: id,
          name: '测试角色',
          jsonData: jsonEncode(card('测试角色')),
          mode: 'adventure',
          authoringMethod: method,
          origin: 'regression-$method');
      final gate = container.read(adventureReadinessGateProvider);
      final statuses = await gate.resolve([id]);
      expect(statuses[id]!.status, AdventureAssetGateStatus.ready);
      final frozen = await gate.enforceAndFreeze(config(id));
      expect(frozen.resourceBindings, hasLength(1));
      final chat = container.read(chatProvider);
      await chat.loadApiKey();
      final starts = await Future.wait([
        chat.startAdventureWithConfig(frozen),
        chat.startAdventureWithConfig(frozen),
      ]);
      expect(starts[0], starts[1]);
      expect(chat.isAdventureChatOpen, isTrue);
      final repo = container.read(adventureRepoProvider);
      expect(await repo.getAdventures(), hasLength(1));
      expect(await repo.getMessages(starts.first), hasLength(1));
      expect(chat.messages.single.content, contains('序章开场'));
      final revisions = container.read(resourceRevisionRepositoryProvider);
      final latest = await revisions.readHead(
          const ResourceId(id), ResourceRevisionKind.latestHead);
      final assembly = await revisions.readHead(
          const ResourceId(id), ResourceRevisionKind.assembly);
      expect(latest!.contentHash, assembly!.contentHash);
      if (method == 'import') {
        var requests = 0;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          await request.drain<void>();
          requests++;
          request.response.headers.contentType =
              ContentType('text', 'event-stream', charset: 'utf-8');
          final continuation = '旅程继续。\n\n${AdventureResponse.jsonSeparator}\n'
              '${jsonEncode({
                'scene': '旅途中',
                'options': ['前进']
              })}';
          request.response.write('data: ${jsonEncode({
                'choices': [
                  {
                    'index': 0,
                    'delta': {'content': continuation},
                    'finish_reason': null
                  }
                ]
              })}\n\n');
          request.response.write('data: ${jsonEncode({
                'choices': [
                  {
                    'index': 0,
                    'delta': <String, Object?>{},
                    'finish_reason': 'stop'
                  }
                ]
              })}\n\ndata: [DONE]\n\n');
          await request.response.close();
        });
        final settings = container.read(settingsProvider);
        await settings.setProvider(LLMProvider.custom);
        await settings.setApiBaseUrl('http://127.0.0.1:${server.port}/v1');
        await settings.setApiKey('local-fixture-placeholder');
        await settings.setModel('local-fixture-model');
        await chat.sendMessage('继续前进');
        final messages = await repo.getMessages(starts.first);
        expect(requests, greaterThan(0));
        expect(messages, hasLength(3));
        expect(messages.last.isUser, isFalse);
        expect(messages.last.errorType, isNull);
        expect(messages.last.content, contains('旅程继续'));
        // Reopen the connection and prove frozen provenance and history persist.
        await DatabaseService.resetDatabase();
        expect(await repo.getMessages(starts.first), hasLength(3));
      }
    });
  }

  test('editing, unchanged failed save retry and subsequent start', () async {
    const id = 'edit-retry';
    final port = container.read(resourceCreationPortProvider);
    Future<void> save(String description) async {
      final data = card('测试角色');
      (data['data']! as Map<String, Object?>)['description'] = description;
      await port.saveCharacter(
          id: id,
          name: '测试角色',
          jsonData: jsonEncode(data),
          mode: 'adventure',
          origin: 'edit-regression');
    }

    await save('原始正文');
    final coordinator = container.read(assemblyReadinessCoordinatorProvider);
    coordinator.debugInterleaveHook =
        () async => throw StateError('private-body-sentinel');
    await save('编辑后的正文');
    final repo = container.read(assemblyReadinessRepositoryProvider);
    expect((await repo.read(id))!.state, ReadinessState.failed);
    coordinator.debugInterleaveHook = null;
    await save('编辑后的正文');
    expect((await repo.read(id))!.state, ReadinessState.ready);
    coordinator.debugInterleaveHook =
        () async => throw StateError('private-body-sentinel');
    await coordinator.prepare(const ResourceId(id));
    expect((await repo.read(id))!.state, ReadinessState.failed);
    coordinator.debugInterleaveHook = null;
    final updated = card('测试角色');
    (updated['data']! as Map<String, Object?>)['description'] = '编辑后的正文';
    final batch = await port.saveCards([
      LegacyCardSave(
          type: ResourceType.character,
          id: id,
          name: '测试角色',
          jsonData: jsonEncode(updated),
          mode: 'adventure',
          origin: 'edit-regression')
    ]);
    expect(batch.single.reusedExisting, isTrue);
    expect((await repo.read(id))!.state, ReadinessState.ready);
    final chat = container.read(chatProvider);
    await chat.loadApiKey();
    final adventure = await chat.startAdventureWithConfig(config(id));
    expect(await container.read(adventureRepoProvider).getMessages(adventure),
        hasLength(1));
  });

  test('production AI generation commits parts and starts Adventure', () async {
    container.dispose();
    container = ProviderContainer(
        overrides: [llmGatewayProvider.overrideWithValue(_AiResponses())]);
    await container.read(settingsProvider).loadApiKey();
    await container.read(settingsProvider).setApiKey('test-only-placeholder');
    final runtime = container.read(resourceStudioRuntimeProvider);
    final completion = runtime.events
        .firstWhere((event) =>
            event is GenerationCompleted || event is GenerationFailed)
        .timeout(const Duration(seconds: 15));
    final session = await runtime.createAndStart(
        resourceType: ResourceType.character,
        name: 'AI生成角色',
        referenceSource: ReferenceSource.text('回归参考'),
        targetCharacters: 1000,
        idempotencyKey: 'ai-production-start');
    expect(await completion, isA<GenerationCompleted>());
    final finished = await runtime.getSession(session.sessionId);
    expect(finished!.status, StreamingLifecycleStatus.completed);
    final id = session.resourceId.value;
    final gate = container.read(adventureReadinessGateProvider);
    expect(
        (await gate.resolve([id]))[id]!.status, AdventureAssetGateStatus.ready);
    final chat = container.read(chatProvider);
    await chat.loadApiKey();
    final adventure = await chat.startAdventureWithConfig(config(id));
    expect(await container.read(adventureRepoProvider).getMessages(adventure),
        hasLength(1));
    final tree = (await runtime.readTree(session.resourceId))!;
    final part = tree.parts.single;
    final db = await DatabaseService.database;
    final row = (await db.query('resource_parts',
            where: 'id = ?', whereArgs: [part.id.value]))
        .single;
    await container
        .read(partContentCommitServiceProvider)
        .applyContent(PartContentCommitRequest(
          partId: part.id,
          expectedUpdatedAt: row['updated_at']! as String,
          content: '手动编辑后重新生成',
        ));
    expect((await gate.resolve([id]))[id]!.status,
        AdventureAssetGateStatus.staleWithPreviousReady);
    expect(await runtime.retryPart(session.sessionId, part.id.value), isTrue);
    expect(
        (await container.read(assemblyReadinessRepositoryProvider).read(id))!
            .state,
        ReadinessState.ready);
    expect(
        (await gate.resolve([id]))[id]!.status, AdventureAssetGateStatus.ready);
  });

  test('associated worldview, two characters and NPC freeze together',
      () async {
    final port = container.read(resourceCreationPortProvider);
    await port.saveWorldview(
        id: 'world',
        name: '测试世界',
        description: '世界概览',
        detailJson: jsonEncode({
          'modules': {
            'overview': {'summary': '已确认世界', 'status': 'confirmed'}
          }
        }),
        entriesJson: '[]',
        mode: 'adventure',
        origin: 'world-regression');
    for (final id in ['hero', 'companion']) {
      await port.saveCharacter(
          id: id,
          name: id,
          jsonData: jsonEncode(card(id)),
          matchingWorldviewId: 'world',
          mode: 'adventure',
          origin: 'multi-regression');
    }
    await port.saveNpc(
        id: 'npc',
        name: 'NPC',
        jsonData: jsonEncode({
          'name': 'NPC',
          'personality': '友善',
          'affinity': 50,
          'isAlive': true,
        }),
        matchingWorldviewId: 'world',
        mode: 'adventure',
        origin: 'multi-regression');
    final input = config('hero').copyWith(
      worldviewSnapshot: {'source_id': 'world'},
      selectedCharacters: [
        ...config('hero').selectedCharacters,
        AdventureSelectedCharacter(
            id: 'companion',
            characterId: 'companion',
            characterName: 'companion',
            narrativeRole: AdventureCharacterRole.companion),
      ],
      supportingCharacters: [SupportingCharacter(id: 'npc', name: 'NPC')],
      npcSnapshots: [
        AdventureNpcSnapshot(
            assetId: 'npc',
            name: 'NPC',
            originWorldviewId: 'world',
            npcJson: const {})
      ],
    );
    final frozen = await container
        .read(adventureReadinessGateProvider)
        .enforceAndFreeze(input);
    expect(frozen.resourceBindings.map((item) => item.resourceId).toSet(),
        {'world', 'hero', 'companion', 'npc'});
    expect(frozen.npcSnapshots.single.originWorldviewId, 'world');
    expect(frozen.supportingCharacters.single.affinity, 50);
    final chat = container.read(chatProvider);
    await chat.loadApiKey();
    final again = await container
        .read(adventureReadinessGateProvider)
        .enforceAndFreeze(input);
    final starts = await Future.wait([
      chat.startAdventureWithConfig(frozen),
      chat.startAdventureWithConfig(again)
    ]);
    expect(starts[0], starts[1]);
    final id = starts.first;
    expect(await container.read(adventureRepoProvider).getAdventures(),
        hasLength(1));
    expect(await container.read(adventureRepoProvider).getMessages(id),
        hasLength(1));
  });

  test('corrupt revision fails closed with safe stage diagnostics and recovers',
      () async {
    const id = 'hash-regression';
    await container.read(resourceCreationPortProvider).saveCharacter(
        id: id,
        name: '测试角色',
        jsonData: jsonEncode(card('测试角色')),
        mode: 'adventure',
        origin: 'hash-regression');
    final db = await DatabaseService.database;
    final head = (await container
        .read(resourceRevisionRepositoryProvider)
        .readHead(const ResourceId(id), ResourceRevisionKind.latestHead))!;
    final row = (await db.query('resource_revision_nodes',
            where: 'revision_id = ? AND node_kind = ?',
            whereArgs: [head.revisionId.value, 'part'],
            limit: 1))
        .single;
    final logs = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? text, {int? wrapWidth}) {
      if (text != null) logs.add(text);
    };
    try {
      await db.update(
          'resource_revision_nodes', {'content': 'private-body-sentinel'},
          where: 'revision_id = ? AND node_id = ?',
          whereArgs: [head.revisionId.value, row['node_id']]);
      final coordinator = container.read(assemblyReadinessCoordinatorProvider);
      final failure = await coordinator.prepare(const ResourceId(id));
      expect(failure.record.state, ReadinessState.failed);
      final diagnostic =
          DiagnosticEnvelope.tryDecode(failure.record.failureReason)!;
      expect(diagnostic.code, 'revisionHashMismatch');
      expect(diagnostic.parameters['stage'], 'assemblyBuild');
      expect(diagnostic.parameters['resourceType'], 'character');
      expect(
          diagnostic.parameters['exceptionType'], 'ResourceAssemblyException');
      await expectLater(
          container
              .read(adventureReadinessGateProvider)
              .enforceAndFreeze(config(id)),
          throwsA(isA<AdventureReadinessGateException>()
              .having((e) => e.issues.single.assetId, 'resource', id)));
      expect(
          await container.read(adventureRepoProvider).getAdventures(), isEmpty);
      expect(logs.join(), isNot(contains('private-body-sentinel')));
      await db.update('resource_revision_nodes', {'content': row['content']},
          where: 'revision_id = ? AND node_id = ?',
          whereArgs: [head.revisionId.value, row['node_id']]);
      final gate = container.read(adventureReadinessGateProvider);
      await gate.prepare(id);
      expect((await gate.resolve([id]))[id]!.status,
          AdventureAssetGateStatus.ready);
    } finally {
      debugPrint = originalDebugPrint;
    }
  });

  test(
      'inconsistent readiness hash and interrupted preparation require real retry',
      () async {
    const id = 'readiness-recovery';
    await container.read(resourceCreationPortProvider).saveCharacter(
        id: id,
        name: '测试角色',
        jsonData: jsonEncode(card('测试角色')),
        mode: 'adventure',
        origin: 'readiness-recovery');
    final db = await DatabaseService.database;
    final gate = container.read(adventureReadinessGateProvider);
    await db.update(
        'resource_assembly_readiness', {'assembly_content_hash': 'incorrect'},
        where: 'resource_id = ?', whereArgs: [id]);
    expect((await gate.resolve([id]))[id]!.status,
        AdventureAssetGateStatus.staleWithPreviousReady);
    await expectLater(gate.enforceAndFreeze(config(id)),
        throwsA(isA<AdventureReadinessGateException>()));
    await gate.prepare(id);
    expect(
        (await gate.resolve([id]))[id]!.status, AdventureAssetGateStatus.ready);
    await db.update('resource_assembly_readiness',
        {'state': 'preparing', 'attempt_token': 'dead-process'},
        where: 'resource_id = ?', whereArgs: [id]);
    final coordinator = container.read(assemblyReadinessCoordinatorProvider);
    expect(await coordinator.recoverInterrupted(), 1);
    expect((await gate.resolve([id]))[id]!.status,
        AdventureAssetGateStatus.failed);
    await gate.prepare(id);
    expect(
        (await gate.resolve([id]))[id]!.status, AdventureAssetGateStatus.ready);
  });

  test('a missing previously bound managed resource blocks session creation',
      () async {
    const id = 'missing-managed';
    await container.read(resourceCreationPortProvider).saveCharacter(
        id: id,
        name: '测试角色',
        jsonData: jsonEncode(card('测试角色')),
        mode: 'adventure',
        origin: 'missing-regression');
    final gate = container.read(adventureReadinessGateProvider);
    final frozen = await gate.enforceAndFreeze(config(id));
    final db = await DatabaseService.database;
    await db.update(
        'resources', {'deleted_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
    await expectLater(
        gate.enforceAndFreeze(frozen),
        throwsA(isA<AdventureReadinessGateException>().having(
            (error) => error.issues.single.parameters['diagnosticCode'],
            'missing resource',
            'resourceMissing')));
    expect(
        await container.read(adventureRepoProvider).getAdventures(), isEmpty);
  });

  for (final table in ['game_state', 'messages']) {
    test(
        '$table initialization failure rolls back only the new session and permits immediate retry',
        () async {
      const id = 'failed-start-resource';
      await container.read(resourceCreationPortProvider).saveCharacter(
          id: id,
          name: '测试角色',
          jsonData: jsonEncode(card('测试角色')),
          mode: 'adventure',
          origin: 'rollback-regression');
      final chat = container.read(chatProvider);
      await chat.loadApiKey();
      final baseline = await chat
          .startAdventureWithConfig(config(id).copyWith(name: '历史会话'));
      final db = await DatabaseService.database;
      await db.execute(
          "CREATE TRIGGER fail_start BEFORE INSERT ON $table BEGIN SELECT RAISE(ABORT, 'injected-start-failure'); END");
      await expectLater(chat.startAdventureWithConfig(config(id)),
          throwsA(isA<DatabaseException>()));
      final repo = container.read(adventureRepoProvider);
      expect(await repo.getAdventures(), hasLength(1));
      expect(await repo.getMessages(baseline), hasLength(1));
      expect(await db.query('resources', where: 'id = ?', whereArgs: [id]),
          hasLength(1));
      await db.execute('DROP TRIGGER fail_start');
      final retry = await chat.startAdventureWithConfig(config(id));
      expect(retry, isNot(baseline));
      expect(await repo.getAdventures(), hasLength(2));
      expect(await repo.getMessages(retry), hasLength(1));
    });
  }

  test('legacy migration with no captured head can prepare and freeze',
      () async {
    final old = await openDatabase('${directory.path}/adventures.db',
        version: 41, onCreate: (db, _) => DatabaseService.createV41Schema(db));
    await old.insert('character_cards', {
      'id': 'legacy-card',
      'name': '旧角色',
      'json_data': jsonEncode(card('旧角色')),
      'created_at': '2025-01-01',
      'updated_at': '2025-01-01',
    });
    await old.close();
    final db = await DatabaseService.database;
    expect(await db.getVersion(), DatabaseService.schemaVersion);
    await ResourceMigrationService(getDb: () => DatabaseService.database).run();
    const id = 'res_legacy_character_cards_legacy-card';
    final revisions = container.read(resourceRevisionRepositoryProvider);
    expect(
        await revisions.readHead(
            const ResourceId(id), ResourceRevisionKind.latestHead),
        isNull);
    final gate = container.read(adventureReadinessGateProvider);
    await gate.prepare(id);
    final frozen = await gate.enforceAndFreeze(config(id));
    expect(frozen.resourceBindings, hasLength(1));
    expect(await db.query('character_cards'), hasLength(1));
    final chat = container.read(chatProvider);
    await chat.loadApiKey();
    final adventureId = await chat.startAdventureWithConfig(frozen);
    final repo = container.read(adventureRepoProvider);
    expect(await repo.getAdventures(), hasLength(1));
    expect(await repo.getMessages(adventureId), hasLength(1));
    expect(chat.isAdventureChatOpen, isTrue);
    expect(await db.query('character_cards'), hasLength(1));
  });
}

final class _AiResponses implements LlmGateway {
  int generatedParts = 0;
  static const suggestedName = 'AI生成角色';

  @override
  bool get isConfigured => true;

  @override
  Future<String> rawCompletion(
      {required String systemPrompt,
      required String instruction,
      int maximumOutputTokens = 4096,
      double temperature = .7,
      LlmTask task = LlmTask.structuredExtraction,
      GenerationTaskHandle? taskHandle}) async {
    if (!systemPrompt.contains('"generation_id"')) {
      final sectionId = RegExp(r'允许的 Section ID：([^,\n]+)')
          .firstMatch(systemPrompt)!
          .group(1)!;
      final partId =
          RegExp(r'允许的 Part ID：([^,\n]+)').firstMatch(systemPrompt)!.group(1)!;
      return jsonEncode({
        'suggestedName': suggestedName,
        'summary': '城市与居民',
        'sections': [
          {
            'id': sectionId,
            'title': '概览',
            'summary': '城市',
            'sortOrder': 0,
            'parts': [
              {
                'id': partId,
                'sectionId': sectionId,
                'title': '正文',
                'generationGoal': '描写城市',
                'estimatedLength': 800,
                'dependencies': <String>[],
                'sortOrder': 0
              }
            ]
          }
        ],
      });
    }
    final ids = <String, String>{};
    for (final key in [
      'generation_id',
      'resource_id',
      'section_id',
      'part_id',
      'attempt_id'
    ]) {
      ids[key] = RegExp('"$key": "(.*?)"').firstMatch(systemPrompt)!.group(1)!;
    }
    final content = 'AI生成正文：山海之间的城市和居民。第${++generatedParts}次生成。';
    return [
      {
        'protocol_version': 1,
        ...ids,
        'sequence': 0,
        'op': 'start_part',
        'cursor': 0,
      },
      {
        'protocol_version': 1,
        ...ids,
        'sequence': 1,
        'op': 'append_text',
        'text_delta': content,
        'cursor': 0,
      },
      {
        'protocol_version': 1,
        ...ids,
        'sequence': 2,
        'op': 'complete_part',
        'cursor': content.length,
        'summary': '城市',
      },
    ].map(jsonEncode).join('\n');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}
