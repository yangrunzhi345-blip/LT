import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/engines/chat_engine.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/dialogue_level.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/scene_dialogue.dart'
    show SceneDialogueCommitResult;
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/models/turn_settlement.dart';
import 'package:lt_dialogue/application/adventure/adventure_runtime_state_resolver.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/chat_engine_host_fixture.dart';

/// BUG-1 回归：非主角自定义检测状态必须随剧情变化。
///
/// 覆盖 prompt 信息完整性（稳定 ID / 当前值 / 范围 / 重要程度 / 检测规则）、
/// changed=true 全链路（parser → merger → validator → DB → effectiveConfig →
/// UI）、changed=false fail-closed、恢复方向与同名角色隔离。
final class _ScriptedLlmService extends LLMService {
  _ScriptedLlmService(this.script)
      : super(const LLMConfig(
          provider: LLMProvider.deepseek,
          apiKey: 'test-key',
          baseUrl: 'https://example.invalid',
          model: 'deepseek-flash',
        ));

  final List<Object> script;
  final List<CompletionParams> params = <CompletionParams>[];
  final List<List<Map<String, String>>> messages =
      <List<Map<String, String>>>[];

  /// Synchronous hook, invoked when call [index] starts.
  void Function(int index)? onCallStart;

  List<int> get settlementCalls => [
        for (var index = 0; index < messages.length; index++)
          if (_isSettlement(index)) index,
      ];

  bool _isSettlement(int index) {
    final first = messages[index].isEmpty ? null : messages[index].first;
    return first != null &&
        first['role'] == 'system' &&
        (first['content'] ?? '').contains('剧情结算器');
  }

  @override
  Future<LLMStreamResult> sendMessageStreamDetailed(
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    final index = this.params.length;
    this.params.add(params);
    this.messages.add(messages);
    onCallStart?.call(index);
    final content = script[index] as String;
    onChunk(content);
    onDone();
    return LLMStreamResult(
      content: content,
      finishReason: LLMFinishReason.stop,
      responseCompleted: true,
    );
  }
}

final class _Harness {
  _Harness(this.config);

  /// Mutable so a test can advance the host's config to the *effective* one
  /// (baseline + runtime overlay) between turns, mirroring production.
  AdventureConfig config;

  /// 当前冒险 ID，创建冒险后由测试赋值。
  int? adventureId;

  final List<Message> messages = <Message>[];
  final List<SceneDialogueCommitResult> commits = <SceneDialogueCommitResult>[];

  ChatEngine build(_ScriptedLlmService llm, IAdventureRepository repo) {
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
        getGameState: () => GameState(hp: 100, maxHp: 100),
        setGameState: (_) {},
        getMessages: () => messages,
        setMessages: (value) {
          messages
            ..clear()
            ..addAll(value);
        },
        getDialogueLevel: () => DialogueLevel.l0,
        onSceneDialogueCommitResult: commits.add,
      ),
      notifyParent: () {},
      adventureRepo: repo,
    );
  }
}

const String _staminaRule = '长途行动、奔跑、战斗、负重、受伤会消耗体力；充分休息会恢复';

/// 足够跨过 L0 的最低字数门槛，同时明确描述体力消耗事件。
const String _exertionNarrative = '艾莉丝沿着废弃的河谷古道长距离奔跑，山路崎岖湿滑，她几次险些跌倒。'
    '傍晚时分，两名盗贼从岩石后扑出，艾莉丝与他们连续战斗了两个回合，'
    '挥刀格挡、翻滚闪避，直到盗贼败退消失在暮色里。她靠着一棵枯树大口喘气，'
    '汗水浸透了衣背，双腿仍在微微发抖。';

const String _restNarrative = '你们在山腰的猎人小屋里安顿下来。艾莉丝喝下热汤，在火堆旁裹着毯子睡了整整一夜。'
    '清晨的阳光照进屋里时，她伸了个懒腰，脸色比昨天好看许多，呼吸也平稳了，'
    '昨夜战斗留下的疲惫已经消退了大半。';

const String _smallTalkNarrative = '你们坐在驿站的角落里闲聊。艾莉丝聊起她年轻时的旅行见闻，偶尔抿一口麦茶，'
    '窗外偶尔有马车驶过。谈话轻松平静，谁也没有起身，屋里的一切都保持原样。';

String _settlementJson({
  List<String> options = const ['查看艾莉丝的状态', '原地休整', '继续赶路'],
  List<Map<String, dynamic>> evaluations = const [],
}) =>
    jsonEncode({
      'schema_version': TurnSettlement.schemaVersion,
      'options': options,
      if (evaluations.isNotEmpty) 'custom_status_evaluations': evaluations,
    });

