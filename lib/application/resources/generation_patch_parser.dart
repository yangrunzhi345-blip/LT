import 'dart:convert';

import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_generation_patch.dart';
import '../../domain/resources/resource_generation_protocol.dart';
import '../../domain/resources/resource_limits.dart';
import 'part_generation_parser.dart';

/// Exception thrown when a patch JSON string is malformed or invalid.
class GenerationPatchParseException implements Exception {
  const GenerationPatchParseException(
    this.message, {
    this.field = '',
    this.rawLine = '',
  });

  final String message;
  final String field;
  final String rawLine;

  @override
  String toString() => 'GenerationPatchParseException: $message'
      '${field.isNotEmpty ? ' [field: $field]' : ''}';
}

/// Thrown when an incoming patch sequence does not match the expected monotonic index.
class PatchSequenceGapException implements Exception {
  const PatchSequenceGapException({
    required this.expectedSequence,
    required this.actualSequence,
    required this.partId,
  });

  final int expectedSequence;
  final int actualSequence;
  final String partId;

  @override
  String toString() =>
      'PatchSequenceGapException: sequence 缺口 (期望: $expectedSequence, 实际: $actualSequence, partId: $partId)';
}

/// Thrown when an incoming patch cursor does not match the accumulated character count.
class PatchCursorMismatchException implements Exception {
  const PatchCursorMismatchException({
    required this.expectedCursor,
    required this.actualCursor,
    required this.partId,
  });

  final int expectedCursor;
  final int actualCursor;
  final String partId;

  @override
  String toString() =>
      'PatchCursorMismatchException: cursor 偏移不匹配 (期望: $expectedCursor, 实际: $actualCursor, partId: $partId)';
}

/// Parser and validator for line-delimited incremental generation patches.
abstract final class GenerationPatchParser {
  /// Strictly permitted keys in a patch JSON object.
  static const Set<String> _allowedPatchKeys = {
    'protocol_version',
    'generation_id',
    'resource_id',
    'section_id',
    'part_id',
    'attempt_id',
    'sequence',
    'op',
    'text_delta',
    'cursor',
    'summary',
    'error_message',
  };

  /// Read-only view of the allowed patch keys, for prompt-contract tests:
  /// every key a prompt declares must be accepted here.
  static Set<String> get allowedPatchKeys =>
      Set.unmodifiable(_allowedPatchKeys);

  /// Parses a single patch from a JSON line string.
  static ResourceGenerationPatch parsePatchLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      throw const GenerationPatchParseException('Patch 行内容为空', rawLine: '');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (e) {
      throw GenerationPatchParseException('Patch JSON 解析失败: $e',
          rawLine: trimmed);
    }

    if (decoded is! Map<String, dynamic>) {
      throw GenerationPatchParseException(
        'Patch 顶层必须为 JSON 对象 (Map)，实际为: ${decoded.runtimeType}',
        rawLine: trimmed,
      );
    }

