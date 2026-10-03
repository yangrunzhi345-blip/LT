import '../../services/character_card_storage_adapter.dart';
import '../../domain/resources/resource_contracts.dart';
import 'character_generation_reference.dart';

/// Maps stored character rows into bounded reference context for Studio drafts.
/// This is deliberately stateless: it does not own generation or persistence.
class CharacterReferenceContextMapper {
  const CharacterReferenceContextMapper._();

  static List<Map<String, String>> fromStoredRows({
    required List<Map<String, dynamic>> cards,
    required Set<String> selectedIds,
  }) {
    return cards
        .where((card) => selectedIds.contains(card['id']?.toString()))
        .map((card) {
      final data =
          CharacterCardStorageAdapter.fromStored(card['json_data']).data;
      return <String, String>{
        'name': _value(data, 'name', fallback: card['name']),
        'gender': _value(data, 'gender'),
        'profession': _value(data, 'profession'),
        'personality': _value(data, 'personality'),
        'background': _value(
          data,
          'background',
          fallback: data['description'],
        ),
        'appearance': _value(data, 'appearance'),
      };
    }).toList(growable: false);
  }

  /// Builds typed references without sharing mutable per-reference maps.
  static CharacterGenerationRelationship toGenerationRelationship({
    required Iterable<CharacterGenerationReference> references,
  }) {
    return CharacterGenerationRelationship.fromReferences(
      references.map((reference) => CharacterGenerationReference(
            sourceResourceId: ResourceId(reference.sourceResourceId.value),
            relationshipType: reference.relationshipType,
            sourceRole: reference.sourceRole,
            generatedCharacterRole: reference.generatedCharacterRole,
            name: reference.name,
            gender: reference.gender,
            profession: reference.profession,
            personality: reference.personality,
            background: reference.background,
            appearance: reference.appearance,
            description: reference.description,
            worldviewScope: reference.worldviewScope,
            metadata: Map.unmodifiable(reference.metadata),
          )),
    );
  }

  static String _value(
    Map<String, dynamic> data,
    String key, {
    Object? fallback,
  }) {
    final value = data[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
    return fallback?.toString().trim() ?? '';
  }
}
