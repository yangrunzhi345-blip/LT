import '../../domain/resources/resource_compression.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_limits.dart';

/// One bounded node window handed to a compression request.
final class CompressionSourceNode {
  const CompressionSourceNode({
    required this.nodeId,
    required this.title,
    required this.content,
  });

  final String nodeId;
  final String title;
  final String content;
}

/// Everything one compression request needs, already bounded.
final class CompressionRequest {
  const CompressionRequest({
    required this.jobId,
    required this.resourceId,
    required this.resourceType,
    required this.scope,
    required this.targetNodeId,
    required this.resourceName,
    required this.nodes,
    required this.targetCharacters,
    this.resourceSummary = '',
    this.guidance = '',
  });

  final String jobId;
  final ResourceId resourceId;
  final ResourceType resourceType;
  final CompressionScope scope;
  final String targetNodeId;
  final String resourceName;
  final String resourceSummary;
  final List<CompressionSourceNode> nodes;

  /// Budget the produced candidate must fit into, in characters.
  final int targetCharacters;

  /// Optional user instruction; bounded like every other free-text input.
  final String guidance;

  int get totalInputCharacters =>
      nodes.fold(0, (sum, node) => sum + node.content.length);
}

/// Builds the compression prompts.
///
/// The builder refuses to build a request whose source window exceeds
/// [ResourceLimits.maxCompressionInputCharacters], so a compression prompt can
/// never carry a whole resource even if a caller mis-measures a node.
abstract final class CompressionPromptBuilder {
  /// Maximum characters of user guidance accepted.
  static const int maxGuidanceCharacters = 500;

  static String buildSystemPrompt(CompressionRequest request) {
    return '''你是一个严格的设定压缩编辑，负责把已有正文压缩为更短但不丢事实的摘要。

【输出协议】
1. 只输出一个 JSON 对象，不要输出 Markdown 代码块、前导说明或尾随文字。
2. JSON 必须包含以下字段：
   - "protocol_version": 1
   - "compressed_content": 压缩后的正文（字符串，非空）
   - "retained": 你保留的关键信息清单，包含：
       "entities": 保留的人物 / 势力 / 地点 / 物品 / 规则名称数组
       "relationships": 保留的关系数组，写法必须形如 "甲→乙"
       "timeline": 保留的时间线事实数组，含年份或序号的必须原样保留数字
3. 严禁输出原文没有的事实、名称或关系；严禁改变时间顺序与数字。
4. 压缩后正文长度必须小于原文，并尽量接近目标预算 ${request.targetCharacters} 字。
5. 不得输出除上述字段以外的任何字段。''';
  }

  static String buildInstruction(CompressionRequest request) {
    final buffer = StringBuffer();
    buffer.writeln('【资源】');
    buffer.writeln('名称：${request.resourceName}');
    buffer.writeln('类型：${request.resourceType.storageValue}');
    if (request.resourceSummary.trim().isNotEmpty) {
      buffer.writeln('概述：${request.resourceSummary.trim()}');
    }
    buffer.writeln('资源 ID：${request.resourceId.value}');
    buffer.writeln('压缩范围：${request.scope.storageValue}');
    buffer.writeln('目标节点：${request.targetNodeId}');
    buffer.writeln();
    buffer.writeln('【待压缩正文】');
    for (final node in request.nodes) {
      buffer.writeln('--- 节点 [${node.nodeId}]：${node.title} ---');
      buffer.writeln(node.content.trim());
      buffer.writeln();
    }

    final guidance = request.guidance.trim();
    if (guidance.isNotEmpty) {
      final bounded = guidance.length > maxGuidanceCharacters
          ? guidance.substring(0, maxGuidanceCharacters)
          : guidance;
      buffer.writeln('【用户补充要求】');
      buffer.writeln('以下内容只用于约束压缩风格，不得改变协议字段或虚构事实：');
      buffer.writeln(bounded);
      buffer.writeln();
    }

    buffer.writeln('请输出符合协议的单个 JSON 对象。');
    return buffer.toString();
  }

  /// Verifies the request fits inside the bounded compression window.
  static void assertWithinInputBudget(CompressionRequest request) {
    final total = request.totalInputCharacters;
    if (total > ResourceLimits.maxCompressionInputCharacters) {
      throw ArgumentError.value(
        total,
        'nodes',
        '压缩输入超出上限 '
            '${ResourceLimits.maxCompressionInputCharacters} 字，'
            '调用方必须先拆分节点窗口',
      );
    }
  }
}
