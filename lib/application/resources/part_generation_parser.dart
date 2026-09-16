import 'dart:convert';

import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_generation_protocol.dart';

/// Exception thrown when the LLM response cannot be parsed into a valid
/// Part Generation JSON payload.
class PartGenerationParseException implements Exception {
  const PartGenerationParseException(
    this.message, {
    this.rawResponse = '',
    this.field = '',
  });

  final String message;
  final String rawResponse;
  final String field;

  @override
  String toString() => 'PartGenerationParseException: $message'
      '${field.isNotEmpty ? ' [field: $field]' : ''}';
}

/// Parser for the Incremental JSON Protocol responses.
abstract final class PartGenerationParser {
  /// Allowed fields for single Part generation responses.
  /// Any key outside this allowlist (e.g. "parts", "sections", "chapters")
  /// will be rejected immediately to protect against structural payload attacks.
  static const Set<String> _allowedKeys = {
    'protocol_version',
    'protocolVersion',
    'generation_id',
    'generationId',
    'resource_id',
    'resourceId',
    'section_id',
    'sectionId',
    'part_id',
    'partId',
    'attempt_id',
    'attemptId',
    'content',
    'summary',
    'status',
  };

  static const List<List<String>> _aliasPairs = [
    ['protocol_version', 'protocolVersion'],
    ['generation_id', 'generationId'],
    ['resource_id', 'resourceId'],
    ['section_id', 'sectionId'],
    ['part_id', 'partId'],
    ['attempt_id', 'attemptId'],
  ];

