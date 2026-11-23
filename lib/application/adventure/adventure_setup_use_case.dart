import 'dart:convert';

import '../../domain/setting_cards/setting_card.dart';
import '../../domain/setting_cards/setting_card_repository.dart';
import '../../services/repositories/library_repository.dart';
import '../setting_cards/setting_card_markdown_parser.dart';

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
  static const SettingCardMarkdownParser _parser = SettingCardMarkdownParser();

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
        'description': _worldviewDescription(card),
        'detail_json': jsonEncode(_parser.resolveWorldviewDetail(card)),
        'entries_json': '[]',
        'source': 'setting_card',
        'content_hash': '',
        'created_at': card.createdAt,
        'updated_at': card.updatedAt,
      };

  /// Short prose overview for the wizard row.
  ///
  /// Priority is summary, then the overview module, then the first prose
  /// paragraph. The wizard shows this string directly, so a Markdown heading or
  /// a JSON document must never reach it.
  static String _worldviewDescription(SettingCard card) {
    final summary = card.summary.trim();
    if (summary.isNotEmpty) return summary;
    final detail = _parser.resolveWorldviewDetail(card);
    final overview = _overviewText(detail['modules']);
    if (overview.isNotEmpty) return overview;
    return SettingCardMarkdownParser.plainProseFromContent(card.content);
  }

  static String _overviewText(Object? modules) {
    if (modules is! Map) return '';
    final overview = modules['overview'];
    if (overview is String) return _readable(overview);
    if (overview is Map) {
      for (final key in const ['summary', 'content', 'description', 'detail']) {
        final text = _readable(overview[key]);
        if (text.isNotEmpty) return text;
      }
    }
    return '';
  }

  /// Rejects Markdown / JSON while accepting ordinary prose.
  static String _readable(Object? value) {
    if (value is! String) return '';
    final text = value.trim();
    if (text.isEmpty || text.startsWith('{') || text.startsWith('[')) return '';
    if (text.split('\n').any((line) => line.trim().startsWith('#'))) return '';
    return text;
  }

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
  /// The card document is resolved back into structured fields first, so the
  /// wizard and AI context read the same gender/age/profession/personality/
  /// appearance the card was rendered from. A card that holds only prose
  /// degrades to a plain name + description without any Markdown or JSON.
  static Map<String, dynamic> _cardPayload(SettingCard card) {
    final payload = _parser.resolveStructuredPayload(card);
    if (_hasStructuredFields(payload)) {
      final result = Map<String, dynamic>.from(payload);
      result['description'] = _readable(result['description']);
      if ((result['description'] as String).isEmpty) {
        final prose = _plainProse(card);
        if (prose.isNotEmpty) result['description'] = prose;
      }
      return result;
    }
    return <String, dynamic>{
      'data': <String, dynamic>{
        'name': card.name.trim(),
        'description': _plainProse(card),
      },
    };
  }

  /// Fields that make a card more than a prose document.
  static bool _hasStructuredFields(Map<String, dynamic> payload) {
    const keys = <String>[
      'gender',
      'age',
      'profession',
      'personality',
      'appearance',
      'bodyDescription',
      'body_description',
      'world_profile',
      'custom_attributes',
      'ability',
      'weakness',
      'equipment',
      'first_mes',
      'mes_example',
      'speaking_style',
      'character_arc',
      'background',
    ];
    for (final key in keys) {
      final value = payload[key];
      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;
      if (value is Map && value.isEmpty) continue;
      if (value is List && value.isEmpty) continue;
      return true;
    }
    return false;
  }

  static String _plainProse(SettingCard card) {
    final summary = card.summary.trim();
    if (summary.isNotEmpty) return summary;
    final payloadProse = SettingCardMarkdownParser.plainProseFromContent(
      _parser.resolveStructuredPayload(card)['description']?.toString() ?? '',
    );
    if (payloadProse.isNotEmpty) return payloadProse;
    return SettingCardMarkdownParser.plainProseFromContent(card.content);
  }
}
