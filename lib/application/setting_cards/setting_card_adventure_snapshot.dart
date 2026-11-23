import 'dart:convert';

import '../../domain/resources/resource_contracts.dart';
import '../../domain/setting_cards/setting_card.dart';
import '../../domain/setting_cards/setting_card_repository.dart';
import '../../models/adventure_config.dart';
import '../../models/character_card.dart';
import '../../models/custom_attribute_item.dart';
import '../../models/supporting_character.dart';
import '../../models/tracked_state_definition.dart';
import '../../models/worldview_details.dart';
import '../../models/worldview_preset.dart';
import '../../services/worldview_snapshot_service.dart';
import '../adventure/adventure_readiness_gate.dart';
import '../resources/resource_readiness_contracts.dart';
import 'setting_card_markdown_parser.dart';

/// Adventure start gate that freezes lightweight setting cards into the
/// AdventureConfig.
///
/// Card-backed assets are always ready: the card is the document, so there is
/// no assembly revision to wait for. Any id without a card is `notManaged`.
final class SettingCardAwareReadinessGate implements IAdventureReadinessGate {
  SettingCardAwareReadinessGate({required SettingCardRepository cards})
      : _cards = cards;

  final SettingCardRepository _cards;

  static const SettingCardMarkdownParser _parser = SettingCardMarkdownParser();

  /// Fields copied from the resolved payload into a character card snapshot.
  ///
  /// Only keys that actually carry a value are written: an absent field must
  /// stay absent so `CharacterCard.fromJson` keeps its own defaults instead of
  /// reading an explicit empty string over a legacy value.
  static const List<String> _characterJsonKeys = <String>[
    'id',
    'name',
    'gender',
    'age',
    'profession',
    'archetype',
    'personality',
    'appearance',
    'bodyDescription',
    'body_description',
    'description',
    'background',
    'scenario',
    'first_mes',
    'mes_example',
    'ability',
    'weakness',
    'equipment',
    'system_prompt',
    'creator_notes',
    'world_profile',
    'custom_attributes',
    'tracked_state_definitions',
    'canonical_entities',
    'relationship_links',
    'source_id',
    'setting_card_id',
    'content',
    'summary',
  ];

  /// Structured fields that must stay structured.
  ///
  /// A prose `## world_profile` section is readable text, not a profile object;
  /// writing the string would make every downstream reader fail its type check
  /// instead of simply having no profile.
  static const Set<String> _structuredKeys = <String>{
    'world_profile',
    'custom_attributes',
    'tracked_state_definitions',
    'canonical_entities',
    'relationship_links',
  };

  static const List<String> _npcJsonKeys = <String>[
    'id',
    'name',
    'source_id',
    'role',
    'profession',
    'occupation',
    'personality',
    'description',
    'background',
    'appearance',
    'custom_attributes',
    'tracked_state_definitions',
    'content',
    'summary',
    'setting_card_id',
  ];

  /// The card-only gate has nothing to prepare.
  ///
  /// [IAdventureReadinessGate.prepare] is fixed to `Future<AssemblyPrepareOutcome>`,
  /// which can only carry an [AssemblyReadinessRecord], so the no-op returns a
  /// synthetic ready record. No inner gate is consulted.
  @override
  Future<AssemblyPrepareOutcome> prepare(String assetId) async {
    final record = AssemblyReadinessRecord(
      resourceId: assetId,
      state: ReadinessState.ready,
    );
    return AssemblyPrepareOutcome(record: record);
  }

