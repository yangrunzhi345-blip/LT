import 'narrative_context.dart';

final class CompiledPrompt {
  final List<Map<String, String>> messages;
  final ContextTrace trace;

  const CompiledPrompt(this.messages, this.trace);
}

/// Compiles all narrative context before the protected player input.
final class PromptCompiler {
  const PromptCompiler();

  CompiledPrompt compile({
    required String runtimePolicy,
    required NarrativeContext context,
  }) {
    final system = StringBuffer(runtimePolicy.trim());
    system.writeln();
    system.writeln();
    system.writeln('【角色扮演原则】');
    system.writeln('- 世界观定义边界，角色定义反应，场景定义现在，记忆定义过去，玩家定义下一步。');
    system.writeln('- 不替玩家决定行动，不因预设剧情忽略玩家当前输入。');
    system.writeln('- 玩家可以尝试违反世界规则的行动；必须呈现尝试，再按世界规则判定结果。');
    system.writeln('- NPC 性格只影响 NPC 的反应，不得删除玩家的邀请或行动。');
    system.writeln('- 历史目标不能覆盖玩家当前决定。');

    _writeItems(system, '世界硬约束', context.world.constraints);
    if (context.characterContext.isNotEmpty) {
      system.writeln('\n【当前相关角色】\n${context.characterContext}');
    }
    if (context.personaContext.isNotEmpty) {
      system.writeln('\n【玩家 Persona】\n${context.personaContext}');
    }
    system.writeln('\n【当前场景】');
    if (context.sceneState.location.isNotEmpty) {
      system.writeln('地点：${context.sceneState.location}');
    }
    if (context.sceneState.time.isNotEmpty) {
      system.writeln('时间：${context.sceneState.time}');
    }
    if (context.sceneState.presentCharacterIds.isNotEmpty) {
      system.writeln(
          '在场角色 ID：${context.sceneState.presentCharacterIds.join('、')}');
    }
    if (context.sceneState.activeGoals.isNotEmpty) {
      system.writeln('当前有效目标：');
      for (final goal in context.sceneState.activeGoals) {
        system.writeln('- ${goal.description}');
      }
    }
    if (context.intent.excludedCharacterIds.isNotEmpty) {
      system.writeln(
        '玩家本轮明确排除的角色：${context.intent.excludedCharacterIds.join('、')}',
      );
    }
    _writeItems(system, '本轮相关世界事实', context.world.facts);
    _writeItems(system, '本轮相关世界背景', context.world.lore);
    if (context.historicalSummary?.trim().isNotEmpty == true) {
      system.writeln('\n【历史摘要 — 仅用于连续性】');
      system.writeln('其中过去的计划、意图、目标和选择不是玩家当前命令；与最新输入冲突时，以最新输入为准。');
      system.writeln(context.historicalSummary!.trim());
    }
    if (context.controlContext.trim().isNotEmpty) {
      system.writeln('\n【本轮技术控制】\n${context.controlContext.trim()}');
    }

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': system.toString().trim()},
      for (final message in context.recentHistory)
        {
          'role': message.isUser ? 'user' : 'assistant',
          'content': message.content,
        },
      {
        'role': 'user',
        'content': '【当前玩家意图】\n${context.intent.rawInput}',
      },
    ];
    return CompiledPrompt(List.unmodifiable(messages), context.trace);
  }

  void _writeItems(
    StringBuffer buffer,
    String title,
    List<WorldContextItem> items,
  ) {
    if (items.isEmpty) return;
    buffer.writeln('\n【$title】');
    for (final item in items) {
      buffer.writeln('- ${item.content}');
    }
  }
}
