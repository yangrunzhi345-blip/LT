import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/character_relationship.dart';

/// Immutable relationship context supplied to a related-character generation.
final class CharacterGenerationReference {
  const CharacterGenerationReference({
    required this.sourceResourceId,
    required this.relationshipType,
    required this.sourceRole,
    required this.generatedCharacterRole,
    this.description = '',
    this.worldviewScope,
    this.metadata = const <String, String>{},
  }) : assert(sourceRole != '' && generatedCharacterRole != '');

  final ResourceId sourceResourceId;
  final CharacterRelationshipType relationshipType;
  final String sourceRole;
  final String generatedCharacterRole;
  final String description;
  final String? worldviewScope;
  final Map<String, String> metadata;

  Map<String, Object?> toJson() => {
        'sourceResourceId': sourceResourceId.value,
        'relationshipType': relationshipType.storageValue,
        'sourceRole': sourceRole,
        'generatedCharacterRole': generatedCharacterRole,
        'description': description,
        if (worldviewScope != null) 'worldviewScope': worldviewScope,
        'metadata': Map<String, String>.unmodifiable(metadata),
      };

  factory CharacterGenerationReference.fromJson(Map<String, Object?> json) {
    final id = (json['sourceResourceId'] as String?)?.trim() ?? '';
    final sourceRole = (json['sourceRole'] as String?)?.trim() ?? '';
    final targetRole =
        (json['generatedCharacterRole'] as String?)?.trim() ?? '';
    if (id.isEmpty || sourceRole.isEmpty || targetRole.isEmpty) {
      throw const FormatException('Invalid character generation reference');
    }
    final rawMetadata = json['metadata'];
    return CharacterGenerationReference(
      sourceResourceId: ResourceId(id),
      relationshipType: CharacterRelationshipType.fromStorageValue(
        (json['relationshipType'] as String?)?.trim() ?? '',
      ),
      sourceRole: sourceRole,
      generatedCharacterRole: targetRole,
      description: (json['description'] as String?)?.trim() ?? '',
      worldviewScope: (json['worldviewScope'] as String?)?.trim(),
      metadata: rawMetadata is Map
          ? Map.unmodifiable(rawMetadata.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            ))
          : const <String, String>{},
    );
  }
}

/// Typed relationship intent retained on a candidate/session.
final class CharacterGenerationRelationship {
  const CharacterGenerationRelationship({required this.references});

  final List<CharacterGenerationReference> references;

  factory CharacterGenerationRelationship.fromReferences(
    Iterable<CharacterGenerationReference> references,
  ) =>
      CharacterGenerationRelationship(
        references: List.unmodifiable(references),
      );

  List<Map<String, Object?>> toJson() =>
      references.map((reference) => reference.toJson()).toList(growable: false);
}

/// Candidate-only draft. It cannot be used as a persisted relationship row.
final class CharacterRelationshipDraft {
  const CharacterRelationshipDraft({required this.relationship});

  final CharacterGenerationRelationship relationship;

  bool get isEmpty => relationship.references.isEmpty;
}
