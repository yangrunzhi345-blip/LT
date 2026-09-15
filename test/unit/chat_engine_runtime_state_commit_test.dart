import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/engines/chat_engine.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/dialogue_level.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/chat_engine_host_fixture.dart';

const _narrative = '艾琳在石桥边停下脚步，确认远处的追兵已经失去踪迹。'
    '夜风掠过河面，火把的倒影随着水波摇曳。你们决定暂时在桥边休整，'
    '并为下一段旅程整理装备和线索。';

final class _RuntimeProposalLlmService extends LLMService {
  _RuntimeProposalLlmService(this.response)
      : super(const LLMConfig(
          provider: LLMProvider.deepseek,
          apiKey: 'test-key',
          baseUrl: 'https://example.invalid',
          model: 'deepseek-flash',
        ));

  final String response;

  @override
  Future<LLMStreamResult> sendMessageStreamDetailed(
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    onChunk(response);
    onDone();
    return LLMStreamResult(
      content: response,
      finishReason: LLMFinishReason.stop,
      responseCompleted: true,
    );
  }
}

final class _RuntimeTurnHarness {
  _RuntimeTurnHarness({
    required this.adventureId,
    required this.repository,
    AdventureConfig? config,
  }) : config = config ??
            AdventureConfig(
              name: '旅人',
              supportingCharacters: [
                SupportingCharacter(id: 'eileen', name: '艾琳'),
              ],
            );

  final int adventureId;
  final IAdventureRepository repository;
  final List<Message> messages = <Message>[];
  final AdventureConfig config;
  GameState gameState = GameState();

