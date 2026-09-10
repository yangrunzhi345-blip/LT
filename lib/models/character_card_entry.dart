import 'dart:convert';

import 'character_card.dart';
import 'custom_attribute_item.dart';
import 'package:flutter/foundation.dart';

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

  /// Native/origin worldview ID; the legacy name is kept for DB compatibility.
  final String? matchingWorldviewId;
  final Map<String, dynamic> rawData;
  final CharacterCard card;

  /// True when the persisted `json_data` could not be turned into a card.
  ///
  /// Such a row keeps its row-level identity so the UI can still list it, while
  /// callers can filter, annotate or skip it instead of losing every other
  /// character card in the same result set.
  final bool hasParseError;

  CharacterCardEntry({
    required this.id,
    required this.name,
    required this.matchingWorldviewId,
    required this.rawData,
    required this.card,
    this.hasParseError = false,
  });

  /// 展开 `data` 包装后的卡片数据（与 CharacterCard.fromJson 一致）。
  Map<String, dynamic> get cardData {
    final nested = rawData['data'];
    return nested is Map<String, dynamic> ? nested : rawData;
  }

  String _rowText(Object? value) => switch (value) {
        String text => text,
        num number => number.toString(),
        bool flag => flag.toString(),
        _ => '',
      };

  String get gender => _rowText(cardData['gender']);

  String get profession => _rowText(cardData['profession']);

  String get age => cardData['age']?.toString() ?? '';

  String get personality => _rowText(cardData['personality']);

  String get appearance => _rowText(cardData['appearance']);

  /// 自添加项 / 自定义属性
  List<CustomAttributeItem> get customAttributes => card.customAttributes;

  /// 背景描述（background 优先，兼容 description）。
  String get background => _firstNonEmptyText(const [
        'background',
        'description',
      ]);

  /// 体型/外貌细节描述（bodyDescription 优先，兼容 body_description）。
  String get bodyDescription => _firstNonEmptyText(const [
        'bodyDescription',
        'body_description',
      ]);

  String _firstNonEmptyText(List<String> keys) {
    for (final key in keys) {
      final text = _rowText(cardData[key]);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

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
    var hasParseError = false;
    try {
      final decoded = jsonDecode(row['json_data'] as String? ?? '{}');
      if (decoded is Map<String, dynamic>) raw = decoded;
    } catch (e, stack) {
      hasParseError = true;
      debugPrint(
          'Error decoding json_data for row id=${row['id']}: $e\n$stack');
    }
    // A row whose JSON decodes but whose field types predate the current model
    // must not take the whole character list down with it: keep the row-level
    // identity so the user still sees which card failed, and fall back to a
    // safe empty card.
    CharacterCard card;
    try {
      card = CharacterCard.fromJson(raw);
    } catch (e, stack) {
      hasParseError = true;
      debugPrint(
          'Error building CharacterCard for row id=${row['id']}: $e\n$stack');
      card = CharacterCard();
    }
    return CharacterCardEntry(
      id: id,
      name: row['name']?.toString() ?? '',
      matchingWorldviewId: row['matching_worldview_id']?.toString(),
      rawData: raw,
      card: card,
      hasParseError: hasParseError,
    );
  }
}
