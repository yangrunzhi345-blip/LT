import 'package:flutter/material.dart';
import 'package:lt_dialogue/core/widgets/app_buttons.dart';
import 'package:lt_dialogue/models/character_card.dart';
import 'package:lt_dialogue/models/character_card_entry.dart';
import 'package:lt_dialogue/domain/resources/section_control.dart';
import 'package:lt_dialogue/services/resource_integrity_validator.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lt_dialogue/application/adventure/adventure_readiness_gate.dart';
import 'package:lt_dialogue/application/resources/resource_migration_service.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_port.dart';
import 'package:lt_dialogue/application/resources/part_content_commit_service.dart';
import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/models/adventure_response.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/domain/errors/diagnostic_envelope.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/screens/assembly_preview_page.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/screens/adventure_session_screen.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';

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

  for (final length in [8000, 12000, 16000, 20000, 24000]) {
    test('existing card $length: import → library reload → reimport → freeze',
        () async {
      final id = 'import-boundary-$length';
      final body = '文' * length;
      final encoded = jsonEncode({
        'spec': 'chara_card_v2',
        'data': {'name': '边界角色', 'description': body},
      });
      ResourceIntegrityValidator.validateCharacterCard(
          name: '边界角色', jsonData: encoded);
      final imported = CharacterCard.fromJsonString(encoded);
      expect(imported.description, body);
      final port = container.read(resourceCreationPortProvider);
      await port.saveCharacter(
          id: id,
          name: imported.name,
          jsonData: encoded,
          mode: 'adventure',
          authoringMethod: 'import',
          origin: 'boundary-first');
      final library = container.read(libraryRepoProvider);
      final row =
          (await library.getCharacterCards()).singleWhere((r) => r['id'] == id);
      ResourceIntegrityValidator.validateCharacterCard(
          name: '边界角色', jsonData: row['json_data']! as String);
      final loaded = CharacterCardEntry.fromRow(row);
      expect(loaded.hasParseError, isFalse);
      expect(loaded.card.description, body);
      final tree =
          ResourceTreeRepositoryImpl(getDb: () => DatabaseService.database);
      final first = (await tree.readTree(ResourceId(id)))!;
      // Long imported prose may fail the separate per-Part optimization
      // validation; that verdict must never erase or misclassify saved body.
      final optimization = await container
          .read(sectionControlRuntimeProvider)
          .validateSection(first.sections.single.id);
      expect(optimization.state, SectionValidationState.invalid);
      expect((await tree.readTree(ResourceId(id)))!.parts.single.content, body);
      await port.saveCharacter(
          id: id,
          name: loaded.name,
          jsonData: row['json_data']! as String,
          mode: 'adventure',
          authoringMethod: 'import',
          origin: 'boundary-reimport');
      final reread = (await tree.readTree(ResourceId(id)))!;
      expect(reread.parts.single.content, body);
      expect(reread.parts.fold<int>(0, (sum, p) => sum + p.content.length),
          length);
      final gate = container.read(adventureReadinessGateProvider);
      expect((await gate.resolve([id]))[id]!.status,
          AdventureAssetGateStatus.ready);
      final frozen = await gate.enforceAndFreeze(config(id));
      expect(frozen.resourceBindings, hasLength(1));
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

  test(
      'two reported overflow character IDs: review → ready → freeze → unique open session',
      () async {
    container.dispose();
    container = ProviderContainer(overrides: [
      llmGatewayProvider.overrideWithValue(_CompressionGateway())
    ]);
    container.read(assemblyReadinessCompressionLinkProvider);
    final coordinator = container.read(assemblyReadinessCoordinatorProvider);
    final revisions = container.read(resourceRevisionRepositoryProvider);
    final service = container.read(resourceRevisionServiceProvider);
    final tree =
        ResourceTreeRepositoryImpl(getDb: () => DatabaseService.database);
    const ids = ['res_cre_1791593277951938_3', 'res_cre_1791592846335305_2'];
    for (final id in ids) {
      await tree.createResourceTree(ResourceTreeDraft(
          id: ResourceId(id),
          type: ResourceType.character,
          name: id == ids.first ? '艾尔' : '利亚',
          sections: [
            ResourceTreeSectionDraft(title: '背景', parts: [
              for (var i = 0; i < 9; i++)
                ResourceTreePartDraft(title: '背景$i', content: '文' * 2800)
            ]),
          ]));
      final original = await service.captureRevision(ResourceId(id),
          cause: RevisionCause.manualSave);
      final result = await coordinator.prepare(ResourceId(id));
      expect(result.record.state, ReadinessState.preparing);
      expect(
          DiagnosticEnvelope.tryDecode(result.record.validationMessage)!.code,
          'compressionApprovalRequired');
      final candidates = await container
          .read(compressionPublisherProvider)
          .publishableCandidates(ResourceId(id));
      expect(candidates, hasLength(9));
      await coordinator.approveCompression(
          resourceId: ResourceId(id),
          candidateIds:
              candidates.map((candidate) => candidate.candidateId).toList(),
          expectedHeadRevisionId: original.revision!.revisionId.value);
      expect((await coordinator.readiness(ResourceId(id)))!.state,
          ReadinessState.ready);
      final old = await revisions.readState(original.revision!.revisionId);
      expect(
          old.nodes.values
              .where((node) => node.kind == RevisionNodeKind.part)
              .fold<int>(0, (sum, node) => sum + node.content.length),
          25200);
    }
    final input = config(ids.first).copyWith(selectedCharacters: [
      ...config(ids.first).selectedCharacters,
      AdventureSelectedCharacter(
          id: ids.last,
          characterId: ids.last,
          characterName: '利亚',
          narrativeRole: AdventureCharacterRole.companion),
    ]);
    final frozen = await container
        .read(adventureReadinessGateProvider)
        .enforceAndFreeze(input);
    expect(frozen.resourceBindings, hasLength(2));
    final chat = container.read(chatProvider);
    await chat.loadApiKey();
    final starts = await Future.wait([
      chat.startAdventureWithConfig(frozen),
      chat.startAdventureWithConfig(frozen)
    ]);
    expect(starts.first, starts.last);
    expect(chat.isAdventureChatOpen, isTrue);
    final repo = container.read(adventureRepoProvider);
    expect(await repo.getAdventures(), hasLength(1));
    expect(await repo.getMessages(starts.first), hasLength(1));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((request) async {
      await request.drain<void>();
      requests++;
      request.response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      final text = '两人继续旅程。\n\n${AdventureResponse.jsonSeparator}\n'
          '${jsonEncode({
            'scene': '旅途中',
            'options': ['前进']
          })}';
      request.response.write('data: ${jsonEncode({
            'choices': [
              {
                'index': 0,
                'delta': {'content': text},
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
    expect(requests, greaterThan(0));
    final messages = await repo.getMessages(starts.first);
    expect(messages, hasLength(3));
    expect(messages.last.errorType, isNull);
    expect(messages.last.content, contains('两人继续旅程'));
    final db = await DatabaseService.database;
    final savedConfig =
        (await db.query('adventures', columns: ['config'])).single['config'];
    final section = (await tree.readSections(ResourceId(ids.first))).first;
    final part = (await tree.readParts(section.id)).first;
    final token = (await db.query('resource_parts',
            columns: ['updated_at'],
            where: 'id = ?',
            whereArgs: [part.id.value]))
        .single['updated_at']
        .toString();
    await tree.updatePart(
        id: part.id, expectedUpdatedAt: token, content: '后续编辑');
    await service.captureRevision(ResourceId(ids.first),
        cause: RevisionCause.manualSave);
    expect((await db.query('adventures', columns: ['config'])).single['config'],
        savedConfig);
    expect(await repo.getMessages(starts.first), hasLength(3));
    debugPrint(
        'SQLITE_E2E characters=2 originalCharacters=25200 each, candidates=18 ready=2 frozen=2 sessions=1 prologue=1 messages=3 continuation=true snapshotPreserved=true chatOpen=true');
  });

  testWidgets(
      '320px review updates readiness and opens the real Adventure Session',
      (tester) async {
    container.dispose();
    container = ProviderContainer(overrides: [
      llmGatewayProvider.overrideWithValue(_CompressionGateway())
    ]);
    await tester.runAsync(() async {
      await DatabaseService.database;
      container.read(assemblyReadinessCompressionLinkProvider);
      final tree =
          ResourceTreeRepositoryImpl(getDb: () => DatabaseService.database);
      await tree.createResourceTree(ResourceTreeDraft(
          id: const ResourceId('widget_compression'),
          type: ResourceType.character,
          name: '艾尔',
          sections: [
            ResourceTreeSectionDraft(title: '背景', parts: [
              for (var i = 0; i < 9; i++)
                ResourceTreePartDraft(title: '背景$i', content: '文' * 2800)
            ]),
          ]));
      await container.read(resourceRevisionServiceProvider).captureRevision(
          const ResourceId('widget_compression'),
          cause: RevisionCause.manualSave);
      await container
          .read(assemblyReadinessCoordinatorProvider)
          .prepare(const ResourceId('widget_compression'));
      await container.read(chatProvider).loadApiKey();
    });
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(builder: (context, ref, _) {
              final chat = ref.watch(chatProvider);
              if (chat.isAdventureChatOpen) {
                return const AdventureSessionScreen();
              }
              return AssemblyPreviewPage(
                  config: config('widget_compression'),
                  onStartAdventure: (input) async {
                    await chat.startAdventureWithConfig(input);
                  });
            }))));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.byType(AssemblyPreviewPage), findsOneWidget);
    expect(find.textContaining('25200'), findsOneWidget);
    expect(
        tester
            .widget<AppPrimaryButton>(
                find.byKey(const Key('assembly-preview-start-button')))
            .onPressed,
        isNull);
    final review = find.byKey(const Key('assembly-preview-compression-review'));
    expect(review, findsOneWidget);
    await tester.ensureVisible(review);
    await tester.tap(review);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('确认采用并重新装配'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(
        (await container
                .read(assemblyReadinessRepositoryProvider)
                .read('widget_compression'))!
            .state,
        ReadinessState.ready);
    final launch = find.byKey(const Key('assembly-preview-start-button'));
    await tester.ensureVisible(launch);
    await tester.tap(launch);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(find.byType(AdventureSessionScreen), findsOneWidget);
    expect(container.read(chatProvider).isAdventureChatOpen, isTrue);
    expect(await container.read(adventureRepoProvider).getAdventures(),
        hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

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

final class _CompressionGateway implements LlmGateway {
  @override
  bool get isConfigured => true;
  @override
  Future<String> rawCompletion(
          {required String systemPrompt,
          required String instruction,
          int maximumOutputTokens = 4096,
          double temperature = .7,
          LlmTask task = LlmTask.structuredExtraction,
          GenerationTaskHandle? taskHandle}) async =>
      jsonEncode({
        'protocol_version': 1,
        'compressed_content': '文' * 200,
        'retained': {
          'entities': <String>[],
          'relationships': <String>[],
          'timeline': <String>[]
        },
      });
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}
