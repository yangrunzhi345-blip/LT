import 'dart:convert';

import 'character_card.dart';
import 'custom_attribute_item.dart';

/// 角色卡行条目的结构化视图 — 资料库/向导页面的**唯一解析点**。
///
/// [fromRow] 处理持久化 `json_data` 的 `data` 包装层（与
/// [CharacterCard.fromJson] 语义一致），并暴露展示所需的派生字段
/// （gender/profession/age）与 [toAssociatedMap]（关联角色上下文，
/// key 与既有 AI 上下文提取完全一致）。[rawData] 保留完整解码结果，
/// 供仍需要原始字段的调用方兜底。
class CharacterCardEntry {
  final String id;
  final String name;
  final String? matchingWorldviewId;
  final Map<String, dynamic> rawData;
  final CharacterCard card;

  CharacterCardEntry({
    required this.id,
    required this.name,
    required this.matchingWorldviewId,
    required this.rawData,
    required this.card,
  });

  /// 展开 `data` 包装后的卡片数据（与 CharacterCard.fromJson 一致）。
  Map<String, dynamic> get cardData {
    final nested = rawData['data'];
    return nested is Map<String, dynamic> ? nested : rawData;
  }

  String get gender => cardData['gender'] as String? ?? '';

  String get profession => cardData['profession'] as String? ?? '';

  String get age => cardData['age']?.toString() ?? '';

  String get personality => cardData['personality'] as String? ?? '';

  String get appearance => cardData['appearance'] as String? ?? '';

  /// 自添加项 / 自定义属性
  List<CustomAttributeItem> get customAttributes => card.customAttributes;

  /// 背景描述（background 优先，兼容 description）。
  String get background =>
      (cardData['background'] as String? ??
          cardData['description'] as String?) ??
      '';

  /// 体型/外貌细节描述（bodyDescription 优先，兼容 body_description）。
  String get bodyDescription =>
      (cardData['bodyDescription'] as String? ??
          cardData['body_description'] as String?) ??
      '';

  /// 关联角色上下文（AI 生成时注入的完整字段）。
  Map<String, String> toAssociatedMap() => {
        'name': name,
        'gender': gender,
        'profession': profession,
        'personality': personality,
        'background': background,
        'bodyDescription': bodyDescription,
        'appearance': appearance,
        if (customAttributes.isNotEmpty)
          'customAttributes': customAttributes
              .map((a) => a.toPromptText())
              .where((s) => s.isNotEmpty)
              .join('；'),
      };

  factory CharacterCardEntry.fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString() ?? '';
    Map<String, dynamic> raw = const {};
    try {
      final decoded = jsonDecode(row['json_data'] as String? ?? '{}');
      if (decoded is Map<String, dynamic>) raw = decoded;
    } catch (_) {}
    return CharacterCardEntry(
      id: id,
      name: row['name']?.toString() ?? '',
      matchingWorldviewId: row['matching_worldview_id']?.toString(),
      rawData: raw,
      card: CharacterCard.fromJson(raw),
    );
  }
}
