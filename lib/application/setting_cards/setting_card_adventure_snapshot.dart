import '../../domain/resources/resource_contracts.dart';
import '../../domain/setting_cards/setting_card.dart';
import '../../domain/setting_cards/setting_card_repository.dart';
import '../../models/adventure_config.dart';
import '../../models/supporting_character.dart';
import '../../models/worldview_details.dart';
import '../adventure/adventure_readiness_gate.dart';
import '../resources/resource_readiness_contracts.dart';

/// Adventure start gate that freezes lightweight setting cards into the
/// AdventureConfig.
///
/// Card-backed assets are always ready: the card is the document, so there is
/// no assembly revision to wait for. Any id without a card is `notManaged`.
final class SettingCardAwareReadinessGate implements IAdventureReadinessGate {
  SettingCardAwareReadinessGate({required SettingCardRepository cards})
      : _cards = cards;

  final SettingCardRepository _cards;

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
          config.worldviewSnapshot = <String, dynamic>{
            'source_id': id,
            'snapshot_kind': 'setting_card',
            'name': card.name,
            'summary': card.summary,
            'content': card.content,
            // `WorldviewSnapshotService.buildManagedEntries` reads the legacy
            // preset keys, not this card-only payload. Without `description`
            // and a `detail_json` overview module the adventure freezes with
            // zero world entries, so mirror the simple-preset shape here.
            'description': card.content,
            'detail_json': _worldviewDetailJson(card),
            'entries_json': '[]',
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

  static SupportingCharacter _renameSupporting(
    SupportingCharacter item,
    String name,
  ) {
    final copy = SupportingCharacter.fromJson(item.toJson());
    if (name.trim().isNotEmpty) copy.name = name;
    return copy;
  }

  /// Serialized simple-worldview payload for [card].
  ///
  /// Reuses [WorldviewDetails.simple] so the frozen card and a legacy simple
  /// preset produce the same confirmed `overview` module.
  static String _worldviewDetailJson(SettingCard card) =>
      WorldviewDetails.simple(card.content).encode();

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
