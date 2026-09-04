import 'dart:convert';

import '../core/config/generation_limits.dart';
import '../models/worldview_details.dart';

class ResourceValidationException implements Exception {
  final String message;

  const ResourceValidationException(this.message);

  @override
  String toString() => message;
}

/// Shared validation for records that are about to become formal library data.
class ResourceIntegrityValidator {
  const ResourceIntegrityValidator._();

  static void validateWorldview({
    required String name,
    required String description,
    required WorldviewDetails details,
  }) {
    final normalizedName = name.trim();
    final normalizedDescription = description.trim();
    if (normalizedName.isEmpty) {
      throw const ResourceValidationException('世界观名称不能为空');
    }
    if (normalizedDescription.isEmpty) {
      throw const ResourceValidationException('世界观描述不能为空');
    }

    if (details.mode == WorldviewEditingMode.simple) {
      final length = normalizedDescription.length;
      if (length < 200 || length > 500) {
        throw ResourceValidationException(
          '简洁世界观描述需为 200–500 字，当前 $length 字',
        );
      }
      return;
    }

    final missingModules = WorldviewDetails.moduleKeys
        .where((key) => key != 'overview')
        .where((key) => !_hasText(details.modules[key]))
        .toList(growable: false);
    if (missingModules.isNotEmpty) {
      throw ResourceValidationException(
        '详细世界观存在空模块：${missingModules.join('、')}',
      );
    }
    final total = normalizedDescription.length +
        WorldviewDetails.moduleKeys.where((key) => key != 'overview').fold<int>(
            0, (sum, key) => sum + _textLength(details.modules[key]));
    if (total < GenerationLimits.detailedWorldviewMinimumCharacters ||
        total > GenerationLimits.detailedWorldviewMaximumCharacters) {
      throw ResourceValidationException(
        '详细世界观总内容需为 '
        '${GenerationLimits.detailedWorldviewMinimumCharacters}–'
        '${GenerationLimits.detailedWorldviewMaximumCharacters} 字，当前 $total 字',
      );
    }
  }

  static void validateCharacterCard({
    required String name,
    required String jsonData,
  }) =>
      _validateCard(name: name, jsonData: jsonData, label: '角色卡');

  static void validateNpcCard({
    required String name,
    required String jsonData,
  }) =>
      _validateCard(name: name, jsonData: jsonData, label: 'NPC');

  static void _validateCard({
    required String name,
    required String jsonData,
    required String label,
  }) {
    if (name.trim().isEmpty) {
      throw ResourceValidationException('$label名称不能为空');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(jsonData);
    } catch (_) {
      throw ResourceValidationException('$label内容不是有效 JSON');
    }
    if (decoded is! Map) {
      throw ResourceValidationException('$label内容不是 JSON 对象');
    }
    final root = Map<String, dynamic>.from(decoded);
    final payload = root['data'] is Map
        ? Map<String, dynamic>.from(root['data'] as Map)
        : root;
    const metadataKeys = {
      'name',
      'spec',
      'spec_version',
      'creator',
      'character_version',
      'tags',
    };
    final hasContent = payload.entries
        .where((entry) => !metadataKeys.contains(entry.key))
        .any((entry) => _hasText(entry.value));
    if (!hasContent) {
      throw ResourceValidationException('$label至少需要一项有效内容');
    }
  }

  static bool _hasText(Object? value) => _textLength(value) > 0;

  static int _textLength(Object? value) {
    if (value is String) return value.trim().length;
    if (value is Iterable) {
      return value.fold<int>(0, (sum, item) => sum + _textLength(item));
    }
    if (value is Map) {
      return value.entries
          .where((entry) => entry.key.toString() != 'status')
          .fold<int>(0, (sum, entry) => sum + _textLength(entry.value));
    }
    return 0;
  }
}
