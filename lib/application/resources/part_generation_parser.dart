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

    // Extract fields, supporting snake_case (canonical protocol) and camelCase
    final protocolVersionRaw =
        decoded['protocol_version'] ?? decoded['protocolVersion'];
    if (protocolVersionRaw == null) {
      throw PartGenerationParseException(
        '缺失协议版本字段 (protocol_version)',
        rawResponse: rawResponse,
        field: 'protocol_version',
      );
    }
    final int protocolVersion;
    if (protocolVersionRaw is int) {
      protocolVersion = protocolVersionRaw;
    } else if (protocolVersionRaw is num) {
      protocolVersion = protocolVersionRaw.toInt();
    } else if (protocolVersionRaw is String) {
      final parsed = int.tryParse(protocolVersionRaw);
      if (parsed == null) {
        throw PartGenerationParseException(
          '协议版本字段 (protocol_version) 格式无效: $protocolVersionRaw',
          rawResponse: rawResponse,
          field: 'protocol_version',
        );
      }
      protocolVersion = parsed;
    } else {
      throw PartGenerationParseException(
        '协议版本字段 (protocol_version) 类型无效: ${protocolVersionRaw.runtimeType}',
        rawResponse: rawResponse,
        field: 'protocol_version',
      );
    }

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

  /// Extracts the outermost JSON object substring, ignoring markdown blocks
  /// or preamble/postamble chatter.
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
    final lastBrace = text.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
      return text.substring(firstBrace, lastBrace + 1).trim();
    }

    return text;
  }
}
