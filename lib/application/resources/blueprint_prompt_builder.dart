import '../../domain/resources/resource_blueprint.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_limits.dart';
import 'resource_creation_contracts.dart';

/// Builder for unified, bounded planning prompts for [ResourceBlueprint].
///
/// Ensures consistent protocol across worldview, character and NPC,
/// enforces bounded reference context, and injects pre-allocated client IDs.
abstract final class BlueprintPromptBuilder {
  /// Maximum reference source character count included in the planning prompt.
  /// Longer references are safely truncated so prompt context stays bounded.
  static const int maxReferenceCharsInPrompt = 8000;

  /// Builds the system prompt for blueprint planning.
  static String buildSystemPrompt({
    required ResourceType resourceType,
    required BlueprintIdPool idPool,
    int? nominalBudget,
  }) {
    final budget = nominalBudget ??
        ResourceLimits.policyFor(resourceType).nominalCharacters;
    final typeName = switch (resourceType) {
      ResourceType.worldview => '世界观设定',
      ResourceType.character => '核心主角/主要角色卡',
      ResourceType.npc => '配角/NPC卡',
    };

    final sectionIdsFormatted = idPool.allowedSectionIds.join(', ');
    final partIdsFormatted = idPool.allowedPartIds.join(', ');

    return '''你是一个高级创意资源规划专家。你的任务是为【$typeName】生成结构化的【Resource Blueprint（大纲规划）】。

【极其重要的核心原则】
1. Blueprint 仅负责大纲规划与任务拆解，【严禁包含正文长文】！
2. 严禁在 generationGoal、summary、title 中输出任何小说正文、对话剧情或长篇设定细节。
3. 每个 Part 的 generationGoal 必须是简明扼要的"生成目标指令"（说明后续生成该小节时应涵盖哪些核心要素，1-3句话即可）。
4. 目录结构必须【自适应、动态产生】，严禁套用死板的九宫格、固定模块或固定表格。根据用户需求与参考资料，提炼出最合适的大纲结构。
5. 所有 Part 的 estimatedLength（预计字数）之和【绝对不能超过 $budget 字】！请合理分配每个 Part 的字数预算。

【ID 安全与预分配规则】
你【必须且只能】从以下预分配列表中按需取用 ID，严禁自行臆造或修改 ID 格式：
- 允许的 Section ID：$sectionIdsFormatted
- 允许的 Part ID：$partIdsFormatted
每个 Part 必须指明所属的 sectionId。
dependencies 是依赖的 Part ID 列表（表示必须先生成哪些 Part，才能生成本 Part），必须构成合法无环的有向无环图（DAG），严禁产生自依赖或循环依赖。

【输出格式】
必须直接返回纯合法 JSON 对象（不要包裹任何额外的说明文本，可以使用 json 代码块）：
{
  "suggestedName": "资源建议名称（不超过50字）",
  "summary": "资源简短规划摘要（不超过300字）",
  "sections": [
    {
      "id": "sec_1",
      "title": "章节标题",
      "summary": "本章节简述",
      "sortOrder": 0,
      "parts": [
        {
          "id": "part_1",
          "sectionId": "sec_1",
          "title": "小节标题",
          "generationGoal": "该小节的正文生成目标（1-3句话指导后续写作）",
          "estimatedLength": 600,
          "dependencies": [],
          "sortOrder": 0
        }
      ]
    }
  ]
}''';
  }

  /// Builds user instruction message for initial planning.
  static String buildUserInstruction({
    required String resourceName,
    required ResourceType resourceType,
    required ReferenceSource referenceSource,
    String intentSummary = '',
  }) {
    final buffer = StringBuffer();
    buffer.writeln('请为以下资源进行自适应大纲规划（Blueprint）：');
    buffer.writeln('- 资源名称/初步意向：${resourceName.trim()}');
    if (intentSummary.trim().isNotEmpty) {
      buffer.writeln('- 创作意图与概述：${intentSummary.trim()}');
    }

    if (referenceSource.hasBody) {
      buffer.writeln('\n【参考资料】');
      final body = referenceSource.body.trim();
      if (body.length <= maxReferenceCharsInPrompt) {
        buffer.writeln(body);
      } else {
        buffer.writeln(body.substring(0, maxReferenceCharsInPrompt));
        buffer.writeln(
          '\n[...参考资料内容较长（共 ${body.length} 字符），已截取前 $maxReferenceCharsInPrompt 字符供大纲规划使用...]',
        );
      }
    }

    buffer.writeln('\n请根据上述需求，生成结构清晰、适合该资源特点、依赖清晰的动态 Section 与 Part 规划 JSON。');
    return buffer.toString();
  }

  /// Builds user instruction message for replanning with previous context & user feedback.
  static String buildReplanInstruction({
    required ResourceBlueprint previousBlueprint,
    required String userFeedback,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('用户希望对现有的 Blueprint 大纲进行重新规划与调整。');
    buffer.writeln('\n【上一个版本的大纲概览 (Revision ${previousBlueprint.revision})】');
    buffer.writeln('- 当前名称：${previousBlueprint.suggestedName}');
    buffer.writeln('- 当前摘要：${previousBlueprint.summary}');
    buffer.writeln('- 当前章节结构：');
    for (final sec in previousBlueprint.sections) {
      buffer.writeln('  * [${sec.id}] ${sec.title}:');
      for (final p in sec.parts) {
        buffer.writeln(
            '    - [${p.id}] ${p.title} (目标: ${p.generationGoal}, 预算: ${p.estimatedLength}字, 依赖: ${p.dependencies})');
      }
    }

    buffer.writeln('\n【用户的修改意见与反馈】');
    buffer.writeln(
        userFeedback.trim().isEmpty ? '请优化大纲结构与内容分布。' : userFeedback.trim());

    buffer.writeln('\n请根据修改意见重新生成完整的 Blueprint JSON。');
    return buffer.toString();
  }
}
