import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/application/adventure/adventure_character_identity.dart';
import 'package:lt_dialogue/application/adventure/adventure_character_status_store.dart';
import 'package:lt_dialogue/application/adventure/adventure_runtime_state_resolver.dart';
import 'package:lt_dialogue/config/app_config.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/providers/adventure_provider.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository_impl.dart';
import 'package:lt_dialogue/services/runtime_state_validator.dart';

/// 回归：selectedCharacters 中的非主角必须能作为检测状态的持久化主体。
///
/// 旧逻辑把 selected-only 角色临时构造的 [SupportingCharacter] 当成已持久化对
/// 象去 `map()` 更新，命中不到任何记录，于是状态永远进不了
/// `adventures.config`。这些用例逐条锁定「添加 → SQLite 落盘 → 重载 →
/// Prompt / runtime tracking」的完整闭环。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late AdventureRepositoryImpl repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_custom_persist_');
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

  AdventureProvider provider() => AdventureProvider(
        adventureRepo: AdventureRepositoryImpl(
          getDb: () => DatabaseService.database,
        ),
        worldEntryRepo: WorldEntryRepositoryImpl(
          getDb: () => DatabaseService.database,
        ),
        libraryRepo: LibraryRepositoryImpl(
          getDb: () => DatabaseService.database,
        ),
      );

  /// 镜像 CharacterStatusScreen 的做法：先解析出视图用的角色条目，再通过唯一的
  /// 持久化权威写回。
  Future<void> saveCompanionStatuses(
    AdventureProvider chat,
    String characterId,
    List<CustomAttributeItem> next,
  ) async {
    final config = chat.adventureConfig!;
    final selected = config.selectedCharacters.firstWhere(
      (c) => AdventureCharacterIdentity.effectiveId(c) == characterId,
    );
    final companion = config.supportingCharacters
            .where((c) => AdventureCharacterIdentity.candidateIds(selected)
                .contains(c.id.trim()))
            .firstOrNull ??
        SupportingCharacter(
          id: AdventureCharacterIdentity.effectiveId(selected),
          name: selected.characterName,
          role: selected.effectiveRole,
        );
    await chat.updateAdventureConfig(
      AdventureCharacterStatusStore.writeCompanionCustomAttributes(
        config: config,
        selected: selected,
        fallbackId: companion.id,
        name: companion.name,
        role: companion.role,
        customAttributes: next,
      ),
    );
  }

  Future<AdventureConfig> storedConfig(int adventureId) async {
    final row = await repository.getAdventureById(adventureId);
    return AdventureConfig.fromJson(
      jsonDecode(row!['config'] as String) as Map<String, dynamic>,
    );
  }

  /// 从 SQLite 重新打开（关闭连接后重连同一份文件），而不是复用内存实例。
  Future<AdventureConfig> reopenFromSqlite(int adventureId) async {
    await DatabaseService.resetDatabase();
    final reopened = AdventureRepositoryImpl(
      getDb: () => DatabaseService.database,
    );
    final row = await reopened.getAdventureById(adventureId);
    return AdventureConfig.fromJson(
      jsonDecode(row!['config'] as String) as Map<String, dynamic>,
    );
  }

  CustomAttributeItem san({int cur = 100, int max = 100}) =>
      CustomAttributeItem(
        id: 'san-alice',
        name: '理智值 (SAN)',
        value: '$cur/$max',
        currentValue: cur,
        maxValue: max,
        icon: '🧠',
        description: '抵抗不可名状与未知恐惧',
        importance: CustomAttributeImportance.important,
      );

  AdventureConfig selectedOnlyConfig() => AdventureConfig(
        name: '莉莉安娜',
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: 'sel-hero',
            characterId: 'hero',
            characterName: '莉莉安娜',
            isProtagonist: true,
            narrativeRole: AdventureCharacterRole.protagonist,
          ),
          AdventureSelectedCharacter(
            id: 'sel-alice',
            characterId: 'alice',
            characterName: '艾莉丝',
            narrativeRole: AdventureCharacterRole.femaleLead,
          ),
        ],
      );

  group('selected-only companion custom status persistence', () {
    test('Case 1: adding a status creates the persistent snapshot in SQLite',
        () async {
      final adventureId = await repository.createAdventure(
          'selected-only', selectedOnlyConfig());
      final chat = provider();
      await chat.loadAdventure(adventureId);
      expect(chat.adventureConfig!.supportingCharacters, isEmpty);

      await saveCompanionStatuses(chat, 'alice', [san()]);

      // 2/3/4：AdventureConfig 中出现带稳定 ID 的持久化快照。
      final afterAdd = chat.adventureConfig!;
      final snapshot = afterAdd.supportingCharacters.single;
      expect(snapshot.id, 'alice');
      expect(snapshot.name, '艾莉丝');
      expect(snapshot.customAttributes.single.id, 'san-alice');
      expect(snapshot.customAttributes.single.characterName, '艾莉丝');

      // 5：数据库 adventures.config 中真实存在。
      final stored = await storedConfig(adventureId);
      expect(
        stored.supportingCharacters
            .singleWhere((c) => c.id == 'alice')
            .customAttributes
            .single
            .identityRef,
        'san-alice',
      );

      // 6/7：关闭页面重新加载（新的 Provider 实例）后仍存在。
      final reloaded = provider();
      await reloaded.loadAdventure(adventureId);
      expect(
        reloaded.adventureConfig!.supportingCharacters
            .singleWhere((c) => c.id == 'alice')
            .customAttributes
            .single
            .currentValue,
        100,
      );

      // 8：重新创建 Repository / reopen DB 后仍存在。
      final reopened = await reopenFromSqlite(adventureId);
      expect(
        reopened.supportingCharacters
            .singleWhere((c) => c.id == 'alice')
            .customAttributes
            .single
            .currentValue,
        100,
      );
    });

    test('Case 2: editing a value survives reload and DB reopen', () async {
      final adventureId =
          await repository.createAdventure('edit', selectedOnlyConfig());
      final chat = provider();
      await chat.loadAdventure(adventureId);
      await saveCompanionStatuses(chat, 'alice', [san()]);
      await saveCompanionStatuses(chat, 'alice', [san(cur: 75)]);

      final stored = await storedConfig(adventureId);
      expect(
        stored.supportingCharacters
            .singleWhere((c) => c.id == 'alice')
            .customAttributes
            .single
            .currentValue,
        75,
      );
      expect(
        stored.supportingCharacters
            .singleWhere((c) => c.id == 'alice')
            .customAttributes,
        hasLength(1),
      );

      final reopened = await reopenFromSqlite(adventureId);
      expect(
        reopened.supportingCharacters
            .singleWhere((c) => c.id == 'alice')
            .customAttributes
            .single
            .value,
        '75/100',
      );
    });

    test('Case 3: deleting a status really removes it from the stored config',
        () async {
      final adventureId =
          await repository.createAdventure('delete', selectedOnlyConfig());
      final chat = provider();
      await chat.loadAdventure(adventureId);
      await saveCompanionStatuses(chat, 'alice', [san()]);
      await saveCompanionStatuses(chat, 'alice', const []);

      final stored = await storedConfig(adventureId);
      expect(
        stored.supportingCharacters
            .singleWhere((c) => c.id == 'alice')
            .customAttributes,
        isEmpty,
      );

      // 重新打开不能复活。
      final reloaded = provider();
      await reloaded.loadAdventure(adventureId);
      expect(
        reloaded.adventureConfig!.supportingCharacters
            .singleWhere((c) => c.id == 'alice')
            .customAttributes,
        isEmpty,
      );
      final reopened = await reopenFromSqlite(adventureId);
      expect(
        reopened.supportingCharacters
            .singleWhere((c) => c.id == 'alice')
            .customAttributes,
        isEmpty,
      );
    });

    test('Case 4: text-only statuses persist for companions', () async {
      final adventureId =
          await repository.createAdventure('text', selectedOnlyConfig());
      final chat = provider();
      await chat.loadAdventure(adventureId);
      const mood = CustomAttributeItem(
        id: 'mind-state',
        name: '精神状态',
        value: '平静',
        importance: CustomAttributeImportance.important,
      );
      await saveCompanionStatuses(chat, 'alice', const [mood]);

      final reopened = await reopenFromSqlite(adventureId);
      final stored = reopened.supportingCharacters
          .singleWhere((c) => c.id == 'alice')
          .customAttributes
          .single;
      expect(stored.name, '精神状态');
      expect(stored.value, '平静');
      expect(stored.isNumeric, isFalse);
      expect(stored.characterName, '艾莉丝');
    });

    test('Case 5: two same-named characters never share one snapshot',
        () async {
      final config = AdventureConfig(
        name: '莉莉安娜',
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: 'sel-hero',
            characterId: 'hero',
            characterName: '莉莉安娜',
            isProtagonist: true,
            narrativeRole: AdventureCharacterRole.protagonist,
          ),
          AdventureSelectedCharacter(
            id: 'sel-1',
            characterId: 'alice-1',
            characterName: '艾莉丝',
          ),
          AdventureSelectedCharacter(
            id: 'sel-2',
            characterId: 'alice-2',
            characterName: '艾莉丝',
          ),
        ],
      );
      final adventureId = await repository.createAdventure('twins', config);
      final chat = provider();
      await chat.loadAdventure(adventureId);

      await saveCompanionStatuses(chat, 'alice-2', [san()]);

      final stored = await storedConfig(adventureId);
      // 只有被编辑的 alice-2 有快照，alice-1 完全没有被串状态。
      expect(stored.supportingCharacters, hasLength(1));
      expect(stored.supportingCharacters.single.id, 'alice-2');
      expect(
        stored.supportingCharacters.single.customAttributes.single.id,
        'san-alice',
      );
      expect(
        stored.supportingCharacters.any((c) => c.id == 'alice-1'),
        isFalse,
      );
    });

    test('Case 6: legacy supporting characters keep working', () async {
      final legacy = AdventureConfig(
        name: '莉莉安娜',
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: 'sel-hero',
            characterId: 'hero',
            characterName: '莉莉安娜',
            isProtagonist: true,
            narrativeRole: AdventureCharacterRole.protagonist,
          ),
        ],
        supportingCharacters: [
          SupportingCharacter(id: 'alice', name: '艾莉丝', role: '治疗师'),
        ],
      );
      final adventureId = await repository.createAdventure('legacy', legacy);
      final chat = provider();
      await chat.loadAdventure(adventureId);

      // 没有对应的 selected 条目时走 fallbackId 路径，仍要命中已有行。
      await chat.updateAdventureConfig(
        AdventureCharacterStatusStore.writeCompanionCustomAttributes(
          config: chat.adventureConfig!,
          selected: null,
          fallbackId: 'alice',
          name: '艾莉丝',
          role: '治疗师',
          customAttributes: [san()],
        ),
      );
      var stored = await storedConfig(adventureId);
      expect(stored.supportingCharacters, hasLength(1));
      expect(stored.supportingCharacters.single.id, 'alice');
      expect(
        stored.supportingCharacters.single.customAttributes.single.currentValue,
        100,
      );

      // 编辑与删除同样保持旧数据。
      await chat.updateAdventureConfig(
        AdventureCharacterStatusStore.writeCompanionCustomAttributes(
          config: chat.adventureConfig!,
          selected: null,
          fallbackId: 'alice',
          name: '艾莉丝',
          role: '治疗师',
          customAttributes: [san(cur: 40)],
        ),
      );
      stored = await storedConfig(adventureId);
      expect(
        stored.supportingCharacters.single.customAttributes.single.currentValue,
        40,
      );

      await chat.updateAdventureConfig(
        AdventureCharacterStatusStore.writeCompanionCustomAttributes(
          config: chat.adventureConfig!,
          selected: null,
          fallbackId: 'alice',
          name: '艾莉丝',
          role: '治疗师',
          customAttributes: const [],
        ),
      );
      stored = await storedConfig(adventureId);
      expect(stored.supportingCharacters.single.customAttributes, isEmpty);
      // 角色本身不能被这次删除抹掉。
      expect(stored.supportingCharacters.single.id, 'alice');
    });

    test('Case 8: the new status reaches allTrackedCustomAttributes and prompt',
        () async {
      final adventureId =
          await repository.createAdventure('prompt', selectedOnlyConfig());
      final chat = provider();
      await chat.loadAdventure(adventureId);
      await saveCompanionStatuses(chat, 'alice', [san()]);

      final stored = await storedConfig(adventureId);
      final tracked = stored.allTrackedCustomAttributes;
      expect(
        tracked.any((a) =>
            a.characterName == '艾莉丝' &&
            a.name == '理智值 (SAN)' &&
            a.identityRef == 'san-alice'),
        isTrue,
      );

      final prompt = AppConfig.adventurePrompt(
        Brightness.light,
        '奇幻森林',
        '普通',
        stored,
        false,
        1,
      );
      expect(prompt, contains('[艾莉丝] 【重要参考】理智值 (SAN)：100/100'));
      expect(prompt, contains('character_id=alice'));
      expect(prompt, contains('attribute_id=san-alice'));
    });

    test('Case 9: RuntimeStateValidator accepts the new companion attribute',
        () async {
      final adventureId =
          await repository.createAdventure('validator', selectedOnlyConfig());
      final chat = provider();
      await chat.loadAdventure(adventureId);
      await saveCompanionStatuses(chat, 'alice', [san()]);
      final stored = await storedConfig(adventureId);

      final accepted = const RuntimeStateValidator().accept(
        [
          RuntimeStateChangeProposal(
            entityType: RuntimeEntityType.character,
            entityId: 'alice',
            changeKind: RuntimeChangeKind.primary,
            operation: RuntimeChangeOperation.set,
            path: RuntimeStateChangeProposal.customAttributePath('san-alice'),
            value: 80,
            reason: '剧情中目睹了不可名状的造物',
          ),
        ],
        config: stored,
      );
      expect(accepted, hasLength(1));
      expect(accepted.single.entityId, 'alice');
    });

    test('Case 10: runtime entity, snapshot id and proposal id converge',
        () async {
      final adventureId =
          await repository.createAdventure('converge', selectedOnlyConfig());
      final chat = provider();
      await chat.loadAdventure(adventureId);

      // 运行期实体由 selectedCharacters 播种，ID 必须与快照一致，否则 overlay
      // 与状态定义无法关联。
      expect(
        chat.runtimeEntities.any((e) =>
            e.entityType == RuntimeEntityType.character &&
            e.entityId == 'alice'),
        isTrue,
      );

      await saveCompanionStatuses(chat, 'alice', [san()]);
      final stored = await storedConfig(adventureId);
      expect(
        stored.supportingCharacters
            .singleWhere((c) => c.id == 'alice')
            .customAttributes
            .single
            .id,
        'san-alice',
      );

      await repository.commitSceneDialogueTurn(
        SceneDialogueCommit(
          requestId: 'converge-1',
          adventureId: adventureId,
          branchId: 0,
          userMessage: Message(id: 'c-u', content: '继续', isUser: true),
          assistantMessage: Message(id: 'c-a', content: '推进', isUser: false),
          gameState: GameState(adventureId: adventureId),
          runtimeStateDraft: RuntimeStateCommitDraft(
            expectedRevision: 0,
            summary: 'san drops',
            sourceMessageId: 'c-a',
            changes: [
              RuntimeStateChangeProposal(
                entityType: RuntimeEntityType.character,
                entityId: 'alice',
                changeKind: RuntimeChangeKind.primary,
                operation: RuntimeChangeOperation.set,
                path:
                    RuntimeStateChangeProposal.customAttributePath('san-alice'),
                value: 60,
                reason: '艾莉丝直视了深渊',
              ),
            ],
          ),
        ),
      );

      // 运行值只落在 overlay，frozen baseline 保持初始值。
      final entities = await repository.getRuntimeEntities(adventureId, 0);
      expect(
        entities
            .singleWhere((e) => e.entityId == 'alice')
            .overlay['custom_attributes.san-alice'],
        60,
      );
      final reopened = await reopenFromSqlite(adventureId);
      expect(
        reopened.supportingCharacters
            .singleWhere((c) => c.id == 'alice')
            .customAttributes
            .single
            .currentValue,
        100,
      );
      final effective = const AdventureRuntimeStateResolver().effectiveConfig(
        reopened,
        entities,
      );
      expect(
        effective.supportingCharacters
            .singleWhere((c) => c.id == 'alice')
            .customAttributes
            .single
            .currentValue,
        60,
      );
    });
  });

  group('protagonist custom status', () {
    /// 镜像 CharacterStatusScreen 的主角分支：绑定主角名后写回配置。
    Future<void> saveProtagonistStatuses(
      AdventureProvider chat,
      List<CustomAttributeItem> next,
    ) async {
      final config = chat.adventureConfig!;
      await chat.updateAdventureConfig(
        config.copyWith(
          customAttributes: AdventureCharacterStatusStore.bindCharacterName(
              next, config.name),
        ),
      );
    }

    test('Case 7: protagonist add, edit, delete and quick adjust still work',
        () async {
      final adventureId =
          await repository.createAdventure('protagonist', selectedOnlyConfig());
      final chat = provider();
      await chat.loadAdventure(adventureId);

      await saveProtagonistStatuses(chat, [san()]);
      expect(
        chat.adventureConfig!.customAttributes.single.characterName,
        '莉莉安娜',
      );

      // quick adjust：-5。
      final adjusted = chat.adventureConfig!.customAttributes.single.copyWith(
        currentValue: 95,
        value: '95/100',
      );
      await saveProtagonistStatuses(chat, [adjusted]);
      expect(chat.adventureConfig!.customAttributes.single.currentValue, 95);

      // 编辑为 75/100。
      await saveProtagonistStatuses(chat, [san(cur: 75)]);
      var stored = await storedConfig(adventureId);
      expect(stored.customAttributes.single.currentValue, 75);
      expect(stored.customAttributes, hasLength(1));

      // 删除后真实消失。
      await saveProtagonistStatuses(chat, const []);
      stored = await storedConfig(adventureId);
      expect(stored.customAttributes, isEmpty);

      final reopened = await reopenFromSqlite(adventureId);
      expect(reopened.customAttributes, isEmpty);
      // 同伴快照不受主角操作影响。
      expect(reopened.supportingCharacters, isEmpty);
    });
  });

  group('identity authority', () {
    test('effectiveId prefers characterId and never falls back to a name', () {
      expect(
        AdventureCharacterIdentity.effectiveId(AdventureSelectedCharacter(
          id: 'sel-a',
          characterId: 'char-a',
          characterName: '艾莉丝',
        )),
        'char-a',
      );
      expect(
        AdventureCharacterIdentity.effectiveId(AdventureSelectedCharacter(
          id: 'sel-a',
          characterId: '',
          characterName: '艾莉丝',
        )),
        'sel-a',
      );
    });

    test('statuses are never bound to a name-matched unrelated character',
        () async {
      final config = AdventureConfig(
        name: '莉莉安娜',
        supportingCharacters: [
          SupportingCharacter(id: 'alice-1', name: '艾莉丝'),
          SupportingCharacter(id: 'alice-2', name: '艾莉丝'),
        ],
      );
      final updated =
          AdventureCharacterStatusStore.writeCompanionCustomAttributes(
        config: config,
        selected: null,
        fallbackId: 'alice-2',
        name: '艾莉丝',
        role: '',
        customAttributes: [san()],
      );
      expect(
        updated.supportingCharacters
            .singleWhere((c) => c.id == 'alice-1')
            .customAttributes,
        isEmpty,
      );
      expect(
        updated.supportingCharacters
            .singleWhere((c) => c.id == 'alice-2')
            .customAttributes
            .single
            .id,
        'san-alice',
      );
    });

    test('a legacy id-less selection falls back to the deterministic legacy id',
        () {
      final config = AdventureConfig(
        name: '莉莉安娜',
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: '',
            characterId: '',
            characterName: '艾莉丝',
          ),
        ],
      );
      final updated =
          AdventureCharacterStatusStore.writeCompanionCustomAttributes(
        config: config,
        selected: config.selectedCharacters.single,
        fallbackId: '',
        name: '艾莉丝',
        role: '治疗师',
        customAttributes: [san()],
      );
      expect(updated.supportingCharacters.single.id,
          SupportingCharacter.legacyIdFor(name: '艾莉丝', role: '治疗师'));
    });
  });
}
