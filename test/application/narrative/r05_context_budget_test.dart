import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/narrative/narrative_context.dart';
import 'package:lt_dialogue/application/narrative/prompt_compiler.dart';
import 'package:lt_dialogue/models/adventure_config.dart';

import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/model_context_capability.dart';
import 'package:lt_dialogue/models/scene_state.dart';
import 'package:lt_dialogue/models/world_entry.dart';
import 'package:lt_dialogue/services/worldview_prompt_budget.dart';
import 'package:lt_dialogue/utils/token_estimator.dart';

void main() {
  const capability = ModelContextCapability(
    providerId: 'test',
    modelId: 'test',
    maximumContextTokens: 8192,
    maximumOutputTokens: 2048,
  );
  const orchestrator = ContextOrchestrator();
  const compiler = PromptCompiler();

  NarrativeContext buildContext({
    required String input,
    List<WorldEntry> entries = const [],
    List<Message> messages = const [],
    String? summary,
    AdventureConfig? config,
    SceneState sceneState = const SceneState(location: '白港'),
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
      runtimePolicyTokens: 96,
      runtimeRevision: 0,
      runtimeEntities: const [],
      archiveRetrievalFacts: const [],
    );
  }

  int worldTokensOf(NarrativeContext context) =>
      context.world.all.fold<int>(0, (sum, item) => sum + item.estimatedTokens);

  int promptTokensOf(NarrativeContext context) => compiler
      .compile(runtimePolicy: '输出叙事。', context: context)
      .messages
      .fold<int>(
        0,
        (sum, message) => sum + TokenEstimator(message['content'] ?? '').tokens,
      );

  // Detailed worldview text that satisfies every integrity module.
  String hugeWorldviewBody(String seed, {int repeats = 400}) =>
      List.filled(repeats, '【世界观/世界规则】$seed 的铁律不可违背。').join('\n');

  test('C1 a huge worldview still respects the total budget', () {
    final entries = <WorldEntry>[
      for (var i = 0; i < 30; i++)
        WorldEntry(
          id: i + 1,
          content: hugeWorldviewBody('规则$i'),
          keys: const ['白港'],
          sticky: 1,
          sourceType: 'worldview_snapshot',
        ),
    ];
    final context = buildContext(input: '我观察四周。', entries: entries);
    final budget = ContextBudget.resolve(
      capability: capability,
      requestedResponseTokens: 1024,
    );

    expect(worldTokensOf(context), lessThanOrEqualTo(4096));
    expect(promptTokensOf(context), lessThanOrEqualTo(budget.inputLimitTokens));
  });

  test('C2 huge character cards respect the budget', () {
    final hugePersonality = '极度谨慎，' * 2000;
    final config = AdventureConfig(
      name: '主角',
      selectedCharacters: [
        AdventureSelectedCharacter(
          id: 'c1',
          characterId: 'c1',
          characterName: '巨卡角色',
          isProtagonist: false,
          characterCardJson: {
            'personality': hugePersonality,
            'world_profile': {
              'public_goal': '守护白港，' * 2000,
            },
          },
        ),
      ],
    );
    final context = buildContext(
      input: '我走向巨卡角色。',
      sceneState: const SceneState(
        location: '白港',
        presentCharacterIds: ['protagonist', 'c1'],
      ),
      config: config,
    );
    final budget = ContextBudget.resolve(
      capability: capability,
      requestedResponseTokens: 1024,
    );

    expect(
      TokenEstimator(context.characterContext).tokens,
      lessThanOrEqualTo(2048),
    );
    expect(promptTokensOf(context), lessThanOrEqualTo(budget.inputLimitTokens));
  });

  test('C3 huge history respects the budget', () {
    final messages = <Message>[
      for (var i = 0; i < 60; i++)
        Message(
          id: 'm\$i',
          content: '历史消息$i：' '很长的战斗描述。' * 200,
          isUser: i.isEven,
        ),
    ];
    final context = buildContext(input: '我继续前进。', messages: messages);
    final budget = ContextBudget.resolve(
      capability: capability,
      requestedResponseTokens: 1024,
    );

    expect(promptTokensOf(context), lessThanOrEqualTo(budget.inputLimitTokens));
  });

  test('C4 the current turn never silently disappears under budget pressure',
      () {
    final messages = <Message>[
      for (var i = 0; i < 60; i++)
        Message(
          id: 'm\$i',
          content: '历史消息$i：' '很长的战斗描述。' * 300,
          isUser: i.isEven,
        ),
    ];
    final context = buildContext(
      input: '这条命令必须完整保留在提示词末尾。',
      messages: messages,
    );
    final prompt = compiler.compile(runtimePolicy: '输出叙事。', context: context);

    expect(
      prompt.messages.last['content'],
      endsWith('这条命令必须完整保留在提示词末尾。'),
    );
  });

  test('C5 a duplicated source identity appears once', () {
    final entry = WorldEntry(
      id: 1,
      content: '白港的灯塔由古代石匠建造，至今仍在运转。',
      keys: const ['白港'],
      sticky: 1,
      sourceType: 'worldview_snapshot',
    );
    final context = buildContext(input: '白港发生了什么？', entries: [
      entry,
      WorldEntry(
        id: 2,
        content: entry.content,
        keys: entry.keys,
        sticky: entry.sticky,
        sourceType: entry.sourceType,
      ),
    ]);

    final includedContents = context.world.all
        .map((item) => item.content)
        .where((content) => content.contains('灯塔'));
    expect(includedContents, hasLength(1));
    expect(context.world.filteredEntryReasons[2], 'duplicate');
  });

  test('C6 repeated assemblies produce a stable selection and ordering', () {
    final entries = <WorldEntry>[
      for (var i = 0; i < 20; i++)
        WorldEntry(
          id: i + 1,
          content: '白港条目$i：平衡分数的内容，用于验证平局排序。',
          keys: const ['白港'],
          sticky: 0,
          sourceType: 'worldview_snapshot',
        ),
    ];
    final first = buildContext(input: '白港。', entries: entries);
    final second = buildContext(input: '白港。', entries: entries);

    expect(
      second.world.all.map((item) => item.entryId).toList(),
      first.world.all.map((item) => item.entryId).toList(),
    );
  });

  test('C7 constraint entries cannot bypass the budget', () {
    final entries = <WorldEntry>[
      for (var i = 0; i < 30; i++)
        WorldEntry(
          id: i + 1,
          // All classified as constraints via the 世界规则 marker.
          content: '【世界观/世界规则】第$i条：${'必须遵守的规则。' * 200}',
          keys: const ['白港'],
          sticky: 1,
          sourceType: 'rule',
        ),
    ];
    final context = buildContext(input: '我观察四周。', entries: entries);
    final budget = ContextBudget.resolve(
      capability: capability,
      requestedResponseTokens: 1024,
    );

    expect(
      worldTokensOf(context),
      lessThanOrEqualTo(4096),
      reason: 'constraints must compete inside the same hard budget',
    );
    expect(
      context.world.filteredEntryReasons.values,
      contains('token_budget'),
    );
    expect(promptTokensOf(context), lessThanOrEqualTo(budget.inputLimitTokens));
  });

  test('C8 estimator consistency on Chinese and mixed text', () {
    final chinese = TokenEstimator('这是一段中文文本，用于验证估算。').tokens;
    final ascii = TokenEstimator('this is an ascii sentence.').tokens;
    // Chinese characters are denser per token than ASCII letters.
    expect(chinese, lessThan(TokenEstimator('x' * 200).tokens));
    expect(ascii, greaterThan(0));

    // Deterministic and consistent between calls.
    expect(TokenEstimator('中文与English混合 🎲').tokens,
        TokenEstimator('中文与English混合 🎲').tokens);

    // Truncation respects the budget and never splits a surrogate pair.
    final emoji = '🎲百面骰' * 500;
    final truncated = truncateToTokens(emoji, 100);
    expect(TokenEstimator(truncated).tokens, lessThanOrEqualTo(100));
    final lastCode = truncated.codeUnitAt(truncated.length - 1);
    expect(lastCode < 0xD800 || lastCode > 0xDBFF, isTrue,
        reason: 'truncation must not end with a lone lead surrogate');
  });

  test('C9 estimator consistency on extended Unicode and empty text', () {
    expect(TokenEstimator('').tokens, 0);
    expect(truncateToTokens('', 100), '');
    expect(truncateToTokens('任意文本', 0), '');

    const extendedUnicode = 'ΩΩ½⅓ двойной кастинг ทดสอบ 🧝‍♀️🗡️';
    final bounded =
        WorldviewPromptBudget.bound(extendedUnicode, maximumTokens: 8);
    expect(TokenEstimator(bounded).tokens, lessThanOrEqualTo(8));
  });

  test('C10 worldview budget trims by line boundary, not arbitrary substring',
      () {
    final lines = List.generate(200, (i) => '第$i行：世界观铁律内容，足够长以产生预算压力。');
    final source = lines.join('\n');

    final bounded = WorldviewPromptBudget.bound(source, maximumTokens: 200);

    expect(TokenEstimator(bounded).tokens, lessThanOrEqualTo(200));
    final outLines = bounded.split('\n');
    for (final line in outLines) {
      // Every output line must be a whole input line (or a truncated prefix
      // of exactly one input line, only allowed for the final one).
      final exact = lines.contains(line);
      final prefixOfOne = lines.any((candidate) =>
          candidate.startsWith(line) && candidate.length > line.length);
      expect(exact || prefixOfOne, isTrue,
          reason: 'line "$line" was cut '
              'outside a line boundary');
    }
    // Deterministic.
    expect(
      WorldviewPromptBudget.bound(source, maximumTokens: 200),
      bounded,
    );
  });

  test('C11 production assembler keeps the estimated input inside the budget',
      () {
    final entries = <WorldEntry>[
      for (var i = 0; i < 40; i++)
        WorldEntry(
          id: i + 1,
          content: '【世界观/世界规则】白港规则$i：${'细节描述。' * 120}',
          keys: const ['白港'],
          sticky: 1,
          sourceType: 'rule',
        ),
    ];
    final messages = <Message>[
      for (var i = 0; i < 40; i++)
        Message(
          id: 'm\$i',
          content: '历史$i：' '漫长的冒险经历。' * 100,
          isUser: i.isEven,
        ),
    ];
    final config = AdventureConfig(
      name: '主角',
      selectedCharacters: [
        AdventureSelectedCharacter(
          id: 'cx',
          characterId: 'cx',
          characterName: '超长角色卡',
          isProtagonist: false,
          characterCardJson: {
            'personality': '复杂性格，' * 1500,
          },
        ),
      ],
    );
    final context = buildContext(
      input: '我该怎么办？',
      entries: entries,
      messages: messages,
      summary: '此前的摘要内容。' * 500,
      sceneState: const SceneState(
        location: '白港',
        presentCharacterIds: ['protagonist', 'cx'],
      ),
      config: config,
    );
    final budget = ContextBudget.resolve(
      capability: capability,
      requestedResponseTokens: 1024,
    );

    expect(
      promptTokensOf(context),
      lessThanOrEqualTo(budget.inputLimitTokens),
      reason: 'assembled input must stay within the configured hard budget',
    );
  });
}
