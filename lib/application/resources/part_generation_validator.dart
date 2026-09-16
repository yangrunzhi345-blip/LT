import '../../domain/resources/resource_generation_protocol.dart';
import '../../domain/resources/resource_limits.dart';

/// Exception thrown when a [PartGenerationResponse] fails validation against
/// the authorized [PartGenerationRequest].
class PartGenerationValidationException implements Exception {
  const PartGenerationValidationException(
    this.message, {
    this.field = '',
    this.expected = '',
    this.actual = '',
  });

  final String message;
  final String field;
  final String expected;
  final String actual;

  @override
  String toString() => 'PartGenerationValidationException: $message'
      '${field.isNotEmpty ? ' [field: $field]' : ''}'
      '${expected.isNotEmpty ? ' [expected: $expected, actual: $actual]' : ''}';
}

/// Strict validator for Part generation responses.
abstract final class PartGenerationValidator {
  /// Set of forbidden keys that would imply an attempt to redefine or mutate
  /// resource hierarchy or sibling nodes.
  static const Set<String> forbiddenStructuralKeys = {
    'sections',
    'parts',
    'subsections',
    'new_nodes',
    'chapters',
    'blueprint',
    'resource_tree',
    'nodes',
  };

  /// Validates a [PartGenerationResponse] strictly against its originating
  /// [PartGenerationRequest].
  ///
  /// [rawDecodedMap] is optional; when provided, it is checked for illegal
  /// structural mutation keys.
  static void validate({
    required PartGenerationRequest request,
    required PartGenerationResponse response,
    Map<String, dynamic>? rawDecodedMap,
  }) {
    // 1. Protocol Version
    if (response.protocolVersion != currentPartGenerationProtocolVersion) {
      throw PartGenerationValidationException(
        '不支持的协议版本',
        field: 'protocol_version',
        expected: '$currentPartGenerationProtocolVersion',
        actual: '${response.protocolVersion}',
      );
    }

    // 2. Generation ID
    if (response.generationId != request.generationId) {
      throw PartGenerationValidationException(
        '生成运行 ID 不匹配',
        field: 'generation_id',
        expected: request.generationId,
        actual: response.generationId,
      );
    }

    // 3. Resource ID
    if (response.resourceId.value != request.resourceId.value) {
      throw PartGenerationValidationException(
        '资源 ID 不匹配（禁止跨资源生成）',
        field: 'resource_id',
        expected: request.resourceId.value,
        actual: response.resourceId.value,
      );
    }

    // 4. Section ID
    if (response.sectionId.value != request.sectionId.value) {
      throw PartGenerationValidationException(
        '章节 ID 不匹配',
        field: 'section_id',
        expected: request.sectionId.value,
        actual: response.sectionId.value,
      );
    }

    // 5. Part ID
    if (response.partId.value != request.partId.value) {
      throw PartGenerationValidationException(
        'Part ID 不匹配（模型只能生成客户端授权的 Part）',
        field: 'part_id',
        expected: request.partId.value,
        actual: response.partId.value,
      );
    }

    // 6. Attempt ID
    if (response.attemptId != request.attemptId) {
      throw PartGenerationValidationException(
        '尝试令牌 (attempt_id) 不匹配（可能为过期响应或重试竞态）',
        field: 'attempt_id',
        expected: request.attemptId,
        actual: response.attemptId,
      );
    }

    // 7. Non-empty Content
    final trimmedContent = response.content.trim();
    if (trimmedContent.isEmpty) {
      throw const PartGenerationValidationException(
        '生成的 Part 正文内容不能为空',
        field: 'content',
      );
    }

    // 8. Content Length Upper Boundary
    const maxChars = ResourceLimits.maxPartCharacters;
    if (response.content.length > maxChars) {
      throw PartGenerationValidationException(
        '生成的 Part 正文字数超限（上限 $maxChars 字）',
        field: 'content_length',
        expected: '<= $maxChars',
        actual: '${response.content.length}',
      );
    }

    // 9. Check for Structural Mutation Keys
    if (rawDecodedMap != null) {
      for (final key in rawDecodedMap.keys) {
        final lower = key.toLowerCase();
        if (forbiddenStructuralKeys.contains(lower)) {
          throw PartGenerationValidationException(
            '响应包含被禁止的结构性字段 "$key"，模型不得更改或定义资源结构树',
            field: key,
          );
        }
      }
    }
  }
}
