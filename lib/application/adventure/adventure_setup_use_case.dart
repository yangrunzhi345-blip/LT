import 'dart:convert';

import '../../domain/setting_cards/setting_card.dart';
import '../../domain/setting_cards/setting_card_repository.dart';
import '../../models/worldview_details.dart';
import '../../services/repositories/library_repository.dart';

/// 冒险创建初始数据的应用层用例。
///
/// 消除页面与 Controller 对 DatabaseService 静态方法的直接依赖，
/// 统一经 [ILibraryRepository] 读取世界观预设与角色卡。
///
/// Phase 5c 之后资料库的读写权威转向 [SettingCard]，但向导仍以 legacy 行结构
/// 消费数据。两个数据源在这里合并：卡片覆盖同 id 的 legacy 行，并按
/// [SettingCard.legacyId] 去掉它代表的那条旧行，避免同一资料出现两次。
class AdventureSetupUseCase {
  /// Adventure library rows only; mirrors the legacy repository's default
  /// adventure-mode filter without importing the l10n-heavy mode model.
  static const String _adventureMode = 'adventure';

  final ILibraryRepository _repository;

  /// Optional so existing callers/tests can keep constructing the use case with
  /// only the legacy repository. When absent the legacy read is unchanged.
  final SettingCardRepository? _cards;

  const AdventureSetupUseCase(this._repository, {SettingCardRepository? cards})
      : _cards = cards;

  /// 加载冒险模式的世界观预设。
  Future<List<Map<String, dynamic>>> loadWorldviewPresets() async {
    final legacy = await _repository.getWorldviewPresets();
    return _mergeCards(legacy, SettingCardKind.worldview, _worldviewRow);
  }

  /// 加载冒险模式的角色卡列表。
  Future<List<Map<String, dynamic>>> loadCharacterCards() async {
    final legacy = await _repository.getCharacterCards();
    return _mergeCards(legacy, SettingCardKind.character, _cardRow);
  }

  /// Loads NPC assets available to adventure assembly.
  Future<List<Map<String, dynamic>>> loadNpcCards() async {
    final legacy = await _repository.getNpcCards();
    return _mergeCards(legacy, SettingCardKind.npc, _cardRow);
  }

  Future<List<Map<String, dynamic>>> _mergeCards(
    List<Map<String, dynamic>> legacyRows,
    SettingCardKind kind,
    Map<String, dynamic> Function(
      SettingCard card,
      Map<String, dynamic>? replacedLegacyRow,
    ) toLegacyRow,
  ) async {
    final repository = _cards;
    if (repository == null) return legacyRows;
    final cards = (await repository.list(kind: kind))
        .where((card) => card.mode.isEmpty || card.mode == _adventureMode)
        .toList(growable: false);
    if (cards.isEmpty) return legacyRows;

    final cardIds = <String>{for (final card in cards) card.id};
    final replacedIds = <String>{
      for (final card in cards)
        if (card.legacyId != null) card.legacyId!,
    };
    final legacyById = <String, Map<String, dynamic>>{
      for (final row in legacyRows) row['id']?.toString() ?? '': row,
    };

    final merged = <Map<String, dynamic>>[];
    for (final row in legacyRows) {
      final id = row['id']?.toString() ?? '';
      if (cardIds.contains(id) || replacedIds.contains(id)) continue;
      merged.add(row);
    }
    for (final card in cards) {
      final legacyId = card.legacyId;
      merged.add(toLegacyRow(
        card,
        legacyById[card.id] ?? (legacyId == null ? null : legacyById[legacyId]),
      ));
    }
    merged.sort((left, right) => _updatedAt(right).compareTo(_updatedAt(left)));
    return merged;
  }

  static String _updatedAt(Map<String, dynamic> row) =>
      row['updated_at']?.toString() ?? '';

  /// Card document rendered in the legacy worldview_presets row shape.
  ///
  /// A markdown card has no structured modules, so the whole document becomes
  /// the confirmed overview, exactly like a legacy "simple" preset.
  static Map<String, dynamic> _worldviewRow(
    SettingCard card,
    Map<String, dynamic>? replacedLegacyRow,
  ) =>
      <String, dynamic>{
        'id': card.id,
        'name': card.name,
        'description': card.content,
        'detail_json': WorldviewDetails.simple(card.content).encode(),
        'entries_json': '[]',
        'source': 'setting_card',
        'content_hash': '',
        'created_at': card.createdAt,
        'updated_at': card.updatedAt,
      };

  /// Card document rendered in the legacy character_cards / npc_cards row
  /// shape. [replacedLegacyRow] keeps the card↔worldview binding when the card
  /// itself never stored an origin id.
  static Map<String, dynamic> _cardRow(
    SettingCard card,
    Map<String, dynamic>? replacedLegacyRow,
  ) {
    final origin = card.originWorldviewId.trim();
    return <String, dynamic>{
      'id': card.id,
      'name': card.name,
      'json_data': jsonEncode(_cardPayload(card)),
      'source': 'setting_card',
      'matching_worldview_id': origin.isNotEmpty
          ? origin
          : replacedLegacyRow?['matching_worldview_id']?.toString() ?? '',
      'created_at': card.createdAt,
      'updated_at': card.updatedAt,
    };
  }

  /// Character/NPC payload the legacy rows carry as JSON text.
  ///
  /// Migrated cards keep the legacy json_data document verbatim; native cards
  /// are markdown, so the document becomes the prose description the wizard
  /// displays and the AI context reads.
  static Map<String, dynamic> _cardPayload(SettingCard card) {
    final document = card.content.trim();
    if (document.startsWith('{')) {
      try {
        final decoded = jsonDecode(document);
        if (decoded is Map<String, dynamic>) return decoded;
      } on FormatException {
        // A markdown body that merely starts with '{' is not a JSON document.
      }
    }
    return <String, dynamic>{
      'data': <String, dynamic>{
        'name': card.name,
        'description': document,
      },
    };
  }
}