  @override
  Future<Map<String, AdventureAssetReadiness>> resolve(
    Iterable<String> assetIds,
  ) async {
    final ids = assetIds.toList(growable: false);
    final cards = await _cardsById(ids);
    final result = <String, AdventureAssetReadiness>{};
    for (final id in ids) {
      final card = cards[id];
      if (card == null) {
        result[id] = AdventureAssetReadiness(
          assetId: id,
          status: AdventureAssetGateStatus.notManaged,
          issueCode: AdventureReadinessIssueCode.notManaged,
        );
        continue;
      }
      result[id] = AdventureAssetReadiness(
        assetId: id,
        status: AdventureAssetGateStatus.ready,
        issueCode: AdventureReadinessIssueCode.ready,
        parameters: <String, Object?>{
          'name': card.name,
          'resourceType': card.kind.storageValue,
          'snapshot': 'setting_card',
        },
      );
    }
    return result;
  }

  @override
  Future<Map<String, AdventureAssetReadiness>> resolveConfig(
    AdventureConfig config,
  ) =>
      resolve(_referencedIds(config));

  @override
  Future<AdventureConfig> enforceAndFreeze(AdventureConfig config) async {
    final cards = await _cardsById(_referencedIds(config));
    // Deep copy so the caller's config can never be mutated, then apply every
    // card snapshot.
    final frozen = AdventureConfig.fromJson(config.toJson());
    if (cards.isEmpty) return frozen;
    _applyCards(frozen, cards);
    return frozen;
  }

  Future<Map<String, SettingCard>> _cardsById(Iterable<String> ids) async {
    final cards = <String, SettingCard>{};
    for (final id in ids) {
      if (id.trim().isEmpty) continue;
      final card = await _cards.findById(id) ?? await _cards.findLegacyId(id);
      if (card == null || card.isDeleted) continue;
      cards[id] = card;
    }
    return cards;
  }

  static List<String> _referencedIds(AdventureConfig config) {
    final ids = <String>[];
    final worldviewId =
        config.worldviewSnapshot?['source_id']?.toString() ?? '';
    if (worldviewId.isNotEmpty) ids.add(worldviewId);
    for (final selected in config.selectedCharacters) {
      final id = selected.characterId.trim();
      if (id.isNotEmpty && !ids.contains(id)) ids.add(id);
    }
    for (final npc in config.npcSnapshots) {
      final id = npc.assetId.trim();
      if (id.isNotEmpty && !ids.contains(id)) ids.add(id);
    }
    return ids;
  }

  static void _applyCards(
    AdventureConfig config,
    Map<String, SettingCard> cards,
  ) {
    for (final entry in cards.entries) {
      final id = entry.key;
      final card = entry.value;
      switch (card.kind) {
        case SettingCardKind.worldview:
          config.worldviewSnapshot = _worldviewSnapshot(card);
        case SettingCardKind.character:
          final characterPayload = _parser.resolveStructuredPayload(card);
          final characterJson = _cardJson(card, characterPayload);
          config.selectedCharacters = config.selectedCharacters
              .map((item) => item.characterId == id
                  ? item.copyWith(
                      characterName: card.name,
                      characterCardJson: characterJson,
                    )
                  : item)
              .toList();
          config.supportingCharacters = config.supportingCharacters
              .map((item) => _matches(item, id)
                  ? _syncSupporting(
                      item: item,
                      card: card,
                      payload: characterPayload,
                    )
                  : item)
              .toList();
          final protagonist = config.protagonistCharacter;
          if (protagonist != null && protagonist.characterId == id) {
            _applyProtagonist(config, card, characterPayload, characterJson);
          }
        case SettingCardKind.npc:
          final npcPayload = _parser.resolveStructuredPayload(card);
          final npcJson = _npcJson(card, npcPayload);
          config.npcSnapshots = config.npcSnapshots
              .map((snapshot) => snapshot.assetId == id
                  ? AdventureNpcSnapshot(
                      assetId: id,
                      name: card.name,
                      originWorldviewId: card.originWorldviewId,
                      npcJson: npcJson,
                    )
                  : snapshot)
              .toList();
          config.supportingCharacters = config.supportingCharacters
              .map((item) => _matches(item, id)
                  ? _syncSupporting(
                      item: item,
                      card: card,
                      payload: npcPayload,
                    )
                  : item)
              .toList();
      }
    }
  }

