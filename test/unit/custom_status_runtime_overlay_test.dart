import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/adventure_runtime_state_resolver.dart';
import 'package:lt_dialogue/config/app_config.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late IAdventureRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_custom_runtime_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    repository = AdventureRepositoryImpl(
      getDb: () => DatabaseService.database,
    );
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('Custom status runtime overlay', () {
    const trust = CustomAttributeItem(
      id: 'trust',
      name: '信任度',
      value: '20/100',
      currentValue: 20,
      maxValue: 100,
    );
    const mood = CustomAttributeItem(
      id: 'mood',
      name: '情绪',
      value: '平静',
    );

    AdventureConfig config() => AdventureConfig(
          name: '旅人',
          supportingCharacters: [
            SupportingCharacter(
              id: 'eileen',
              name: '艾琳',
              customAttributes: const [trust, mood],
            ),
          ],
        );

    Future<void> commitValue({
      required int adventureId,
      required int branchId,
      required int revision,
      required String requestId,
      required String attributeId,
      required Object value,
      String reason = '本轮剧情导致状态变化',
    }) async {
      await repository.commitSceneDialogueTurn(
        SceneDialogueCommit(
          requestId: requestId,
          adventureId: adventureId,
          branchId: branchId,
          userMessage: Message(
            id: '$requestId-user',
            content: '继续',
            isUser: true,
          ),
          assistantMessage: Message(
            id: '$requestId-assistant',
            content: '剧情推进',
            isUser: false,
          ),
          gameState: GameState(adventureId: adventureId),
          runtimeStateDraft: RuntimeStateCommitDraft(
            expectedRevision: revision,
            summary: 'custom status update',
            sourceMessageId: '$requestId-assistant',
            changes: [
              RuntimeStateChangeProposal(
                entityType: RuntimeEntityType.character,
                entityId: 'eileen',
                changeKind: RuntimeChangeKind.primary,
                operation: RuntimeChangeOperation.set,
                path: RuntimeStateChangeProposal.customAttributePath(
                  attributeId,
                ),
                value: value,
                reason: reason,
              ),
            ],
          ),
        ),
      );
    }

    Future<AdventureConfig> frozenConfig(int adventureId) async {
      final row = await repository.getAdventureById(adventureId);
      return AdventureConfig.fromJson(
        jsonDecode(row!['config'] as String) as Map<String, dynamic>,
      );
    }

    test('should preserve frozen baseline and resolve the current overlay',
        () async {
      final adventureId = await repository.createAdventure('overlay', config());

      await commitValue(
        adventureId: adventureId,
        branchId: 0,
        revision: 0,
        requestId: 'turn-1',
        attributeId: 'trust',
        value: 25,
        reason: '艾琳接受了玩家解释',
      );

      final frozen = await frozenConfig(adventureId);
      expect(
        frozen.supportingCharacters.single.customAttributes.first.currentValue,
        20,
      );
      final entities = await repository.getRuntimeEntities(adventureId, 0);
      expect(entities.single.overlay['custom_attributes.trust'], 25);
      final effective = const AdventureRuntimeStateResolver().effectiveConfig(
        frozen,
        entities,
      );
      expect(
        effective
            .supportingCharacters.single.customAttributes.first.currentValue,
        25,
      );
      final prompt = AppConfig.adventurePrompt(
        Brightness.light,
        '测试冒险',
        '普通',
        effective,
        false,
        1,
      );
      expect(prompt, contains('[艾琳] 【参考】信任度：25/100'));
      expect(prompt, isNot(contains('[艾琳] 【参考】信任度：20/100')));
      final persisted = const AdventureRuntimeStateResolver()
          .baselineForPersistence(effective, frozen, entities);
      expect(
        persisted
            .supportingCharacters.single.customAttributes.first.currentValue,
        20,
      );
    });

    test('should overlay a protagonist by its stable adventure identity',
        () async {
      final protagonistConfig = AdventureConfig(
        name: '旅人',
        customAttributes: const [trust],
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: 'selected-protagonist',
            characterId: 'hero-1',
            characterName: '旅人',
            isProtagonist: true,
          ),
        ],
      );
      final adventureId =
          await repository.createAdventure('protagonist', protagonistConfig);
      await repository.commitSceneDialogueTurn(
        SceneDialogueCommit(
          requestId: 'hero-turn',
          adventureId: adventureId,
          branchId: 0,
          userMessage: Message(id: 'hero-u', content: '继续', isUser: true),
          assistantMessage: Message(id: 'hero-a', content: '推进', isUser: false),
          gameState: GameState(adventureId: adventureId),
          runtimeStateDraft: RuntimeStateCommitDraft(
            expectedRevision: 0,
            summary: 'protagonist custom status',
            changes: [
              RuntimeStateChangeProposal(
                entityType: RuntimeEntityType.character,
                entityId: 'hero-1',
                changeKind: RuntimeChangeKind.primary,
                operation: RuntimeChangeOperation.set,
                path: RuntimeStateChangeProposal.customAttributePath('trust'),
                value: 30,
                reason: '主角获得信任',
              ),
            ],
          ),
        ),
      );

      final entities = await repository.getRuntimeEntities(adventureId, 0);
      final effective = const AdventureRuntimeStateResolver().effectiveConfig(
        await frozenConfig(adventureId),
        entities,
      );
      expect(effective.customAttributes.single.currentValue, 30);
      expect(entities.single.entityId, 'hero-1');
    });

    test('should record before after revision parent reason and request',
        () async {
      final adventureId = await repository.createAdventure('history', config());
      await commitValue(
        adventureId: adventureId,
        branchId: 0,
        revision: 0,
        requestId: 'history-1',
        attributeId: 'trust',
        value: 25,
        reason: '第一次建立信任',
      );
      await commitValue(
        adventureId: adventureId,
        branchId: 0,
        revision: 1,
        requestId: 'history-2',
        attributeId: 'trust',
        value: 32,
        reason: '第二次共同作战',
      );

      final changes = await repository.getRecentStateChangesForEntity(
        adventureId,
        0,
        RuntimeEntityType.character,
        'eileen',
      );
      expect(changes, hasLength(2));
      expect(jsonDecode(changes.first['before_json'] as String), 25);
      expect(jsonDecode(changes.first['after_json'] as String), 32);
      expect(changes.first['revision'], 2);
      expect(changes.first['request_id'], 'history-2');
      expect(changes.first['parent_commit_id'], 'runtime-history-1');
      expect(changes.first['reason'], '第二次共同作战');
      expect(changes.first['cause_ref'], 'history-2-assistant');
    });

    test('should reject unknown attributes and invalid values', () async {
      final adventureId = await repository.createAdventure('invalid', config());
      await commitValue(
        adventureId: adventureId,
        branchId: 0,
        revision: 0,
        requestId: 'unknown',
        attributeId: 'missing',
        value: 50,
      );
      await commitValue(
        adventureId: adventureId,
        branchId: 0,
        revision: 0,
        requestId: 'over-max',
        attributeId: 'trust',
        value: 101,
      );

      expect((await repository.getRuntimeHead(adventureId, 0)).revision, 0);
      expect(await repository.getRuntimeEntities(adventureId, 0), isEmpty);
      expect(await repository.getMessages(adventureId), hasLength(4));
    });

    test('should keep independent runtime states for every assembled character',
        () async {
      final adventureId = await repository.createAdventure(
        'multi-character',
        AdventureConfig(
          name: '旅人',
          supportingCharacters: [
            SupportingCharacter(id: 'a', name: 'A'),
            SupportingCharacter(id: 'b', name: 'B'),
            SupportingCharacter(id: 'c', name: 'C'),
          ],
        ),
      );
      for (final id in ['a', 'b', 'c']) {
        await repository.seedRuntimeEntity(
          adventureId: adventureId,
          branchId: 0,
          entityType: RuntimeEntityType.character,
          entityId: id,
        );
      }
      await repository.commitSceneDialogueTurn(
        SceneDialogueCommit(
          requestId: 'multi-hp',
          adventureId: adventureId,
          branchId: 0,
          userMessage: Message(id: 'multi-u', content: '继续', isUser: true),
          assistantMessage:
              Message(id: 'multi-a', content: 'A受伤', isUser: false),
          gameState: GameState(adventureId: adventureId),
          runtimeStateDraft: const RuntimeStateCommitDraft(
            expectedRevision: 0,
            summary: 'character A took damage',
            changes: [
              RuntimeStateChangeProposal(
                entityType: RuntimeEntityType.character,
                entityId: 'a',
                changeKind: RuntimeChangeKind.primary,
                operation: RuntimeChangeOperation.increment,
                path: 'hp',
                value: -25,
                reason: '受到攻击',
              ),
            ],
          ),
        ),
      );

      final entities = await repository.getRuntimeEntities(adventureId, 0);
      expect(entities, hasLength(3));
      expect(
          entities
              .singleWhere((entity) => entity.entityId == 'a')
              .overlay['hp'],
          75);
      expect(
          entities
              .where((entity) => entity.entityId != 'a')
              .every((entity) => entity.overlay.isEmpty),
          isTrue);
      final reopened = AdventureRepositoryImpl(
        getDb: () async => DatabaseService.database,
      );
      expect(await reopened.getRuntimeEntities(adventureId, 0), hasLength(3));
    });

    test('should restore current values without replaying commit history',
        () async {
      final adventureId = await repository.createAdventure('restore', config());
      await commitValue(
        adventureId: adventureId,
        branchId: 0,
        revision: 0,
        requestId: 'restore-1',
        attributeId: 'mood',
        value: '紧张',
      );

      final reopenedRepository = AdventureRepositoryImpl(
        getDb: () => DatabaseService.database,
      );
      final frozen = AdventureConfig.fromJson(
        jsonDecode(
          (await reopenedRepository.getAdventureById(adventureId))!['config']
              as String,
        ) as Map<String, dynamic>,
      );
      final entities =
          await reopenedRepository.getRuntimeEntities(adventureId, 0);
      final effective = const AdventureRuntimeStateResolver().effectiveConfig(
        frozen,
        entities,
      );

      expect(
          frozen.supportingCharacters.single.customAttributes.last.value, '平静');
      expect(effective.supportingCharacters.single.customAttributes.last.value,
          '紧张');
    });

    test('should keep 50-turn runtime heads branch-local and baseline frozen',
        () async {
      final adventureId = await repository.createAdventure('long', config());
      for (var turn = 1; turn <= 50; turn++) {
        await commitValue(
          adventureId: adventureId,
          branchId: 0,
          revision: turn - 1,
          requestId: 'long-$turn',
          attributeId: 'trust',
          value: 20 + turn,
          reason: 'deterministic turn $turn',
        );
      }
      final branchId = await repository.createBranch(
        adventureId: adventureId,
        parentId: 0,
        forkAfterId: 100,
        name: 'branch-b',
      );
      await commitValue(
        adventureId: adventureId,
        branchId: 0,
        revision: 50,
        requestId: 'branch-a',
        attributeId: 'trust',
        value: 90,
      );
      await commitValue(
        adventureId: adventureId,
        branchId: branchId,
        revision: 50,
        requestId: 'branch-b',
        attributeId: 'trust',
        value: 60,
      );

      final root = await repository.getRuntimeEntities(adventureId, 0);
      final branch = await repository.getRuntimeEntities(adventureId, branchId);
      expect(root.single.overlay['custom_attributes.trust'], 90);
      expect(branch.single.overlay['custom_attributes.trust'], 60);
      expect((await repository.getRuntimeHead(adventureId, 0)).revision, 51);
      expect(
        (await repository.getRuntimeHead(adventureId, branchId)).revision,
        51,
      );
      expect(
        (await frozenConfig(adventureId))
            .supportingCharacters
            .single
            .customAttributes
            .first
            .currentValue,
        20,
      );
    });
  });
}
