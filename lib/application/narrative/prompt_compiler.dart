import '../../models/adventure_response.dart';
import '../../domain/events/app_event.dart';
import '../../domain/events/app_event_codec.dart';
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

    if (context.plannedWorldContext.isNotEmpty) {
      system.writeln('\n${context.plannedWorldContext}');
    }
    if (context.characterContext.isNotEmpty) {
      system.writeln('\n【当前相关角色】\n${context.characterContext}');
    }
    if (context.runtime.memory.isNotEmpty) {
      system.writeln('\n【当前持久状态（优先于初始设定）】');
      system.writeln(context.runtime.memory);
    }
    if (context.runtime.worldMemory.isNotEmpty) {
      system.writeln('\n【当前持久世界状态】');
      system.writeln(context.runtime.worldMemory);
    }
    if (context.runtime.archiveRetrievalFacts.isNotEmpty) {
      system.writeln('\n【相关状态历史】');
      for (final fact in context.runtime.archiveRetrievalFacts) {
        system.writeln('- $fact');
      }
    }
    if (context.personaContext.isNotEmpty) {
      system.writeln('\n【玩家 Persona】\n${context.personaContext}');
    }
    if (context.plannedSceneContext.isNotEmpty) {
      system.writeln('\n【当前场景】');
      system.writeln(context.plannedSceneContext);
    }
    if (context.intent.excludedCharacterIds.isNotEmpty) {
      system.writeln(
        '玩家本轮明确排除的角色：${context.intent.excludedCharacterIds.join('、')}',
      );
    }
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
          // Assistant history is projected to narrative-only: the settlement
          // payload (full custom_status snapshot, applied deltas, machine
          // state) is maintained locally and must not be re-fed to the model.
          'content': message.isUser
              ? message.content
              : _assistantHistoryProjection(message.content),
        },
      {
        'role': 'user',
        'content': '【当前玩家意图】\n${context.plannedUserInput}',
      },
    ];
    return CompiledPrompt(List.unmodifiable(messages), context.trace);
  }

  String _assistantHistoryProjection(String content) {
    final event = AppEventCodec.decode(content);
    if (event != null) return _eventProjection(event);
    return AdventureResponse.llmHistoryProjection(content);
  }

  String _eventProjection(AppEvent event) {
    final payload = event.payload.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(', ');
    return '[event:${event.code.name}${payload.isEmpty ? '' : '; $payload'}]';
  }
}