  /// Freezes the protagonist's own identity from the card.
  ///
  /// The user's wizard choices win: a non-empty personality, gender, age or
  /// background is never overwritten by the card. The card only fills what the
  /// wizard left empty, so selecting a card cannot silently discard the user's
  /// explicit edits.
  static void _applyProtagonist(
    AdventureConfig config,
    SettingCard card,
    Map<String, dynamic> payload,
    Map<String, dynamic> characterJson,
  ) {
    final model = CharacterCard.fromJson(characterJson);
    config.name = card.name;
    config.characterCard = model;
    if (config.personality.trim().isEmpty &&
        model.personality.trim().isNotEmpty) {
      config.personality = model.personality;
    }
    if (config.gender.trim().isEmpty) {
      config.gender = _text(payload['gender']);
    }
    if (config.age.trim().isEmpty) {
      config.age = _text(payload['age']);
    }
    if (config.protagonistBackground.trim().isEmpty) {
      final background = _text(payload['background']);
      final fallback = _text(payload['description']);
      final chosen = background.isNotEmpty ? background : fallback;
      if (chosen.isNotEmpty) config.protagonistBackground = chosen;
    }
  }

  /// Keeps the legacy `supportingCharacters` compatibility row in sync.
  ///
  /// `AdventureTrackedStateFreezer` reads a selected character's legacy
  /// `custom_attributes` from this row when the card declares no explicit
  /// `tracked_state_definitions`. Without this copy the monitoring chain is
  /// empty even though the card still documents the attribute.
  static SupportingCharacter _syncSupporting({
    required SupportingCharacter item,
    required SettingCard card,
    required Map<String, dynamic> payload,
  }) {
    final name = card.name.trim();
    final custom = payload['custom_attributes'] is List
        ? _customAttributes(payload['custom_attributes'])
        : const <CustomAttributeItem>[];
    final definitions = payload.containsKey('tracked_state_definitions')
        ? TrackedStateDefinition.parseList(
            payload['tracked_state_definitions'],
            source: 'setting_card',
            fromResource: true,
          )
        : const <TrackedStateDefinition>[];
    // An empty payload field (a generated card often carries empty lists) must
    // not erase attributes the user already configured on the roster row.
    return item.copyWith(
      name: name.isNotEmpty ? name : null,
      customAttributes: custom.isEmpty ? null : custom,
      trackedStateDefinitions: definitions.isEmpty ? null : definitions,
    );
  }

  static bool _matches(SupportingCharacter item, String id) =>
      item.id.trim() == id;

  static List<CustomAttributeItem> _customAttributes(Object? raw) {
    if (raw is! List) return const <CustomAttributeItem>[];
    final items = <CustomAttributeItem>[];
    for (final item in raw) {
      if (item is! Map) continue;
      items.add(CustomAttributeItem.fromJson(Map<String, dynamic>.from(item)));
    }
    return items;
  }

  /// Builds the frozen worldview snapshot from the card.
  ///
  /// Entry rows are generated here so the frozen snapshot is renderable on its
  /// own. `adventure_provider` re-runs `buildManagedEntries` with the real
  /// adventure id before writing world entries, so the placeholder `0` only
  /// appears inside the persisted config copy and is never used as a row id.
  static Map<String, dynamic> _worldviewSnapshot(SettingCard card) {
    final detail = _parser.resolveWorldviewDetail(card);
    final description = _worldviewDescription(card, detail);
    // A hand-edited document can be valid JSON with the wrong value types
    // (for example format_version as a string). Degrading to the simple shape
    // is better than failing adventure start on a recoverable authoring error.
    WorldviewDetails details;
    try {
      details = WorldviewDetails.fromJson(
        detail,
        fallbackDescription: description,
      );
    } on Object {
      details = WorldviewDetails.simple(description);
    }
    final preset = WorldviewPreset(
      id: card.id,
      name: card.name,
      description: description,
      details: details,
    );
    final snapshot = WorldviewSnapshotService.snapshot(preset);
    snapshot['source_id'] = card.id;
    snapshot['snapshot_kind'] = 'setting_card';
    snapshot['name'] = card.name;
    snapshot['summary'] = card.summary;
    snapshot['content'] = card.content;
    final entries = WorldviewSnapshotService.buildManagedEntries(0, snapshot);
    snapshot['entries_json'] =
        jsonEncode(<Map<String, dynamic>>[for (final e in entries) e.toJson()]);
    return snapshot;
  }