SupportingCharacter alice({String id = 'alice'}) => SupportingCharacter(
      id: id,
      name: '艾莉丝',
      customAttributes: const [
        CustomAttributeItem(
          id: 'stamina',
          name: '体力值',
          value: '100/100',
          importance: CustomAttributeImportance.important,
          currentValue: 100,
          maxValue: 100,
          description: _staminaRule,
        ),
      ],
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late IAdventureRepository repository;
  late _Harness harness;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_settlement_semantics_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    repository = AdventureRepositoryImpl(getDb: () => DatabaseService.database);
    final config = AdventureConfig(
      name: '旅人',
      supportingCharacters: [alice()],
    );
    harness = _Harness(config);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<int> createAdventure(String title) async {
    final id = await repository.createAdventure(title, harness.config);
    harness.adventureId = id;
    return id;
  }

  /// 把 harness 的 config 推进为「基线 + runtime overlay」的有效配置，
  /// 模拟生产环境 `_host.adventureConfig` 的行为。
  Future<void> advanceConfigToEffective(int adventureId) async {
    final entities = await repository.getRuntimeEntities(adventureId, 0);
    harness.config = const AdventureRuntimeStateResolver()
        .effectiveConfig(harness.config, entities);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Case S1 — 消耗：prompt 信息完整 + delta 全链路落库。
  // ─────────────────────────────────────────────────────────────────────────
  test('Case S1: exertion turn drains stamina 100 -> 90 end to end', () async {
    final adventureId = await createAdventure('S1 消耗');
    final llm = _ScriptedLlmService([
      '$_exertionNarrative\n---JSON---\n{"scene":"河谷古道","options":["a","b","c"]}',
      _settlementJson(evaluations: const [
        {
          'character_id': 'alice',
          'attribute_id': 'stamina',
          'changed': true,
          'operation': 'delta',
          'value': -10,
          'reason': '长距离奔跑并连续战斗',
        },
      ]),
    ]);
    final engine = harness.build(llm, repository);
    addTearDown(engine.dispose);

    await engine.sendMessage('我们全速赶路并击退了盗贼');

    // Prompt 必须携带完整判定信息：稳定 ID、当前值、范围、重要程度、检测规则。
    final settlementIndex = llm.settlementCalls.single;
    final prompt =
        llm.messages[settlementIndex].map((m) => m['content']).join('\n');
    expect(prompt, contains('character_id=alice'));
    expect(prompt, contains('attribute_id=stamina'));
    expect(prompt, contains('角色=艾莉丝'));
    expect(prompt, contains('状态=体力值'));
    expect(prompt, contains('当前=100/100'));
    expect(prompt, contains('范围=0..100'));
    expect(prompt, contains('重要程度=重要参考'));
    expect(prompt, contains('检测规则=$_staminaRule'));
    expect(prompt, contains(_exertionNarrative), reason: 'settlement 必须看到最终正文');

    // 逐状态诊断：模型判定与系统落地都可追溯。
    final diagnostics = harness.commits.single.statusDiagnostics;
    expect(diagnostics, contains('settlement:evaluated:alice:stamina:true'));
    expect(diagnostics, contains('settlement:changed:alice:stamina:delta:-10'));
    expect(diagnostics,
        contains('settlement:applied:alice:stamina:100/100->90/100'));

    // Runtime HEAD 落库。
    final entity = (await repository.getRuntimeEntities(adventureId, 0)).single;
    expect(entity.entityId, 'alice');
    expect(entity.overlay['custom_attributes.stamina'], 90);

    // UI 语义：committed message 的状态快照显示新值。
    final assistant =
        harness.messages.lastWhere((m) => !m.isUser && !m.isError);
    expect(assistant.content, contains('90/100'));
    expect(assistant.content, contains(_exertionNarrative));

    // reopen 后仍保持。
    await DatabaseService.resetDatabase();
    final reopened =
        AdventureRepositoryImpl(getDb: () => DatabaseService.database);
    final reopenedEntity =
        (await reopened.getRuntimeEntities(adventureId, 0)).single;
    expect(reopenedEntity.overlay['custom_attributes.stamina'], 90);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Case S2 — 普通交谈：changed=false，状态与 revision 都不动。
  // ─────────────────────────────────────────────────────────────────────────
  test('Case S2: small talk keeps stamina at 100 (fail-closed)', () async {
    final adventureId = await createAdventure('S2 交谈');
    final llm = _ScriptedLlmService([
      '$_smallTalkNarrative\n---JSON---\n{"scene":"驿站","options":["a","b","c"]}',
      _settlementJson(evaluations: const [
        {
          'character_id': 'alice',
          'attribute_id': 'stamina',
          'changed': false,
          'reason': '普通交谈，没有体力消耗',
        },
      ]),
    ]);
    final engine = harness.build(llm, repository);
    addTearDown(engine.dispose);

    await engine.sendMessage('我们坐下来聊了聊天');

    expect(await repository.getRuntimeEntities(adventureId, 0), isEmpty);
    expect((await repository.getRuntimeHead(adventureId, 0)).revision, 0);
    final diagnostics = harness.commits.single.statusDiagnostics;
    expect(diagnostics, contains('settlement:evaluated:alice:stamina:false'));
    expect(
      diagnostics.where((d) => d.startsWith('settlement:applied')),
      isEmpty,
      reason: 'changed=false 不得产生任何写入',
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Case S3 — 恢复：先消耗到 90，休息一晚恢复到 95。
  // ─────────────────────────────────────────────────────────────────────────
  test('Case S3: rest recovers stamina 90 -> 95 across turns', () async {
    final adventureId = await createAdventure('S3 恢复');
    final llm = _ScriptedLlmService([
      '$_exertionNarrative\n---JSON---\n{"scene":"河谷古道","options":["a","b","c"]}',
      _settlementJson(evaluations: const [
        {
          'character_id': 'alice',
          'attribute_id': 'stamina',
          'changed': true,
          'operation': 'delta',
          'value': -10,
          'reason': '长距离奔跑并连续战斗',
        },
      ]),
      '$_restNarrative\n---JSON---\n{"scene":"猎人小屋","options":["a","b","c"]}',
      _settlementJson(evaluations: const [
        {
          'character_id': 'alice',
          'attribute_id': 'stamina',
          'changed': true,
          'operation': 'delta',
          'value': 5,
          'reason': '充分休息与进食后恢复',
        },
      ]),
    ]);
    final engine = harness.build(llm, repository);
    addTearDown(engine.dispose);

    await engine.sendMessage('我们全速赶路并击退了盗贼');
    expect(
        (await repository.getRuntimeEntities(adventureId, 0))
            .single
            .overlay['custom_attributes.stamina'],
        90);

    // 第二轮开始前，host config 推进为有效配置（生产环境语义）。
    await advanceConfigToEffective(adventureId);
    await engine.sendMessage('我们在小屋里休息一晚');

    final entity = (await repository.getRuntimeEntities(adventureId, 0)).single;
    expect(entity.overlay['custom_attributes.stamina'], 95);
    expect(
      harness.commits.last.statusDiagnostics,
      contains('settlement:applied:alice:stamina:90/100->95/100'),
    );

    await DatabaseService.resetDatabase();
    final reopened =
        AdventureRepositoryImpl(getDb: () => DatabaseService.database);
    final reopenedEntity =
        (await reopened.getRuntimeEntities(adventureId, 0)).single;
    expect(reopenedEntity.overlay['custom_attributes.stamina'], 95);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Case S4 — 两个同名艾莉丝：只有目标稳定 ID 被更新。
  // ─────────────────────────────────────────────────────────────────────────
  test('Case S4: two same-named Alices update only the targeted stable id',
      () async {
    final config = AdventureConfig(
      name: '旅人',
      supportingCharacters: [alice(id: 'alice_a'), alice(id: 'alice_b')],
    );
    harness.config = config;
    final adventureId = await createAdventure('S4 同名');
    final llm = _ScriptedLlmService([
      '$_exertionNarrative\n---JSON---\n{"scene":"河谷古道","options":["a","b","c"]}',
      _settlementJson(evaluations: const [
        {
          'character_id': 'alice_b',
          'attribute_id': 'stamina',
          'changed': true,
          'operation': 'delta',
          'value': -10,
          'reason': '奔跑与战斗的是第二个艾莉丝',
        },
        {
          'character_id': 'alice_a',
          'attribute_id': 'stamina',
          'changed': false,
          'reason': '本轮未出场',
        },
      ]),
    ]);
    final engine = harness.build(llm, repository);
    addTearDown(engine.dispose);

    await engine.sendMessage('我们全速赶路并击退了盗贼');

    // Prompt 必须同时给出两条稳定 ID 不同的追踪槽。
    final prompt = llm.messages[llm.settlementCalls.single]
        .map((m) => m['content'])
        .join('\n');
    expect(prompt, contains('character_id=alice_a'));
    expect(prompt, contains('character_id=alice_b'));

    final entities = await repository.getRuntimeEntities(adventureId, 0);
    final byId = {for (final e in entities) e.entityId: e};
    expect(byId['alice_b']!.overlay['custom_attributes.stamina'], 90);
    expect(byId.containsKey('alice_a'), isFalse, reason: '同名角色的状态必须完全隔离');
    expect(
      harness.commits.single.statusDiagnostics,
      contains('settlement:evaluated:alice_a:stamina:false'),
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Case S5 — changed=true 全链路：parser → merger → validator → DB →
  // effectiveConfig → UI 消息内容。
  // ─────────────────────────────────────────────────────────────────────────
  test(
      'Case S5: changed=true flows through the whole chain into effective '
      'config and the committed message', () async {
    final adventureId = await createAdventure('S5 全链路');
    final llm = _ScriptedLlmService([
      '$_exertionNarrative\n---JSON---\n{"scene":"河谷古道","options":["a","b","c"]}',
      _settlementJson(evaluations: const [
        {
          'character_id': 'alice',
          'attribute_id': 'stamina',
          'changed': true,
          'operation': 'delta',
          'value': -10,
          'reason': '长距离奔跑并连续战斗',
        },
      ]),
    ]);
    final engine = harness.build(llm, repository);
    addTearDown(engine.dispose);

    await engine.sendMessage('我们全速赶路并击退了盗贼');

    // parser/merger：诊断证明变化被接受。
    final diagnostics = harness.commits.single.statusDiagnostics;
    expect(diagnostics,
        contains('settlement:applied:alice:stamina:100/100->90/100'));
    expect(
      diagnostics.where((d) => d.startsWith('settlement:rejected')),
      isEmpty,
    );

    // validator/DB：revision 前进 + overlay 落库。
    expect((await repository.getRuntimeHead(adventureId, 0)).revision, 1);
    final entities = await repository.getRuntimeEntities(adventureId, 0);
    expect(entities.single.overlay['custom_attributes.stamina'], 90);

    // effectiveConfig：UI 读取的有效配置显示新值。
    final effective = const AdventureRuntimeStateResolver()
        .effectiveConfig(harness.config, entities);
    final stamina = effective.supportingCharacters
        .where((c) => c.id == 'alice')
        .single
        .customAttributes
        .where((a) => a.id == 'stamina')
        .single;
    expect(stamina.effectiveCurrentValue, 90);
    expect(stamina.displayValue, '90/100');

    // UI：committed message 的 custom_status 快照渲染为 90/100。
    final assistant =
        harness.messages.lastWhere((m) => !m.isUser && !m.isError);
    expect(assistant.content, contains('"currentValue":90'));
    expect(assistant.content, contains('90/100'));
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Pending assistant presentation 生命周期：冻结 → settling → settled → commit。
  // ─────────────────────────────────────────────────────────────────────────
  test(
      'pending presentation: narrative freezes before settlement and is '
      'released only after commit', () async {
    final adventureId = await createAdventure('Pending lifecycle');
    final llm = _ScriptedLlmService([
      '$_exertionNarrative\n---JSON---\n{"scene":"河谷古道","options":["a","b","c"]}',
      _settlementJson(evaluations: const [
        {
          'character_id': 'alice',
          'attribute_id': 'stamina',
          'changed': true,
          'operation': 'delta',
          'value': -10,
          'reason': '长距离奔跑并连续战斗',
        },
      ]),
    ]);
    final engine = harness.build(llm, repository);
    addTearDown(engine.dispose);

    final phaseAtSettlement = <PendingAssistantPhase>[];
    final contentAtSettlement = <String>[];
    llm.onCallStart = (index) {
      if (index == 1) {
        phaseAtSettlement.add(engine.pendingAssistantPhase);
        contentAtSettlement.add(engine.pendingAssistantContent);
      }
    };

    await engine.sendMessage('我们全速赶路并击退了盗贼');

    expect(phaseAtSettlement, equals([PendingAssistantPhase.settling]),
        reason: 'settlement 启动前正文必须已经冻结');
    final frozen = contentAtSettlement.single;
    expect(frozen, contains(_exertionNarrative));
    expect(frozen, isNot(contains('---JSON---')),
        reason: '冻结内容只含正文，正文 payload 不得提前显示');
    expect(frozen, isNot(contains('"options"')));

    expect(engine.pendingAssistantPhase, PendingAssistantPhase.none,
        reason: 'commit 后 pending 必须释放');
    expect(engine.hasPendingAssistant, isFalse);
    expect(engine.pendingAssistantContent, isEmpty);
    expect(adventureId, greaterThan(0));
  });
}
