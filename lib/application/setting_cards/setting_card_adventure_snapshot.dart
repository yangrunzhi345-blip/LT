import '../../domain/setting_cards/setting_card.dart';
import '../../domain/setting_cards/setting_card_repository.dart';
import '../../models/adventure_config.dart';
import '../../models/supporting_character.dart';
import '../adventure/adventure_readiness_gate.dart';
import '../resources/assembly_readiness_coordinator.dart';

/// Adventure start gate that freezes lightweight setting cards into the
/// AdventureConfig.
///
/// Card-backed assets are always ready: the card is the document, so there is
/// no assembly revision to wait for. Any asset without a card is delegated to
/// the retired tree gate unchanged, which keeps old data readable during the
/// transition (Phase 5c removes that fallback).
final class SettingCardAwareReadinessGate implements IAdventureReadinessGate {
  SettingCardAwareReadinessGate({
    required IAdventureReadinessGate inner,
    required SettingCardRepository cards,
  })  : _inner = inner,
        _cards = cards;

  final IAdventureReadinessGate _inner;
  final SettingCardRepository _cards;

  @override
  Future<AssemblyPrepareOutcome> prepare(String assetId) =>
      _inner.prepare(assetId);

  @override
  Future<Map<String, AdventureAssetReadiness>> resolve(
    Iterable<String> assetIds,
  ) async {
    final result = await _inner.resolve(assetIds);
    final cards = await _cardsById(assetIds);
    for (final entry in cards.entries) {
      result[entry.key] = AdventureAssetReadiness(
        assetId: entry.key,
        status: AdventureAssetGateStatus.ready,
        issueCode: AdventureReadinessIssueCode.ready,
        parameters: <String, Object?>{
          'name': entry.value.name,
          'resourceType': entry.value.kind.storageValue,
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
    if (cards.isEmpty) return _inner.enforceAndFreeze(config);

    // Freeze card-backed assets on a copy of the caller's config.
    final frozen = AdventureConfig.fromJson(config.toJson());
    _applyCards(frozen, cards);

    // Everything else still goes through the retired gate, but without the card
    // ids so an assembly revision can never overwrite a card snapshot.
    final legacyConfig = _withoutCards(config, cards.keys);
    if (_referencedIds(legacyConfig).isEmpty) {
      _applyCards(frozen, cards);
      return frozen;
    }
    final legacyFrozen = await _inner.enforceAndFreeze(legacyConfig);
    _mergeLegacy(frozen, legacyFrozen, cards.keys);
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

  /// Deep copy with every card-backed reference removed, so the legacy gate
  /// sees only assets it can actually resolve.
  static AdventureConfig _withoutCards(
    AdventureConfig config,
    Iterable<String> cardIds,
  ) {
    final stripped = AdventureConfig.fromJson(config.toJson());
    final worldviewId =
        stripped.worldviewSnapshot?['source_id']?.toString() ?? '';
    if (cardIds.contains(worldviewId)) {
      stripped.worldviewSnapshot = null;
    }
    stripped.selectedCharacters = stripped.selectedCharacters
        .where((item) => !cardIds.contains(item.characterId))
        .toList();
    stripped.npcSnapshots = stripped.npcSnapshots
        .where((item) => !cardIds.contains(item.assetId))
        .toList();
    stripped.resourceBindings = stripped.resourceBindings
        .where((binding) => !cardIds.contains(binding.resourceId))
        .toList();
    final protagonist = config.protagonistCharacter;
    if (protagonist != null && cardIds.contains(protagonist.characterId)) {
      // The protagonist fields describe a card, so the legacy gate must not
      // rewrite them.
      stripped.name = config.name;
      stripped.characterCard = null;
    }
    return stripped;
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
          config.worldviewSnapshot = <String, dynamic>{
            'source_id': id,
            'snapshot_kind': 'setting_card',
            'name': card.name,
            'summary': card.summary,
            'content': card.content,
          };
        case SettingCardKind.character:
          final protagonist = config.protagonistCharacter;
          config.selectedCharacters = config.selectedCharacters
              .map((item) => item.characterId == id
                  ? item.copyWith(
                      characterName: card.name,
                      characterCardJson: _cardJson(card),
                    )
                  : item)
              .toList();
          config.supportingCharacters = config.supportingCharacters
              .map((item) =>
                  item.id == id ? _renameSupporting(item, card.name) : item)
              .toList();
          if (protagonist != null && protagonist.characterId == id) {
            config.name = card.name;
            config.personality = '';
            config.characterCard = null;
          }
        case SettingCardKind.npc:
          config.npcSnapshots = config.npcSnapshots
              .map((snapshot) => snapshot.assetId == id
                  ? AdventureNpcSnapshot(
                      assetId: id,
                      name: card.name,
                      originWorldviewId: card.originWorldviewId,
                      npcJson: _npcJson(card),
                    )
                  : snapshot)
              .toList();
          config.supportingCharacters = config.supportingCharacters
              .map((item) =>
                  item.id == id ? _renameSupporting(item, card.name) : item)
              .toList();
      }
    }
  }

  static void _mergeLegacy(
    AdventureConfig result,
    AdventureConfig legacyFrozen,
    Iterable<String> cardIds,
  ) {
    final worldviewId =
        result.worldviewSnapshot?['source_id']?.toString() ?? '';
    if (!cardIds.contains(worldviewId)) {
      result.worldviewSnapshot = legacyFrozen.worldviewSnapshot;
    }
    final legacyById = <String, AdventureSelectedCharacter>{
      for (final item in legacyFrozen.selectedCharacters)
        item.characterId: item,
    };
    result.selectedCharacters = result.selectedCharacters
        .map((item) => cardIds.contains(item.characterId)
            ? item
            : legacyById[item.characterId] ?? item)
        .toList();
    final legacyNpcs = <String, AdventureNpcSnapshot>{
      for (final npc in legacyFrozen.npcSnapshots) npc.assetId: npc,
    };
    result.npcSnapshots = result.npcSnapshots
        .map((npc) => cardIds.contains(npc.assetId)
            ? npc
            : legacyNpcs[npc.assetId] ?? npc)
        .toList();
    final protagonist = result.protagonistCharacter;
    if (protagonist == null || !cardIds.contains(protagonist.characterId)) {
      result.name = legacyFrozen.name;
      result.gender = legacyFrozen.gender;
      result.age = legacyFrozen.age;
      result.personality = legacyFrozen.personality;
      result.protagonistClass = legacyFrozen.protagonistClass;
      result.protagonistBackground = legacyFrozen.protagonistBackground;
      result.characterCard = legacyFrozen.characterCard;
    }
    result.resourceBindings = legacyFrozen.resourceBindings;
  }

  static SupportingCharacter _renameSupporting(
    SupportingCharacter item,
    String name,
  ) {
    final copy = SupportingCharacter.fromJson(item.toJson());
    if (name.trim().isNotEmpty) copy.name = name;
    return copy;
  }

  static Map<String, dynamic> _cardJson(SettingCard card) => <String, dynamic>{
        'id': card.id,
        'name': card.name,
        'description': card.content,
        'content': card.content,
        'summary': card.summary,
        'source_id': card.id,
        'setting_card_id': card.id,
      };

  static Map<String, dynamic> _npcJson(SettingCard card) => <String, dynamic>{
        'id': card.id,
        'name': card.name,
        'description': card.content,
        'content': card.content,
        'summary': card.summary,
        'setting_card_id': card.id,
      };
}
