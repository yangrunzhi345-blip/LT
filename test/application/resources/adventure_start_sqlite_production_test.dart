import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lt_dialogue/application/adventure/adventure_readiness_gate.dart';
import 'package:lt_dialogue/models/adventure_response.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/setting_card_repository_impl.dart';

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
  late SettingCardRepositoryImpl cards;
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
    cards = SettingCardRepositoryImpl(getDb: () => DatabaseService.database);
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

  /// Seeds the lightweight card the library and the Adventure gate now read.
  Future<void> seedCard({
    required String id,
    required SettingCardKind kind,
    required String name,
    required String content,
    String summary = '',
    String mode = 'adventure',
    String originWorldviewId = '',
  }) =>
      cards.save(SettingCard(
        id: id,
        kind: kind,
        name: name,
        summary: summary,
        content: content,
        mode: mode,
        originWorldviewId: originWorldviewId,
        createdAt: '2026-01-01T00:00:00',
        updatedAt: '2026-01-01T00:00:00',
      ));

  for (final method in ['import', 'manual']) {
    test('$method card save → card gate ready → freeze → session → prologue',
        () async {
      const id = '角色-生产链路';
      final encoded = jsonEncode(card('测试角色'));
      await seedCard(
        id: id,
        kind: SettingCardKind.character,
        name: '测试角色',
        content: encoded,
        summary: '回归测试背景',
      );
      final gate = container.read(adventureReadinessGateProvider);
      final statuses = await gate.resolve([id]);
      expect(statuses[id]!.status, AdventureAssetGateStatus.ready);
      final frozen = await gate.enforceAndFreeze(config(id));
      // The card, not a tree revision binding, is the frozen snapshot.
      expect(frozen.resourceBindings, isEmpty);
      final frozenCharacter = frozen.selectedCharacters.single;
      expect(frozenCharacter.characterName, '测试角色');
      expect(frozenCharacter.characterCardJson, isNotNull);
      expect(frozenCharacter.characterCardJson!['content'], contains('回归测试背景'));
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

  test('associated worldview, two characters and NPC freeze together',
      () async {
    await seedCard(
      id: 'world',
      kind: SettingCardKind.worldview,
      name: '测试世界',
      summary: '世界概览',
      content: '世界概览\n\n## detail\n已确认世界',
    );
    for (final id in ['hero', 'companion']) {
      await seedCard(
        id: id,
        kind: SettingCardKind.character,
        name: id,
        content: jsonEncode(card(id)),
        originWorldviewId: 'world',
      );
    }
    await seedCard(
      id: 'npc',
      kind: SettingCardKind.npc,
      name: 'NPC',
      content: '友善',
      originWorldviewId: 'world',
    );
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
    // Cards are frozen into the config instead of tree revision bindings.
    expect(frozen.resourceBindings, isEmpty);
    expect(frozen.worldviewSnapshot?['source_id'], 'world');
    expect(frozen.worldviewSnapshot?['name'], '测试世界');
    expect(
        frozen.selectedCharacters
            .every((item) => item.characterCardJson != null),
        isTrue);
    expect(frozen.selectedCharacters, hasLength(2));
    expect(frozen.npcSnapshots.single.originWorldviewId, 'world');
    expect(frozen.npcSnapshots.single.name, 'NPC');
    expect(frozen.npcSnapshots.single.npcJson, isNotEmpty);
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

  test('a missing card resolves notManaged and never blocks the start',
      () async {
    final gate = container.read(adventureReadinessGateProvider);
    final statuses = await gate.resolve(['missing-card']);
    expect(
        statuses['missing-card']!.status, AdventureAssetGateStatus.notManaged);
    final frozen = await gate.enforceAndFreeze(config('missing-card'));
    expect(frozen.resourceBindings, isEmpty);
    expect(frozen.selectedCharacters.single.characterCardJson, isNull);
  });

  for (final table in ['game_state', 'messages']) {
    test(
        '$table initialization failure rolls back only the new session and permits immediate retry',
        () async {
      const id = 'failed-start-resource';
      await seedCard(
        id: id,
        kind: SettingCardKind.character,
        name: '测试角色',
        content: jsonEncode(card('测试角色')),
      );
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
      expect(await db.query('setting_cards', where: 'id = ?', whereArgs: [id]),
          hasLength(1));
      await db.execute('DROP TRIGGER fail_start');
      final retry = await chat.startAdventureWithConfig(config(id));
      expect(retry, isNot(baseline));
      expect(await repo.getAdventures(), hasLength(2));
      expect(await repo.getMessages(retry), hasLength(1));
    });
  }

  test('legacy rows migrate to cards and freeze by card snapshot', () async {
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
    const id = 'res_legacy_character_cards_legacy-card';
    // The compatibility migration turns the legacy row into a lightweight
    // setting card, reachable by both its stable id and its legacy id.
    final migrated = await cards.findById(id);
    expect(migrated, isNotNull);
    expect(migrated!.name, '旧角色');
    expect(migrated.legacyId, 'legacy-card');
    expect((await cards.findLegacyId('legacy-card'))!.id, id);
    final gate = container.read(adventureReadinessGateProvider);
    expect(
        (await gate.resolve([id]))[id]!.status, AdventureAssetGateStatus.ready);
    final frozen = await gate.enforceAndFreeze(config(id));
    // The card becomes the frozen snapshot authority; no tree binding exists.
    expect(frozen.resourceBindings, isEmpty);
    final frozenCharacter = frozen.selectedCharacters.single;
    expect(frozenCharacter.characterName, '旧角色');
    expect(frozenCharacter.characterCardJson, isNotNull);
    expect(frozenCharacter.characterCardJson!['content'], isNotEmpty);
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