    return parsePatchMap(decoded, rawLine: trimmed);
  }

  /// Parses and strictly validates a decoded map into a [ResourceGenerationPatch].
  static ResourceGenerationPatch parsePatchMap(
    Map<String, dynamic> map, {
    String rawLine = '',
  }) {
    // 1. Strict allowlist check: Reject unexpected or structural keys (e.g. "parts", "sections")
    for (final key in map.keys) {
      if (!_allowedPatchKeys.contains(key)) {
        throw GenerationPatchParseException(
          '未知或非法的 Patch 字段: "$key"，禁止携带额外结构或未授权属性',
          field: key,
          rawLine: rawLine,
        );
      }
    }

    // 2. Strict wire types
    final protocolVersion = map['protocol_version'];
    if (protocolVersion is! int) {
      throw GenerationPatchParseException(
        '协议版本字段 (protocol_version) 必须为标准整数 (int)，实际为: ${protocolVersion.runtimeType}',
        field: 'protocol_version',
        rawLine: rawLine,
      );
    }
    if (protocolVersion != 1) {
      throw GenerationPatchParseException(
        '不支持的协议版本: $protocolVersion (仅支持 1)',
        field: 'protocol_version',
        rawLine: rawLine,
      );
    }

    final sequence = map['sequence'];
    if (sequence is! int || sequence < 0) {
      throw GenerationPatchParseException(
        'sequence 必须为非负整数 (int)',
        field: 'sequence',
        rawLine: rawLine,
      );
    }

    final int? cursor;
    if (!map.containsKey('cursor')) {
      // Cursor is application-authoritative. Its absence is intentionally
      // preserved instead of being silently defaulted to zero.
      cursor = null;
    } else if (map['cursor'] case final int value when value >= 0) {
      // Accept correct legacy responses as an assertion only. The accumulator
      // still derives the authoritative value and rejects any disagreement.
      cursor = value;
    } else {
      throw GenerationPatchParseException(
        'cursor 若提供必须为非负整数 (int)，不能为 null 或其他类型',
        field: 'cursor',
        rawLine: rawLine,
      );
    }

    final opStr = map['op']?.toString() ?? '';
    final ResourcePatchOp op;
    try {
      op = ResourcePatchOp.fromWire(opStr);
    } catch (_) {
      throw GenerationPatchParseException(
        '未知的 op 操作类型: "$opStr"',
        field: 'op',
        rawLine: rawLine,
      );
    }

    final generationId = map['generation_id']?.toString() ?? '';
    if (generationId.isEmpty) {
      throw GenerationPatchParseException('缺失或空的 generation_id',
          field: 'generation_id', rawLine: rawLine);
    }

    final resourceId = map['resource_id']?.toString() ?? '';
    if (resourceId.isEmpty) {
      throw GenerationPatchParseException('缺失或空的 resource_id',
          field: 'resource_id', rawLine: rawLine);
    }

    final sectionId = map['section_id']?.toString() ?? '';
    if (sectionId.isEmpty) {
      throw GenerationPatchParseException('缺失或空的 section_id',
          field: 'section_id', rawLine: rawLine);
    }

    final partId = map['part_id']?.toString() ?? '';
    if (partId.isEmpty) {
      throw GenerationPatchParseException('缺失或空的 part_id',
          field: 'part_id', rawLine: rawLine);
    }

    final attemptId = map['attempt_id']?.toString() ?? '';
    if (attemptId.isEmpty) {
      throw GenerationPatchParseException('缺失或空的 attempt_id',
          field: 'attempt_id', rawLine: rawLine);
    }

    final textDelta = map['text_delta']?.toString() ?? '';
    final summary = map['summary']?.toString() ?? '';
    final errorMessage = map['error_message']?.toString();

    return ResourceGenerationPatch(
      protocolVersion: protocolVersion,
      generationId: generationId,
      resourceId: ResourceId(resourceId),
      sectionId: SectionId(sectionId),
      partId: PartId(partId),
      attemptId: attemptId,
      sequence: sequence,
      op: op,
      textDelta: textDelta,
      cursor: cursor,
      summary: summary,
      errorMessage: errorMessage,
    );
  }

  /// Parses multiple newline-delimited patch lines.
  static List<ResourceGenerationPatch> parseNdjson(String ndjson) {
    final lines = const LineSplitter().convert(ndjson);
    final patches = <ResourceGenerationPatch>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      patches.add(parsePatchLine(trimmed));
    }
    return patches;
  }

  /// Converts a full single [PartGenerationResponse] into a canonical 3-patch sequence:
  /// 1. `start_part` (sequence 0, cursor 0)
  /// 2. `append_text` (sequence 1, cursor 0, textDelta = content)
  /// 3. `complete_part` (sequence 2, cursor = content.length, summary)
  static List<ResourceGenerationPatch> responseToPatches(
    PartGenerationResponse response,
  ) {
    return [
      ResourceGenerationPatch(
        protocolVersion: 1,
        generationId: response.generationId,
        resourceId: response.resourceId,
        sectionId: response.sectionId,
        partId: response.partId,
        attemptId: response.attemptId,
        sequence: 0,
        op: ResourcePatchOp.startPart,
        cursor: 0,
      ),
      ResourceGenerationPatch(
        protocolVersion: 1,
        generationId: response.generationId,
        resourceId: response.resourceId,
        sectionId: response.sectionId,
        partId: response.partId,
        attemptId: response.attemptId,
        sequence: 1,
        op: ResourcePatchOp.appendText,
        textDelta: response.content,
        cursor: 0,
      ),
      ResourceGenerationPatch(
        protocolVersion: 1,
        generationId: response.generationId,
        resourceId: response.resourceId,
        sectionId: response.sectionId,
        partId: response.partId,
        attemptId: response.attemptId,
        sequence: 2,
        op: ResourcePatchOp.completePart,
        cursor: response.content.length,
        summary: response.summary,
      ),
    ];
  }
}

/// Accumulator that maintains state across a stream of [ResourceGenerationPatch]es
/// for a single Part generation attempt.
///
/// The canonical cursor is [_currentLength], measured in Dart UTF-16 code
/// units via [String.length]. Wire patches normally omit their cursor, so an
/// LLM can never corrupt content by estimating a long Unicode offset. A
/// legacy supplied cursor remains a strict assertion, not a fallback value.
class GenerationPatchAccumulator {
  GenerationPatchAccumulator({
    required this.expectedGenerationId,
    required this.expectedResourceId,
    required this.expectedSectionId,
    required this.expectedPartId,
    required this.expectedAttemptId,
    this.maxCharacters = ResourceLimits.maxPartCharacters,
  });

