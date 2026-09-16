import '../../domain/resources/resource_generation_protocol.dart';

/// Prompt builder for Part generation requests following the Incremental JSON Protocol.
abstract final class PartGenerationPromptBuilder {
  /// Builds the system prompt enforcing the JSON protocol and boundaries.
  static String buildSystemPrompt(PartGenerationRequest request) {
    return '''你是一个专业的 RPG/跑团内容作家与设定规划专家。
你的任务是为当前资源的指定 Part 生成正文内容（Markdown 格式的正文 prose）。

【协议规范与严格限制】
1. 你必须仅输出一个合法的 JSON 对象，不要包含任何前导或尾随说明文字。
2. 必须包含且严格保持以下字段的值与请求一致：
   - "protocol_version": 1
   - "generation_id": "${request.generationId}"
   - "resource_id": "${request.resourceId.value}"
   - "section_id": "${request.sectionId.value}"
   - "part_id": "${request.partId.value}"
   - "attempt_id": "${request.attemptId}"
   - "content": "在此处填写生成的详细正文 Markdown 文本"
   - "summary": "对此段内容的简短摘要（1-2句话）"
   - "status": "completed"
3. 严禁生成任何其他章节（sections）或部件（parts），严禁篡改 ID，严禁输出未经授权的额外层级。
4. 正文字数应紧扣目标预算（约 ${request.targetBudget} 字），内容必须翔实、生动、符合上下文设定。''';
  }

  /// Builds the user instruction prompt with contextual dependencies and bounds.
  static String buildInstruction(PartGenerationRequest request) {
    final ctx = request.context;
    final buffer = StringBuffer();

    buffer.writeln('【资源背景】');
    buffer.writeln('资源名称：${ctx.resourceName}');
    buffer.writeln('资源类型：${ctx.resourceType.storageValue}');
    if (ctx.resourceSummary.trim().isNotEmpty) {
      buffer.writeln('总体概述：${ctx.resourceSummary.trim()}');
    }
    buffer.writeln();

    buffer.writeln('【当前章节】');
    buffer.writeln('章节标题：${ctx.sectionTitle}');
    if (ctx.sectionSummary.trim().isNotEmpty) {
      buffer.writeln('章节作用：${ctx.sectionSummary.trim()}');
    }
    buffer.writeln();

    buffer.writeln('【待生成部件】');
    buffer.writeln('Part ID：${request.partId.value}');
    buffer.writeln('部件标题：${ctx.partTitle}');
    buffer.writeln('生成目标：${request.promptGoal}');
    buffer.writeln('目标字数：约 ${request.targetBudget} 字');
    buffer.writeln();

    if (ctx.dependencySummaries.isNotEmpty) {
      buffer.writeln('【前置依赖内容上下文】');
      for (final dep in ctx.dependencySummaries) {
        buffer.writeln('--- 前置部件 [${dep.partId.value}]: ${dep.title} ---');
        // Bounded excerpt to avoid token overflow
        final excerpt = dep.contentSummary.trim();
        if (excerpt.length > 1500) {
          buffer.writeln('${excerpt.substring(0, 1500)}...（已截断）');
        } else {
          buffer.writeln(excerpt);
        }
      }
      buffer.writeln();
    }

    if (ctx.referenceExcerpt.trim().isNotEmpty) {
      buffer.writeln('【参考材料节选】');
      final ref = ctx.referenceExcerpt.trim();
      if (ref.length > 2000) {
        buffer.writeln('${ref.substring(0, 2000)}...（已截断）');
      } else {
        buffer.writeln(ref);
      }
      buffer.writeln();
    }

    buffer.writeln('请按照协议规范，以 JSON 格式生成该 Part 的完整正文。');
    return buffer.toString();
  }
}
