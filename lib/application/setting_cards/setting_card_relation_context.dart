import '../../domain/resources/character_relationship.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../domain/setting_cards/setting_card_repository.dart';
import 'setting_card_markdown_parser.dart';

/// Loads a card's confirmed relations as generation context entries.
///
/// The relationship table stays the single source of truth: this reads it at
/// generation time instead of copying a relation list onto the card, so a
/// regenerated card cannot silently contradict relations the user confirmed.
final class SettingCardRelationContext {
  const SettingCardRelationContext._();

  static const SettingCardMarkdownParser _parser = SettingCardMarkdownParser();

  /// Returns one readable summary per counterpart of [cardId].
  ///
  /// Both the card row id and its legacy resource id are queried, because the
  /// relationship table is keyed by the legacy resource id while cards created
  /// in the library use their own id. Missing or deleted counterparts are
  /// skipped rather than failing generation.
  static Future<List<Map<String, String>>> load({
    required String cardId,
    required Future<List<CharacterRelationshipPerspective>> Function(ResourceId)
        listFor,
    required SettingCardRepository cards,
  }) async {
    final trimmed = cardId.trim();
    if (trimmed.isEmpty) return const <Map<String, String>>[];

    final ids = <String>{trimmed};
    final card =
        await cards.findById(trimmed) ?? await cards.findLegacyId(trimmed);
    final legacyId = card?.legacyId ?? '';
    if (legacyId.isNotEmpty) ids.add(legacyId);

    final relations = <CharacterRelationshipPerspective>[];
    final seen = <String>{};
    for (final id in ids) {
      for (final relation in await listFor(ResourceId(id))) {
        if (seen.add(relation.relationshipId)) relations.add(relation);
      }
    }

    final result = <Map<String, String>>[];
    for (final relation in relations) {
      final otherId = relation.counterpartResourceId.value;
      final other =
          await cards.findById(otherId) ?? await cards.findLegacyId(otherId);
      if (other == null || other.isDeleted) continue;
      final payload = _parser.resolveStructuredPayload(other);
      final relationText = relation.description.trim().isNotEmpty
          ? relation.description.trim()
          : relation.relationType.storageValue;
      result.add(<String, String>{
        'name': other.name,
        'profession': _text(payload['profession']),
        'personality': _text(payload['personality']),
        'background': _text(payload['description'] ?? payload['background']),
        'relation': relationText,
      });
    }
    return result;
  }

  static String _text(Object? value) =>
      value is String ? value.trim() : (value?.toString().trim() ?? '');
}
