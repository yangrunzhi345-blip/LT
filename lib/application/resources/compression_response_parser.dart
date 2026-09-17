import 'dart:convert';

import '../../domain/resources/resource_compression.dart';
import '../../domain/resources/resource_limits.dart';

/// Raised when a compression response is not exactly the agreed shape.
class CompressionParseException implements Exception {
  const CompressionParseException(this.message);

  final String message;

  @override
  String toString() => 'CompressionParseException: $message';
}

/// The validated content of one compression response.
final class CompressionParseResult {
  const CompressionParseResult({
    required this.compressedContent,
    required this.retention,
  });

  final String compressedContent;
  final CompressionRetention retention;
}

/// Strict parser for the compression response protocol.
///
/// The protocol is deliberately small: one JSON object, three known keys, and
/// a bounded length. Anything else is rejected before it can reach storage, so
/// a model that answers with prose, a giant blob or an unknown structure can
/// never become a candidate.
abstract final class CompressionResponseParser {
  static const int protocolVersion = 1;

  /// Maximum declared retention entries across all three lists.
  static const int maxRetentionEntries = 200;

  static const Set<String> allowedTopLevelKeys = <String>{
    'protocol_version',
    'compressed_content',
    'retained',
  };

  static const Set<String> allowedRetentionKeys = <String>{
    'entities',
    'relationships',
    'timeline',
  };

  static CompressionParseResult parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const CompressionParseException('压缩响应为空');
    }

    final jsonText = _stripOptionalFence(trimmed);
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (error) {
      throw CompressionParseException('压缩响应不是合法 JSON：${error.message}');
    }
    if (decoded is! Map) {
      throw const CompressionParseException('压缩响应必须是单个 JSON 对象');
    }

    final map = decoded.cast<String, Object?>();
    final unknown =
        map.keys.where((key) => !allowedTopLevelKeys.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw CompressionParseException('压缩响应包含未授权字段：${unknown.join('、')}');
    }

    final version = map['protocol_version'];
    if (version is! int || version != protocolVersion) {
      throw CompressionParseException(
        '压缩响应 protocol_version 必须为 $protocolVersion，实际为 $version',
      );
    }

    final content = map['compressed_content'];
    if (content is! String || content.trim().isEmpty) {
      throw const CompressionParseException('压缩响应缺少非空 compressed_content');
    }
    if (content.length > ResourceLimits.maxCompressionOutputCharacters) {
      throw CompressionParseException(
        '压缩响应正文超过上限（${content.length} > '
        '${ResourceLimits.maxCompressionOutputCharacters} 字）',
      );
    }

    final retention = _parseRetention(map['retained']);
    return CompressionParseResult(
      compressedContent: content,
      retention: retention,
    );
  }

  /// Strips one optional ```/```json fence around the payload.
  ///
  /// Models frequently wrap JSON in a fence even when told not to; unwrapping a
  /// single well-formed fence is safe because the body must still parse as one
  /// JSON object. Any other surrounding text still fails.
  static String _stripOptionalFence(String text) {
    if (!text.startsWith('```')) return text;
    final firstNewline = text.indexOf('\n');
    if (firstNewline < 0) return text;
    if (!text.endsWith('```')) return text;
    return text.substring(firstNewline + 1, text.length - 3).trim();
  }

  static CompressionRetention _parseRetention(Object? raw) {
    if (raw == null) return CompressionRetention.empty;
    if (raw is! Map) {
      throw const CompressionParseException('retained 必须是 JSON 对象');
    }
    final map = raw.cast<String, Object?>();
    final unknown =
        map.keys.where((key) => !allowedRetentionKeys.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw CompressionParseException('retained 包含未授权字段：${unknown.join('、')}');
    }

    final entities = _parseStringList(map['entities'], 'entities');
    final relationships =
        _parseStringList(map['relationships'], 'relationships');
    final timeline = _parseStringList(map['timeline'], 'timeline');

    final total = entities.length + relationships.length + timeline.length;
    if (total > maxRetentionEntries) {
      throw CompressionParseException(
        'retained 条目过多（$total > $maxRetentionEntries）',
      );
    }

    return CompressionRetention(
      entities: entities,
      relationships: relationships,
      timeline: timeline,
    );
  }

  static List<String> _parseStringList(Object? raw, String field) {
    if (raw == null) return const <String>[];
    if (raw is! List) {
      throw CompressionParseException('retained.$field 必须是数组');
    }
    final values = <String>[];
    for (final item in raw) {
      if (item is! String) {
        throw CompressionParseException('retained.$field 只能包含字符串');
      }
      final trimmed = item.trim();
      if (trimmed.isEmpty) continue;
      values.add(trimmed);
    }
    return values;
  }
}