  /// Short prose used as the preset description and fallback overview.
  ///
  /// The frozen description must be readable on its own: the card body is
  /// stored separately under content, so copying it here would make a card's
  /// Markdown document its own summary.
  static String _worldviewDescription(
    SettingCard card,
    Map<String, dynamic> detail,
  ) {
    final summary = card.summary.trim();
    if (summary.isNotEmpty) return summary;
    final modules = detail['modules'];
    if (modules is Map) {
      final text = _overviewText(modules['overview']);
      if (text.isNotEmpty) return text;
    }
    return SettingCardMarkdownParser.plainProseFromContent(card.content);
  }

  static String _overviewText(Object? value) {
    if (value is String) return _readable(value);
    if (value is Map) {
      for (final key in const ['summary', 'content', 'description', 'detail']) {
        final text = _readable(value[key]);
        if (text.isNotEmpty) return text;
      }
    }
    return '';
  }

  static String _readable(Object? value) {
    if (value is! String) return '';
    final text = value.trim();
    if (text.isEmpty || text.startsWith('{') || text.startsWith('[')) return '';
    if (text.split('\n').any((line) => line.trim().startsWith('#'))) return '';
    return text;
  }

  static Map<String, dynamic> _cardJson(
    SettingCard card,
    Map<String, dynamic> payload,
  ) {
    final result = _selectPersistable(payload, _characterJsonKeys);
    final body = result['bodyDescription'] ?? result['body_description'];
    if (body != null) {
      // Both spellings reach different readers (`CharacterCard` prefers the
      // camelCase key, legacy importers the snake_case one).
      result['bodyDescription'] = body;
      result['body_description'] = body;
    }
    final name = _text(payload['name']);
    final description = _text(payload['description']);
    result['id'] = card.id;
    result['name'] = name.isNotEmpty ? name : card.name;
    result['description'] = description.isNotEmpty
        ? description
        : SettingCardMarkdownParser.plainProseFromContent(card.content);
    result['content'] = card.content;
    result['summary'] = card.summary;
    result['source_id'] = card.id;
    result['setting_card_id'] = card.id;
    return result;
  }

  static Map<String, dynamic> _npcJson(
    SettingCard card,
    Map<String, dynamic> payload,
  ) {
    final result = _selectPersistable(payload, _npcJsonKeys);
    final name = _text(payload['name']);
    final description = _text(payload['description']);
    result['id'] = card.id;
    result['name'] = name.isNotEmpty ? name : card.name;
    result['source_id'] = card.id;
    result['description'] = description.isNotEmpty
        ? description
        : SettingCardMarkdownParser.plainProseFromContent(card.content);
    result['content'] = card.content;
    result['summary'] = card.summary;
    result['setting_card_id'] = card.id;
    return result;
  }

  static Map<String, dynamic> _selectPersistable(
    Map<String, dynamic> payload,
    List<String> keys,
  ) {
    final result = <String, dynamic>{};
    for (final key in keys) {
      final value = payload[key];
      if (!_isMeaningful(value)) continue;
      if (_structuredKeys.contains(key) && value is! Map && value is! List) {
        continue;
      }
      result[key] = value;
    }
    return result;
  }

  static bool _isMeaningful(Object? value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    if (value is List) return value.isNotEmpty;
    return true;
  }

  static String _text(Object? value) {
    if (value is String) return value.trim();
    if (value is num || value is bool) return value.toString().trim();
    return '';
  }
}
