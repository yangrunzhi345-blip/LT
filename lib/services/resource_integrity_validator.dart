import 'dart:convert';

import '../core/config/generation_limits.dart';
import '../domain/resources/resource_limits.dart';
import '../models/worldview_details.dart';
import 'worldview_length_guard.dart';

class ResourceValidationException implements Exception {
  final String message;

  const ResourceValidationException(this.message);

  @override
  String toString() => message;
}

enum RoleplayReadiness { incomplete, ready }

class RoleplayReadinessReport {
  final RoleplayReadiness readiness;
  final List<String> presentFields;

  const RoleplayReadinessReport({
    required this.readiness,
    required this.presentFields,
  });
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
    final total = const WorldviewLengthGuard().count(
      detailJson: details.toJson(),
      fallbackDescription: normalizedDescription,
    );
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
      _validateCard(
        name: name,
        jsonData: jsonData,
        label: '角色卡',
        absoluteCharacters: ResourceLimits.characterAbsoluteCharacters,
      );

  static void validateNpcCard({
    required String name,
    required String jsonData,
  }) =>
      _validateCard(
        name: name,
        jsonData: jsonData,
        label: 'NPC',
        absoluteCharacters: ResourceLimits.npcAbsoluteCharacters,
      );

  /// Evaluates RP richness without changing whether a legal card can be saved.
  static RoleplayReadinessReport evaluateCharacterReadiness(String jsonData) {
    Object? decoded;
    try {
      decoded = jsonDecode(jsonData);
    } catch (_) {
      return const RoleplayReadinessReport(
        readiness: RoleplayReadiness.incomplete,
        presentFields: [],
      );
    }
    if (decoded is! Map) {
      return const RoleplayReadinessReport(
        readiness: RoleplayReadiness.incomplete,
        presentFields: [],
      );
    }
    final root = Map<String, dynamic>.from(decoded);
    final payload = root['data'] is Map
        ? Map<String, dynamic>.from(root['data'] as Map)
        : root;
    const roleplayFields = [
      'description',
      'background',
      'personality',
      'scenario',
      'first_mes',
      'appearance',
      'profession',
      'world_profile',
      'custom_attributes',
    ];
    final present = roleplayFields
        .where((field) => _hasText(payload[field]))
        .toList(growable: false);
    return RoleplayReadinessReport(
      readiness: present.length >= 3
          ? RoleplayReadiness.ready
          : RoleplayReadiness.incomplete,
      presentFields: present,
    );
  }

  static void _validateCard({
    required String name,
    required String jsonData,
    required String label,
    required int absoluteCharacters,
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
    final hasContent = payload.entries
        .where((entry) => !_cardMetadataKeys.contains(entry.key))
        .any((entry) => _hasText(entry.value));
    if (!hasContent) {
      throw ResourceValidationException('$label至少需要一项有效内容');
    }
    // Fail-closed hard ceiling. Content above the absolute capacity is rejected
    // instead of being truncated, so a save either persists the full body or
    // reports an actionable error; it can never leave a half-written card.
    final bodyLength = _cardBodyLength(payload);
    if (bodyLength > absoluteCharacters) {
      throw ResourceValidationException(
        '$label正文共 $bodyLength 字，超过最大容量 $absoluteCharacters 字；'
        '请精简内容后重试（不会截断或部分保存）',
      );
    }
  }

  /// Persisted fields that are card metadata, not roleplay body text.
  static const Set<String> _cardMetadataKeys = {
    'name',
    'spec',
    'spec_version',
    'creator',
    'character_version',
    'tags',
  };

  /// Total roleplay body characters, excluding [_cardMetadataKeys].
  static int _cardBodyLength(Map<String, dynamic> payload) {
    var total = 0;
    for (final entry in payload.entries) {
      if (_cardMetadataKeys.contains(entry.key)) continue;
      total += _textLength(entry.value);
    }
    return total;
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
