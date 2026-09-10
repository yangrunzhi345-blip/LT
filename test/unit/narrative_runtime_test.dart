import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/narrative/conflict_resolver.dart';
import 'package:lt_dialogue/application/adventure/adventure_runtime_state_resolver.dart';
import 'package:lt_dialogue/application/narrative/narrative_context.dart';
import 'package:lt_dialogue/application/narrative/prompt_compiler.dart';
import 'package:lt_dialogue/application/narrative/user_intent.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/model_context_capability.dart';
import 'package:lt_dialogue/models/scene_state.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/models/world_entry.dart';
import 'package:lt_dialogue/services/runtime_state_validator.dart';

void main() {
  const capability = ModelContextCapability(
    providerId: 'test',
    modelId: 'test',
    maximumContextTokens: 8192,
    maximumOutputTokens: 2048,
  );

  group('IntentResolver', () {
    const resolver = IntentResolver();

    test('should preserve raw input and extract cancellation and new goal', () {
      const input = '我不去王宫了，我去酒馆。';
      final intent = resolver.resolve(input);

      expect(intent.rawInput, input);
      expect(intent.refusals, contains('我不去王宫了'));
      expect(intent.goals, contains('我去酒馆'));
      expect(intent.changesPreviousGoal, isTrue);
    });

    test('should resolve excluded characters only from known roster', () {
      final intent = resolver.resolve(
        '不要让艾琳跟着我。',
        knownCharacters: const {'npc-eileen': '艾琳'},
      );

      expect(intent.rawInput, '不要让艾琳跟着我。');
      expect(intent.excludedCharacterIds, ['npc-eileen']);
    });

    test('should only request archive retrieval for explicit history questions',
        () {
      expect(resolver.resolve('艾琳为什么会变成这样？').asksHistory, isTrue);
      expect(resolver.resolve('What happened before?').asksCause, isFalse);
      expect(resolver.resolve('What happened before?').asksHistory, isTrue);
      expect(resolver.resolve('我走向酒馆。').asksHistory, isFalse);
    });
  });

  group('NarrativeConflictResolver', () {
    const resolver = NarrativeConflictResolver();

    test('should cancel an old scene goal when current user refuses it', () {
      const state = SceneState(
        goals: [
          SceneGoal(id: 'palace', description: '前往王宫'),
        ],
      );
      final intent = const IntentResolver().resolve('我不去王宫了，我去酒馆。');
      final result = resolver.resolve(state, intent);

      expect(
        result.sceneState.goals
            .firstWhere((goal) => goal.id == 'palace')
            .status,
        SceneGoalStatus.cancelled,
      );
      expect(
        result.sceneState.activeGoals.map((goal) => goal.description),
        contains('我去酒馆'),
      );
      expect(
        result.triggeredRules,
        contains('current_user_cancels_scene_goal:palace'),
      );
    });
  });

  group('ContextOrchestrator and PromptCompiler', () {
    const orchestrator = ContextOrchestrator();
    const compiler = PromptCompiler();

    NarrativeContext buildContext({
      required String input,
      SceneState sceneState = const SceneState(location: '白港'),
      List<WorldEntry> entries = const [],
      List<Message> messages = const [],
      String? summary,
      AdventureConfig? config,
      List<RuntimeEntityState> runtimeEntities = const [],
    }) {
      return orchestrator.build(
        rawInput: input,
        config: config,
        sceneState: sceneState,
        worldEntries: entries,
        messages: messages,
        summary: summary,
        persona: null,
        capability: capability,
        requestedResponseTokens: 1024,
        runtimeRevision: 7,
        runtimeEntities: runtimeEntities,
      );
    }

    test('should preserve impossible action while applying world constraint',
        () {
      final context = buildContext(
        input: '我尝试释放火球。',
        entries: [
          WorldEntry(
            id: 1,
            content: '【世界观/世界规则】不存在魔法。',
            keys: const ['魔法', '火球'],
            sticky: 1,
            sourceType: 'worldview_snapshot',
          ),
        ],
      );
      final prompt = compiler.compile(
        runtimePolicy: '输出叙事与 JSON。',
        context: context,
      );

      expect(prompt.messages.last['content'], '【当前玩家意图】\n我尝试释放火球。');
      expect(prompt.messages.first['content'], contains('不存在魔法'));
      expect(prompt.messages.first['content'], contains('必须呈现尝试'));
    });

    test('should make current betrayal override historical summary', () {
      final context = buildContext(
        input: '我决定背叛帝国。',
        summary: '玩家准备帮助帝国。',
      );
      final prompt = compiler.compile(
        runtimePolicy: 'runtime',
        context: context,
      );

      expect(prompt.messages.first['content'], contains('仅用于连续性'));
      expect(prompt.messages.first['content'], contains('不是玩家当前命令'));
      expect(prompt.messages.last['content'], endsWith('我决定背叛帝国。'));
    });

    test('should retain invitation and use personality only as a reaction', () {
      final config = AdventureConfig(
        name: '主角',
        supportingCharacters: [
          SupportingCharacter(
            id: 'eileen',
            name: '艾琳',
            personality: '极度谨慎',
          ),
        ],
      );
      final context = buildContext(
        input: '我邀请艾琳一起潜入。',
        sceneState: const SceneState(
          location: '白港',
          presentCharacterIds: ['protagonist', 'eileen'],
        ),
        config: config,
      );
      final prompt = compiler.compile(
        runtimePolicy: 'runtime',
        context: context,
      );

      expect(prompt.messages.first['content'], contains('极度谨慎'));
      expect(prompt.messages.first['content'], contains('不得删除玩家的邀请'));
      expect(prompt.messages.last['content'], endsWith('我邀请艾琳一起潜入。'));
    });

    test('should prefer frozen selected character over duplicate legacy entry',
        () {
      final config = AdventureConfig(
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: 'eileen',
            characterId: 'eileen',
            characterName: '艾琳',
            characterCardJson: {
              'personality': '冻结后的冷静判断',
            },
          ),
        ],
        supportingCharacters: [
          SupportingCharacter(
            id: 'eileen',
            name: '艾琳',
            personality: '资料库旧版本性格',
          ),
        ],
      );
      final context = buildContext(
        input: '艾琳怎么看？',
        sceneState: const SceneState(
          location: '白港',
          presentCharacterIds: ['eileen'],
        ),
        config: config,
      );

      expect(context.characterContext, contains('冻结后的冷静判断'));
      expect(context.characterContext, isNot(contains('资料库旧版本性格')));
    });

    test('should deduplicate legacy character by selected character ID alias',
        () {
      final config = AdventureConfig(
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: 'selected-row',
            characterId: 'asset-eileen',
            characterName: '艾琳',
            characterCardJson: {'personality': '冻结人格'},
          ),
        ],
        supportingCharacters: [
          SupportingCharacter(
            id: 'asset-eileen',
            name: '艾琳',
            personality: '旧人格',
          ),
          SupportingCharacter(
            id: 'legacy-keeper',
            name: '守门人',
            personality: '真正的旧角色',
          ),
        ],
      );
      final context = buildContext(
        input: '艾琳和守门人怎么看？',
        sceneState: const SceneState(
          location: '白港',
          presentCharacterIds: ['asset-eileen', 'legacy-keeper'],
        ),
        config: config,
      );

      expect(context.characterContext, contains('冻结人格'));
      expect(context.characterContext, isNot(contains('旧人格')));
      expect(context.characterContext, contains('真正的旧角色'));
    });

    test('should inject duplicate worldview content only once', () {
      final context = buildContext(
        input: '查看白港的宵禁情况。',
        entries: [
          WorldEntry(
            id: 1,
            content: '【世界观/locations】白港实行宵禁。',
            keys: const ['白港', '宵禁'],
            sourceType: 'worldview_snapshot',
          ),
          WorldEntry(
            id: 2,
            content: '【世界观/locations】白港实行宵禁。',
            keys: const ['白港'],
            sourceType: 'legacy',
          ),
        ],
      );
      final system = compiler
          .compile(runtimePolicy: 'runtime', context: context)
          .messages
          .first['content']!;

      expect('白港实行宵禁'.allMatches(system), hasLength(1));
      expect(context.world.filteredEntryIds, contains(2));
    });

    test('should exclude trailing unresponded user message from history', () {
      const input = '这是本轮唯一的玩家输入。';
      final context = buildContext(
        input: input,
        messages: [
          Message(id: 'assistant', content: '上一轮回复', isUser: false),
          Message(id: 'user', content: input, isUser: true),
        ],
      );
      final prompt = compiler.compile(
        runtimePolicy: 'runtime',
        context: context,
      );

      expect(
        prompt.messages.where((message) => message['content']!.contains(input)),
        hasLength(1),
      );
      expect(prompt.messages.last['content'], '【当前玩家意图】\n$input');
    });

    test('should retrieve relevant lore within budget and protect user input',
        () {
      const input = '我调查白港城卫队。';
      final entries = [
        for (var index = 0; index < 100; index++)
          WorldEntry(
            id: index,
            keys: [index == 42 ? '白港' : '无关词$index'],
            content: index == 42
                ? '【世界观/locations】白港由城卫队巡逻。'
                : '【世界观/timeline】${List.filled(200, '无关历史资料').join()}',
            sourceType: 'worldview_snapshot',
          ),
      ];
      final context = buildContext(input: input, entries: entries);

      expect(context.world.all.map((item) => item.entryId), contains(42));
      expect(context.world.all.length, lessThan(entries.length));
      expect(context.intent.rawInput, input);
      expect(context.budget.responseReserveTokens, 1024);
    });

    test('should place bounded runtime HEAD ahead of baseline context', () {
      final context = buildContext(
        input: '艾琳现在怎么样？',
        sceneState: const SceneState(presentCharacterIds: ['eileen']),
        runtimeEntities: [
          RuntimeEntityState(
            entityType: RuntimeEntityType.character,
            entityId: 'eileen',
            lifecycleStatus: 'dead',
            overlay: const {'life_status': 'dead', 'affinity': 10},
          ),
        ],
      );
      final prompt =
          compiler.compile(runtimePolicy: 'runtime', context: context);

      expect(prompt.messages.first['content'], contains('当前持久状态（优先于初始设定）'));
      expect(prompt.messages.first['content'], contains('life_status=dead'));
      expect(
          context.trace.entries
              .where((entry) => entry.source == 'runtime_head'),
          isNotEmpty);
    });

    test('should bound runtime memory despite a large HEAD', () {
      final entities = List<RuntimeEntityState>.generate(
          1000,
          (index) => RuntimeEntityState(
                entityType: RuntimeEntityType.character,
                entityId: 'npc-$index',
                overlay: {'goal': '目标 $index ${'很长的状态 '.padRight(200, 'x')}'},
              ));
      final context = buildContext(
        input: 'npc-1 怎么了？',
        sceneState: const SceneState(presentCharacterIds: ['npc-1']),
        runtimeEntities: entities,
      );

      expect(context.runtime.memory, contains('npc-1'));
      expect(context.runtime.filteredEntityCount, greaterThan(900));
      expect(context.trace.totalEstimatedTokens,
          lessThanOrEqualTo(context.budget.inputLimitTokens));
    });

    test('should truncate historical summary before current user input', () {
      const input = '我现在去酒馆。';
      final summary = List.filled(5000, '过去的计划').join();
      final context = buildContext(input: input, summary: summary);
      final prompt = compiler.compile(
        runtimePolicy: 'runtime',
        context: context,
      );

      expect(context.historicalSummary!.length, lessThan(summary.length));
      expect(
        context.trace.entries
            .firstWhere((entry) => entry.source == 'historical_summary')
            .decision,
        'truncated',
      );
      expect(prompt.messages.last['content'], '【当前玩家意图】\n$input');
    });
  });

  group('SceneState', () {
    test('should serialize goal lifecycle without losing status', () {
      const state = SceneState(
        location: '酒馆',
        goals: [
          SceneGoal(
            id: 'palace',
            description: '前往王宫',
            status: SceneGoalStatus.cancelled,
          ),
          SceneGoal(id: 'tavern', description: '寻找酒馆'),
        ],
      );

      final restored = SceneState.decode(state.encode());

      expect(restored.location, '酒馆');
      expect(restored.goals.first.status, SceneGoalStatus.cancelled);
      expect(restored.activeGoals.single.description, '寻找酒馆');
    });

    test('tryDecode tolerates malformed persisted rows', () {
      expect(SceneState.tryDecode('{not json'), isNull);
      expect(SceneState.tryDecode('[1,2,3]'), isNull);

      // Non-list list fields must not throw; they fall back to defaults.
      final state = SceneState.tryDecode(
        '{"location":"白港","present_character_ids":"protagonist",'
        '"unresolved_events":{"a":1},"recent_changes":42}',
      );
      expect(state, isNotNull);
      expect(state!.location, '白港');
      expect(state.presentCharacterIds, ['protagonist']);
      expect(state.unresolvedEvents, isEmpty);
      expect(state.recentChanges, isEmpty);
    });
  });

  group('AdventureRuntimeStateResolver', () {
    test('overlays current character state without mutating the baseline', () {
      final baseline = AdventureConfig(
        supportingCharacters: [
          SupportingCharacter(id: 'eileen', name: '艾琳', affinity: 40),
        ],
      );
      final effective = const AdventureRuntimeStateResolver().effectiveConfig(
        baseline,
        [
          RuntimeEntityState(
            entityType: RuntimeEntityType.character,
            entityId: 'eileen',
            lifecycleStatus: 'dead',
            overlay: const {'affinity': 10, 'relationship': '敌人'},
          ),
        ],
      );

      expect(effective.supportingCharacters.single.isAlive, isFalse);
      expect(effective.supportingCharacters.single.affinity, 10);
      expect(effective.supportingCharacters.single.relation, '敌人');
      expect(baseline.supportingCharacters.single.isAlive, isTrue);
      expect(baseline.supportingCharacters.single.affinity, 40);
    });
  });

  group('RuntimeStateValidator', () {
    const validator = RuntimeStateValidator();

    test('filters invalid schema values but keeps valid persistent changes',
        () {
      final accepted = validator.accept(const [
        RuntimeStateChangeProposal(
          entityType: RuntimeEntityType.character,
          entityId: 'eileen',
          changeKind: RuntimeChangeKind.primary,
          operation: RuntimeChangeOperation.set,
          path: 'life_status',
          value: 'dead',
          reason: '明确死亡',
        ),
        RuntimeStateChangeProposal(
          entityType: RuntimeEntityType.character,
          entityId: 'eileen',
          changeKind: RuntimeChangeKind.primary,
          operation: RuntimeChangeOperation.set,
          path: 'lifecycle_status',
          value: 'not-a-status',
          reason: 'invalid',
        ),
      ]);
      expect(accepted, hasLength(1));
      expect(accepted.single.value, 'dead');
    });

    test('rejects a contradictory batch for one entity path', () {
      const change = RuntimeStateChangeProposal(
        entityType: RuntimeEntityType.character,
        entityId: 'eileen',
        changeKind: RuntimeChangeKind.primary,
        operation: RuntimeChangeOperation.set,
        path: 'life_status',
        value: 'dead',
        reason: 'test',
      );
      expect(
        () => validator.accept([change, change]),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