  /// Parses a raw string from LLM completion into a [PartGenerationResponse].
  static PartGenerationResponse parse(String rawResponse) {
    final trimmed = rawResponse.trim();
    if (trimmed.isEmpty) {
      throw const PartGenerationParseException(
        'LLM 返回内容为空，无法解析 Part 正文',
        rawResponse: '',
      );
    }

    final jsonStr = _extractJsonPayload(trimmed);
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonStr);
    } catch (e) {
      throw PartGenerationParseException(
        'JSON 格式解析失败: $e',
        rawResponse: rawResponse,
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw PartGenerationParseException(
        'Part 生成响应顶层必须为 JSON 对象 (Map)，实际为 ${decoded.runtimeType}',
        rawResponse: rawResponse,
      );
    }

    // 1. Strict allowlist guard: Reject unauthorized structural or injected keys
    for (final key in decoded.keys) {
      if (!_allowedKeys.contains(key)) {
        throw PartGenerationParseException(
          '未知或未经授权的字段: "$key"，正文生成禁止携带结构树或额外字段',
          field: key,
          rawResponse: rawResponse,
        );
      }
    }

    // 2. Reject duplicate snake_case and camelCase semantic fields
    for (final pair in _aliasPairs) {
      if (decoded.containsKey(pair[0]) && decoded.containsKey(pair[1])) {
        throw PartGenerationParseException(
          '同时包含了重复的 snake_case 与 camelCase 语义字段: "${pair[0]}" 与 "${pair[1]}"',
          field: pair[0],
          rawResponse: rawResponse,
        );
      }
    }

    // 3. Strict canonical wire typing for protocol_version
    final protocolVersionRaw =
        decoded['protocol_version'] ?? decoded['protocolVersion'];
    if (protocolVersionRaw == null) {
      throw PartGenerationParseException(
        '缺失协议版本字段 (protocol_version)',
        rawResponse: rawResponse,
        field: 'protocol_version',
      );
    }
    if (protocolVersionRaw is! int) {
      throw PartGenerationParseException(
        '协议版本字段 (protocol_version) 必须为标准整数 (int)，实际为: ${protocolVersionRaw.runtimeType}',
        rawResponse: rawResponse,
        field: 'protocol_version',
      );
    }
    if (protocolVersionRaw != 1) {
      throw PartGenerationParseException(
        '不支持的协议版本: $protocolVersionRaw (仅支持 1)',
        rawResponse: rawResponse,
        field: 'protocol_version',
      );
    }
    final int protocolVersion = protocolVersionRaw;

    final generationId =
        (decoded['generation_id'] ?? decoded['generationId'])?.toString() ?? '';
    if (generationId.isEmpty) {
      throw PartGenerationParseException(
        '缺失或空的 generation_id',
        rawResponse: rawResponse,
        field: 'generation_id',
      );
    }

    final resourceIdStr =
        (decoded['resource_id'] ?? decoded['resourceId'])?.toString() ?? '';
    if (resourceIdStr.isEmpty) {
      throw PartGenerationParseException(
        '缺失或空的 resource_id',
        rawResponse: rawResponse,
        field: 'resource_id',
      );
    }

    final sectionIdStr =
        (decoded['section_id'] ?? decoded['sectionId'])?.toString() ?? '';
    if (sectionIdStr.isEmpty) {
      throw PartGenerationParseException(
        '缺失或空的 section_id',
        rawResponse: rawResponse,
        field: 'section_id',
      );
    }

    final partIdStr =
        (decoded['part_id'] ?? decoded['partId'])?.toString() ?? '';
    if (partIdStr.isEmpty) {
      throw PartGenerationParseException(
        '缺失或空的 part_id',
        rawResponse: rawResponse,
        field: 'part_id',
      );
    }

    final attemptId =
        (decoded['attempt_id'] ?? decoded['attemptId'])?.toString() ?? '';
    if (attemptId.isEmpty) {
      throw PartGenerationParseException(
        '缺失或空的 attempt_id',
        rawResponse: rawResponse,
        field: 'attempt_id',
      );
    }

    final dynamic contentRaw = decoded['content'];
    if (contentRaw == null) {
      throw PartGenerationParseException(
        '缺失正文字段 (content)',
        rawResponse: rawResponse,
        field: 'content',
      );
    }
    final content = contentRaw.toString();

    final summary = decoded['summary']?.toString() ?? '';
    final status = decoded['status']?.toString() ?? 'completed';

    return PartGenerationResponse(
      protocolVersion: protocolVersion,
      generationId: generationId,
      resourceId: ResourceId(resourceIdStr),
      sectionId: SectionId(sectionIdStr),
      partId: PartId(partIdStr),
      attemptId: attemptId,
      content: content,
      summary: summary,
      status: status,
    );
  }

  /// Extracts the single JSON object, rejecting ambiguous prose containing multiple objects.
  static String _extractJsonPayload(String raw) {
    var text = raw.trim();

    // Check for markdown code blocks
    if (text.startsWith('```')) {
      final firstNewline = text.indexOf('\n');
      if (firstNewline != -1) {
        text = text.substring(firstNewline + 1);
      }
      if (text.endsWith('```')) {
        text = text.substring(0, text.length - 3).trim();
      }
    }

    final firstBrace = text.indexOf('{');
    if (firstBrace == -1) {
      throw PartGenerationParseException(
        '未在 LLM 响应中找到 JSON 起始大括号',
        rawResponse: raw,
      );
    }

    // Find the closing brace that balances firstBrace
    var depth = 0;
    var closingBrace = -1;
    var inString = false;
    var isEscaped = false;

    for (var i = firstBrace; i < text.length; i++) {
      final char = text[i];
      if (isEscaped) {
        isEscaped = false;
        continue;
      }
      if (char == '\\') {
        isEscaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (!inString) {
        if (char == '{') {
          depth++;
        } else if (char == '}') {
          depth--;
          if (depth == 0) {
            closingBrace = i;
            break;
          }
        }
      }
    }

    if (closingBrace == -1) {
      throw PartGenerationParseException(
        'JSON 对象结构不完整，未正确闭合',
        rawResponse: raw,
      );
    }

    // Check if there is another JSON object preceding firstBrace or trailing closingBrace
    final preceding = text.substring(0, firstBrace);
    if (preceding.contains('{')) {
      throw PartGenerationParseException(
        '响应中包含多个独立的 JSON 对象，存在歧义',
        rawResponse: raw,
      );
    }

    final remaining = text.substring(closingBrace + 1);
    if (remaining.contains('{')) {
      throw PartGenerationParseException(
        '响应中包含多个独立的 JSON 对象，存在歧义',
        rawResponse: raw,
      );
    }

    return text.substring(firstBrace, closingBrace + 1);
  }
}
