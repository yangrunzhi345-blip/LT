import 'dart:convert';

import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_limits.dart';

/// Thrown when `metadata_json` violates the frozen metadata rules.
class ResourceMetadataException implements Exception {
  const ResourceMetadataException(this.message);

  final String message;

  @override
  String toString() => 'ResourceMetadataException: $message';
}

/// Enforces the frozen `metadata_json` rules for the unified resource tree.
///
/// Frozen by ADR-0001 and resolved as F-3 during Phase 1: `metadata_json` only
/// carries type-specific runtime core fields, provenance and necessary machine
/// metadata. Body text belongs to `ResourcePart.content`, and a serialized
/// content tree is never allowed inside metadata.
///
/// This policy deliberately lives in the repository layer instead of
/// `lib/domain/resources/`: measuring the serialized size needs JSON
/// serialization, and the Phase 0 contract-purity guard forbids serialization
/// helpers in the contract layer. The domain entities stay pure Dart while the
/// rule is enforced on the write boundary.
final class ResourceMetadataPolicy {
  const ResourceMetadataPolicy();

  /// Upper bound for the serialized (UTF-8) metadata payload.
  ///
  /// Rationale (F-3): comfortably above the runtime core fields Phase 10 builds
  /// character context from (system prompt, first message), yet far below a
  /// 50,000-character worldview body (roughly 150 KB once UTF-8 JSON encoded).
  /// It therefore admits legitimate use while still blocking a whole-tree dump.
  static const int maximumSerializedBytes = 64 * 1024;

  /// Keys that name a content container. Their presence means the author is
  /// mirroring the tree or the body into metadata instead of writing Parts.
  static const Set<String> forbiddenContainerKeys = {
    'sections',
    'section',
    'parts',
    'part',
    'content',
    'contentJson',
    'fullContent',
    'partsJson',
    'sectionsJson',
    'sectionJson',
    'contentTree',
    'tree',
    'treeJson',
    'modules',
    'moduleJson',
    'detailJson',
    'rawJson',
    'legacyJson',
    'blueprint',
  };

  /// Case- and separator-insensitive key form, so `content_json`, `contentJson`
  /// and `Content-Json` cannot slip past the guard.
  static String normalizeKey(String key) =>
      key.replaceAll(RegExp('[^A-Za-z0-9]'), '').toLowerCase();

  static final Set<String> _normalizedForbiddenKeys =
      forbiddenContainerKeys.map(normalizeKey).toSet();

  /// Validates [metadata] for [type]; throws [ResourceMetadataException].
  void validate({
    required ResourceType type,
    required Map<String, Object?> metadata,
  }) {
    if (metadata.isEmpty) return;

    final String encoded;
    try {
      encoded = jsonEncode(metadata);
    } catch (error) {
      throw ResourceMetadataException(
        'metadata 必须可 JSON 序列化：$error',
      );
    }

    final int sizeInBytes = utf8.encode(encoded).length;
    if (sizeInBytes > maximumSerializedBytes) {
      throw ResourceMetadataException(
        'metadata 序列化后为 $sizeInBytes 字节，超过上限 $maximumSerializedBytes 字节；'
        '正文请写入 Part.content',
      );
    }

    final int nominalBudget = ResourceLimits.policyFor(type).nominalCharacters;
    _visit(value: metadata, nominalBudget: nominalBudget);
  }

  void _visit({
    required Object? value,
    required int nominalBudget,
  }) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString();
        if (_normalizedForbiddenKeys.contains(normalizeKey(key))) {
          throw ResourceMetadataException(
            'metadata 不允许包含内容容器键 "$key"；'
            'Section / Part 正文必须写入内容树',
          );
        }
        _visit(value: entry.value, nominalBudget: nominalBudget);
      }
      return;
    }
    if (value is Iterable) {
      for (final item in value) {
        _visit(value: item, nominalBudget: nominalBudget);
      }
      return;
    }
    if (value is String && value.length >= nominalBudget) {
      throw ResourceMetadataException(
        'metadata 中单个字符串长度为 ${value.length}，已达到该资源类型的名义容量 '
        '$nominalBudget；正文必须写入 Part.content',
      );
    }
  }
}