  ChatEngine build(
    String response, {
    DialogueLevel dialogueLevel = DialogueLevel.l0,
  }) {
    final llm = _RuntimeProposalLlmService(response);
    return ChatEngine(
      host: ChatDependencies(
        getApiKey: () => 'test-key',
        getApiBaseUrl: () => 'https://example.invalid',
        getProviderType: () => LLMProvider.deepseek,
        getModelName: () => 'deepseek-flash',
        getCustomSystemPrompt: () => '',
        getAuthorsNote: () => '',
        getAuthorsNoteDepth: () => 0,
        getAuthorsNoteFrequency: () => 0,
        getAdventureConfig: () => config,
        getWorldEntries: () => const [],
        getBrightness: () => Brightness.light,
        getGameTopic: () => '测试冒险',
        getGameDifficulty: () => '普通',
        getCompletionParams: () =>
            const CompletionParams(enableThinking: false, maxTokens: 2048),
        getCurrentAdventureId: () => adventureId,
        getCurrentBranchId: () => 0,
        getActivePersona: () => null,
        getSelectedCharacterName: () => null,
        getTts: () => null,
        getLLMService: () => llm,
        setProvider: (_) async {},
        setModel: (_) async {},
        getGameState: () => gameState,
        setGameState: (value) => gameState = value,
        getMessages: () => messages,
        setMessages: (value) {
          messages
            ..clear()
            ..addAll(value);
        },
        getDialogueLevel: () => dialogueLevel,
      ),
      notifyParent: () {},
      adventureRepo: repository,
    );
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late IAdventureRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_runtime_turn_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    repository = AdventureRepositoryImpl(getDb: () => DatabaseService.database);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('ChatEngine runtime state proposal commits', () {
    test('should commit custom status to overlay without mutating baseline',
        () async {
      final config = AdventureConfig(
        name: '旅人',
        supportingCharacters: [
          SupportingCharacter(
            id: 'eileen',
            name: '艾琳',
            customAttributes: const [
              CustomAttributeItem(
                id: 'trust',
                name: '信任度',
                value: '20/100',
                currentValue: 20,
                maxValue: 100,
              ),
            ],
          ),
        ],
      );
      final adventureId =
          await repository.createAdventure('Custom runtime', config);
      const response = '$_narrative\n---JSON---\n'
          '{"scene":"石桥","options":["继续前进","检查装备","观察河面"],'
          '"custom_status_evaluations":[{"character_id":"eileen",'
          '"attribute_id":"trust","changed":true,"operation":"delta",'
          '"value":5,"reason":"艾琳接受了玩家解释"}]}';
      final harness = _RuntimeTurnHarness(
        adventureId: adventureId,
        repository: repository,
        config: config,
      );
      final engine = harness.build(response);
      addTearDown(engine.dispose);

      await engine.sendMessage('我向艾琳解释。');

      final stored = await repository.getAdventureById(adventureId);
      final frozen = AdventureConfig.fromJson(
        jsonDecode(stored!['config'] as String) as Map<String, dynamic>,
      );
      expect(
        frozen.supportingCharacters.single.customAttributes.single.currentValue,
        20,
      );
      final entity =
          (await repository.getRuntimeEntities(adventureId, 0)).single;
      expect(entity.overlay['custom_attributes.trust'], 25);
      expect((await repository.getRuntimeHead(adventureId, 0)).revision, 1);
      final history = await repository.getRecentStateChangesForEntity(
        adventureId,
        0,
        RuntimeEntityType.character,
        'eileen',
      );
      expect(jsonDecode(history.single['before_json'] as String), 20);
      expect(jsonDecode(history.single['after_json'] as String), 25);
      expect(history.single['reason'], '艾琳接受了玩家解释');
      expect(harness.messages.last.content, contains('25/100'));
    });

    test('should commit a canonical AI runtime proposal to the Runtime HEAD',
        () async {
      final adventureId = await repository.createAdventure(
        'Runtime proposal',
        AdventureConfig(
          name: '旅人',
          supportingCharacters: [
            SupportingCharacter(id: 'eileen', name: '艾琳'),
          ],
        ),
      );
      const response = '$_narrative\n---JSON---\n'
          '{"scene":"石桥","options":["继续前进","检查装备","观察河面"],'
          '"runtime_state_changes":[{"entity_type":"character",'
          '"entity_id":"eileen","change_kind":"primary",'
          '"operation":"set","path":"life_status","value":"dead",'
          '"reason":"剧情中明确死亡"}]}';
      final harness =
          _RuntimeTurnHarness(adventureId: adventureId, repository: repository);
      final engine = harness.build(response);
      addTearDown(engine.dispose);

      await engine.sendMessage('我查看艾琳的情况。');

      final head = await repository.getRuntimeHead(adventureId, 0);
      final entity =
          (await repository.getRuntimeEntities(adventureId, 0)).single;
      expect(head.revision, 1);
      expect(entity.entityId, 'eileen');
      expect(entity.overlay['life_status'], 'dead');
      expect(entity.lifecycleStatus, 'dead');
    });

    test('should ignore an invalid proposal without aborting the turn',
        () async {
      final adventureId = await repository.createAdventure(
        'Invalid runtime proposal',
        AdventureConfig(
          name: '旅人',
          supportingCharacters: [
            SupportingCharacter(id: 'eileen', name: '艾琳'),
          ],
        ),
      );
      const response = '$_narrative\n---JSON---\n'
          '{"scene":"石桥","options":["继续前进","检查装备","观察河面"],'
          '"runtime_state_changes":[{"entity_type":"character",'
          '"entity_id":"eileen","change_kind":"primary",'
          '"operation":"increment","path":"life_status","value":1,'
          '"reason":"invalid operation"}]}';
      final harness =
          _RuntimeTurnHarness(adventureId: adventureId, repository: repository);
      final engine = harness.build(response);
      addTearDown(engine.dispose);

      await engine.sendMessage('我查看艾琳的情况。');

      expect(engine.lastErrorType, isNull);
      expect(engine.status, ChatStatus.idle);
      expect((await repository.getRuntimeHead(adventureId, 0)).revision, 0);
      expect(await repository.getRuntimeEntities(adventureId, 0), isEmpty);
      expect(await repository.getMessages(adventureId), hasLength(2));
    });
  });

  // L2 档位：min=400 / target=700 / hardMax=1000。原始正文 1052 个纯汉字
  // （69 个 14 字整句 = 966，再加 40 字句与 46 字句），硬上限 1000 会把聚合结果
  // 恰好收敛到 966。这正是用户截图里「曾经 overflow、最终却合法」的场景：
  // 最终 verdict 必须是 within_range，控制台与 diagnostics_json 都不得再报失败。
  group('ChatEngine final narrative length verdict', () {
    final overLimitNarrative =
        '${'天' * 14}。' * 69 + '${'地' * 40}。' + '${'玄' * 46}。';
    final response = '$overLimitNarrative\n---JSON---\n'
        '{"scene":"石桥","options":["继续前进","检查装备","观察河面"]}';

    /// Captures every [debugPrint] the engine emits for one turn.
    List<String> captureDebugPrint() {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = original);
      return logs;
    }

    test('converged over-limit response is within range in both outputs',
        () async {
      final adventureId = await repository.createAdventure(
        'Length verdict',
        AdventureConfig(name: '旅人'),
      );
      final harness =
          _RuntimeTurnHarness(adventureId: adventureId, repository: repository);
      final engine = harness.build(response, dialogueLevel: DialogueLevel.l2);
      addTearDown(engine.dispose);
      final logs = captureDebugPrint();

      await engine.sendMessage('我继续前进。');

      final monitor = logs.join('\n');
      expect(monitor, contains('字数范围:  400 / 700 / 1000'));
      expect(monitor, contains('实际:      966'));
      expect(monitor, contains('达标:      ✅ 是'));
      expect(monitor, contains('原始响应超出硬上限：1052 → 966，已自动收敛'));
      // 最终正文已回到 [400, 1000] 内，不得再被判成最终 overflow。
      expect(monitor, isNot(contains('最终正文仍超过硬上限')));

      final db = await DatabaseService.database;
      final rows = await db.query(
        'scene_dialogue_turns',
        where: 'adventure_id = ?',
        whereArgs: [adventureId],
      );
      expect(rows, hasLength(1));
      final diagnostics = jsonDecode(rows.single['diagnostics_json'] as String)
          as Map<String, dynamic>;
      expect(diagnostics['length_initial_chinese_chars'], 1052);
      expect(diagnostics['length_final_chinese_chars'], 966);
      expect(diagnostics['length_required_chinese_chars'], 400);
      expect(diagnostics['length_hard_maximum_chinese_chars'], 1000);
      expect(diagnostics['length_overflow_detected'], isTrue);
      expect(diagnostics['length_final_verdict'], 'within_range');
      expect(diagnostics['length_final_passed'], isTrue);
    });
  });
}
