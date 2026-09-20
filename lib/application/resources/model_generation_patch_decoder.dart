import 'dart:convert';

import '../../domain/resources/resource_generation_patch.dart';
import '../../domain/resources/resource_generation_protocol.dart';
import 'generation_patch_parser.dart';

/// Decodes model-authored Patch fields and binds the request-owned envelope.
///
/// The canonical parser remains the trust boundary for fully bound patches.
/// Legacy envelope fields are accepted only as assertions that exactly match
/// the active request; a model response can never select another generation,
/// resource, Part, or attempt.
final class ModelGenerationPatchDecoder {
  ModelGenerationPatchDecoder(this.request);

  final PartGenerationRequest request;
  int _lineNumber = 0;

  static const Set<String> _modelKeys = {
    'sequence',
    'op',
    'text_delta',
    'summary',
    'error_message',
    // A legacy cursor is an assertion checked by the accumulator. It is never
    // used as the application's authoritative position.
    'cursor',
  };

  static const Set<String> _immutableEnvelopeKeys = {
    'protocol_version',
    'generation_id',
    'resource_id',
    'section_id',
    'part_id',
    'attempt_id',
  };

  /// Decodes one model NDJSON line into a canonical Patch.
  ResourceGenerationPatch decodeLine(String line) {
    _lineNumber++;
    try {
      return _decodeLine(line);
    } on GenerationPatchParseException catch (error) {
      throw GenerationPatchParseException(
        '模型 Patch #$_lineNumber 校验失败；${error.message}',
        field: error.field,
        // Model prose can contain private user data. Keep only its JSON shape
        // in diagnostics rather than retaining the complete raw line.
        rawLine: _safeShape(line),
      );
    }
  }

  ResourceGenerationPatch _decodeLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      throw const GenerationPatchParseException('Patch 行内容为空', rawLine: '');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (error) {
      throw GenerationPatchParseException(
        'Patch JSON 解析失败: $error',
        rawLine: trimmed,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw GenerationPatchParseException(
        'Patch 顶层必须为 JSON 对象 (Map)，实际为: ${decoded.runtimeType}',
        rawLine: trimmed,
      );
    }

    for (final key in decoded.keys) {
      if (!_modelKeys.contains(key) && !_immutableEnvelopeKeys.contains(key)) {
        throw GenerationPatchParseException(
          '未知或非法的模型 Patch 字段: "$key"',
          field: key,
          rawLine: trimmed,
        );
      }
    }

    _assertLegacyEnvelope(decoded, rawLine: trimmed);
    return GenerationPatchParser.parsePatchMap(
      {
        ...decoded,
        'protocol_version': request.protocolVersion,
        'generation_id': request.generationId,
        'resource_id': request.resourceId.value,
        'section_id': request.sectionId.value,
        'part_id': request.partId.value,
        'attempt_id': request.attemptId,
      },
      rawLine: trimmed,
    );
  }

  String _safeShape(String line) {
    try {
      final decoded = jsonDecode(line.trim());
      if (decoded is Map<String, dynamic>) {
        final keys = decoded.keys.toList()..sort();
        return 'object keys=${keys.join(',')}';
      }
      return 'top-level=${decoded.runtimeType}';
    } catch (_) {
      return 'invalid-json';
    }
  }

  /// Decodes every non-empty line from a collected NDJSON completion.
  List<ResourceGenerationPatch> decodeNdjson(String ndjson) =>
      const LineSplitter()
          .convert(ndjson)
          .where((line) => line.trim().isNotEmpty)
          .map(decodeLine)
          .toList(growable: false);

  void _assertLegacyEnvelope(
    Map<String, dynamic> patch, {
    required String rawLine,
  }) {
    final expected = <String, Object>{
      'protocol_version': request.protocolVersion,
      'generation_id': request.generationId,
      'resource_id': request.resourceId.value,
      'section_id': request.sectionId.value,
      'part_id': request.partId.value,
      'attempt_id': request.attemptId,
    };
    for (final entry in expected.entries) {
      if (!patch.containsKey(entry.key)) {
        continue;
      }
      final actual = patch[entry.key];
      if (actual.runtimeType != entry.value.runtimeType ||
          actual != entry.value) {
        throw GenerationPatchParseException(
          '模型提供的固定协议字段与当前请求不一致',
          field: entry.key,
          rawLine: rawLine,
        );
      }
    }
  }
}