  final String expectedGenerationId;
  final ResourceId expectedResourceId;
  final SectionId expectedSectionId;
  final PartId expectedPartId;
  final String expectedAttemptId;
  final int maxCharacters;

  final StringBuffer _buffer = StringBuffer();
  int _currentLength = 0;
  int _nextSequence = 0;
  String _summary = '';
  bool _isStarted = false;
  bool _isCompleted = false;
  bool _isFailed = false;
  String? _errorMessage;

  int get currentLength => _currentLength;
  int get nextSequence => _nextSequence;
  bool get isStarted => _isStarted;
  bool get isCompleted => _isCompleted;
  bool get isFailed => _isFailed;
  String? get errorMessage => _errorMessage;
  String get currentText => _buffer.toString();
  String get summary => _summary;

  /// Applies a single patch. Idempotent on duplicate sequence (`patch.sequence < nextSequence`).
  /// Throws [PatchSequenceGapException] if a sequence number is skipped.
  /// Throws [PatchCursorMismatchException] if a supplied legacy cursor does
  /// not match the application-derived accumulated length.
  void applyPatch(ResourceGenerationPatch patch) {
    // 1. Identity validation
    if (patch.generationId != expectedGenerationId ||
        patch.resourceId != expectedResourceId ||
        patch.sectionId != expectedSectionId ||
        patch.partId != expectedPartId ||
        patch.attemptId != expectedAttemptId) {
      throw StateError(
        'Patch 标识与当前任务不匹配：'
        'gen(${patch.generationId}/$expectedGenerationId), '
        'res(${patch.resourceId.value}/${expectedResourceId.value}), '
        'part(${patch.partId.value}/${expectedPartId.value}), '
        'att(${patch.attemptId}/$expectedAttemptId)',
      );
    }

    // 2. Monotonic sequence check (idempotent write for duplicates, gap detection)
    if (patch.sequence < _nextSequence) {
      // Duplicate patch already applied: ignore without side effects
      return;
    }
    if (patch.sequence > _nextSequence) {
      throw PatchSequenceGapException(
        expectedSequence: _nextSequence,
        actualSequence: patch.sequence,
        partId: expectedPartId.value,
      );
    }

    _validateReportedCursor(patch);

    // 3. Operation handling
    switch (patch.op) {
      case ResourcePatchOp.startPart:
        if (_isStarted) {
          throw StateError('start_part 操作重复调用 (part: ${expectedPartId.value})');
        }
        _isStarted = true;
        break;

      case ResourcePatchOp.appendText:
        if (!_isStarted) {
          _isStarted = true; // Permissive start if append arrives as seq 0
        }
        if (_isCompleted) {
          throw StateError('已完成的 Part 禁止继续追加文本');
        }
        _buffer.write(patch.textDelta);
        _currentLength += patch.textDelta.length;
        if (_currentLength > maxCharacters) {
          throw PartGenerationParseException(
            'Part 正文长度超出上限限制 (当前: $_currentLength, 上限: $maxCharacters)',
            field: 'content',
          );
        }
        break;

      case ResourcePatchOp.completePart:
        if (_isCompleted) return;
        if (!_isStarted && _currentLength == 0) {
          _isStarted = true;
        }
        _isCompleted = true;
        if (patch.summary.isNotEmpty) {
          _summary = patch.summary;
        }
        break;

      case ResourcePatchOp.failPart:
        _isFailed = true;
        _errorMessage = patch.errorMessage ?? 'LLM 报告生成失败';
        break;
    }

    _nextSequence++;
  }

  void _validateReportedCursor(ResourceGenerationPatch patch) {
    final reportedCursor = patch.cursor;
    if (reportedCursor != null && reportedCursor != _currentLength) {
      throw PatchCursorMismatchException(
        expectedCursor: _currentLength,
        actualCursor: reportedCursor,
        partId: expectedPartId.value,
      );
    }
  }

  /// Exports accumulated content into a validated [PartGenerationResponse].
  PartGenerationResponse toResponse() {
    if (_isFailed) {
      throw StateError('当前 Part 生成失败: $_errorMessage');
    }
    if (!_isCompleted) {
      throw StateError('当前 Part 尚未收到 complete_part 结束标记');
    }
    return PartGenerationResponse(
      protocolVersion: 1,
      generationId: expectedGenerationId,
      resourceId: expectedResourceId,
      sectionId: expectedSectionId,
      partId: expectedPartId,
      attemptId: expectedAttemptId,
      content: currentText,
      summary: _summary,
      status: 'completed',
    );
  }
}
