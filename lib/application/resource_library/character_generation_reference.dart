import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/character_relationship.dart';
import '../../core/utils/worldview_character_scope_policy.dart';

enum CharacterGenerationScopeFailure {
  conflictingReferenceWorldviews,
  crossWorldReference,
}

/// Typed failure raised when relationship references cannot share one
/// generation worldview scope.
final class CharacterGenerationScopeException implements Exception {
  const CharacterGenerationScopeException({
    required this.code,
    required this.message,
    this.targetWorldviewId = '',
    this.referenceWorldviewIds = const <String>[],
  });

  final CharacterGenerationScopeFailure code;
  final String message;
  final String targetWorldviewId;
  final List<String> referenceWorldviewIds;

  @override
  String toString() => 'CharacterGenerationScopeException($code): $message';
}

/// Applies the existing resource worldview compatibility semantics to
/// generation references. It never selects a target from the first reference.
abstract final class CharacterGenerationScopeValidator {
  static void validate({
    required Iterable<CharacterGenerationReference> references,
    String targetWorldviewId = '',
  }) {
    final target = WorldviewCharacterScopePolicy.stableId(targetWorldviewId);
    final sourceScopes = references
        .map((reference) =>
            WorldviewCharacterScopePolicy.stableId(reference.worldviewScope))
        .whereType<String>()
        .toSet();

    if (target == null && sourceScopes.length > 1) {
      throw CharacterGenerationScopeException(
        code: CharacterGenerationScopeFailure.conflictingReferenceWorldviews,
        message:
            'Multiple relationship references come from different worldviews; '
            'select an explicit compatible target worldview first',
        referenceWorldviewIds: sourceScopes.toList(growable: false),
      );
    }

    if (target == null) return;
    for (final source in sourceScopes) {
      final compatibility =
          WorldviewCharacterScopePolicy.compatibility(source, target);
      if (compatibility == CharacterWorldviewCompatibility.crossWorld) {
        throw CharacterGenerationScopeException(
          code: CharacterGenerationScopeFailure.crossWorldReference,
          message:
              'Relationship reference worldview $source is incompatible with '
              'target worldview $target',
          targetWorldviewId: target,
          referenceWorldviewIds: [source],
        );
      }
    }
  }
}

/// Immutable relationship context supplied to a related-character generation.
final class CharacterGenerationReference {
  CharacterGenerationReference({
    required this.sourceResourceId,
    required this.relationshipType,
    required this.sourceRole,
    required this.generatedCharacterRole,
    this.name = '',
    this.gender = '',
    this.profession = '',
    this.personality = '',
    this.background = '',
    this.appearance = '',
    this.description = '',
    this.worldviewScope,
    Map<String, String> metadata = const <String, String>{},
  }) : metadata = Map.unmodifiable(metadata) {
    if (sourceResourceId.value.trim().isEmpty) {
      throw const CharacterRelationshipValidationException(
        CharacterRelationshipFailure.invalidEndpoint,
        'A source ResourceId is required',
      );
    }
    CharacterRelationship.validate(
      relationType: relationshipType,
      endpointARole: sourceRole,
      endpointBRole: generatedCharacterRole,
      description: description,
    );
  }

  final ResourceId sourceResourceId;
  final CharacterRelationshipType relationshipType;
  final String sourceRole;
  final String generatedCharacterRole;
  final String name;
  final String gender;
  final String profession;
  final String personality;
  final String background;
  final String appearance;
  final String description;
  final String? worldviewScope;
  final Map<String, String> metadata;

  Map<String, Object?> toJson() => {
        'sourceResourceId': sourceResourceId.value,
        'relationshipType': relationshipType.storageValue,
        'sourceRole': sourceRole,
        'generatedCharacterRole': generatedCharacterRole,
        'name': name,
        'gender': gender,
        'profession': profession,
        'personality': personality,
        'background': background,
        'appearance': appearance,
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
      name: (json['name'] as String?)?.trim() ?? '',
      gender: (json['gender'] as String?)?.trim() ?? '',
      profession: (json['profession'] as String?)?.trim() ?? '',
      personality: (json['personality'] as String?)?.trim() ?? '',
      background: (json['background'] as String?)?.trim() ?? '',
      appearance: (json['appearance'] as String?)?.trim() ?? '',
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
  CharacterGenerationRelationship({
    required Iterable<CharacterGenerationReference> references,
  }) : references = List.unmodifiable(references);

  const CharacterGenerationRelationship.empty() : references = const [];

  final List<CharacterGenerationReference> references;

  factory CharacterGenerationRelationship.fromReferences(
    Iterable<CharacterGenerationReference> references,
  ) =>
      CharacterGenerationRelationship(
        references: List.unmodifiable(references),
      );

  List<Map<String, Object?>> toJson() =>
      references.map((reference) => reference.toJson()).toList(growable: false);

  /// Compatibility payload for the legacy LLM adapter boundary only.
  List<Map<String, dynamic>> toLegacyPromptMaps() => references
      .map((reference) => <String, dynamic>{
            ...reference.metadata,
            'resourceId': reference.sourceResourceId.value,
            'relationType': reference.relationshipType.storageValue,
            'sourceRole': reference.sourceRole,
            'targetRole': reference.generatedCharacterRole,
            if (reference.name.isNotEmpty) 'name': reference.name,
            if (reference.gender.isNotEmpty) 'gender': reference.gender,
            if (reference.profession.isNotEmpty)
              'profession': reference.profession,
            if (reference.personality.isNotEmpty)
              'personality': reference.personality,
            if (reference.background.isNotEmpty)
              'background': reference.background,
            if (reference.appearance.isNotEmpty)
              'appearance': reference.appearance,
            'description': reference.description,
            if (reference.worldviewScope != null)
              'worldviewScope': reference.worldviewScope,
          })
      .toList(growable: false);

  /// Stable, bounded prompt projection for the Resource Studio pipeline.
  ///
  /// The projection intentionally contains only the typed, user-authored
  /// relationship constraints. It does not expose a model-returned relation
  /// field and it never mutates the draft. Every Blueprint/Part retry can
  /// rebuild the same text from the persisted session draft.
  String toPromptConstraints() {
    if (references.isEmpty) return '';
    final lines = <String>[
      '以下关系约束由用户确认，必须保持不变；模型不得新增、删除或改写关系：',
    ];
    for (var index = 0; index < references.length; index++) {
      final reference = references[index];
      final line = StringBuffer()
        ..write(
            '${index + 1}. sourceResourceId=${reference.sourceResourceId.value}; ')
        ..write('name=${_bounded(reference.name, 120)}; ')
        ..write('gender=${_bounded(reference.gender, 40)}; ')
        ..write('profession=${_bounded(reference.profession, 120)}; ')
        ..write('personality=${_bounded(reference.personality, 280)}; ')
        ..write('background=${_bounded(reference.background, 400)}; ')
        ..write('appearance=${_bounded(reference.appearance, 280)}; ')
        ..write('relationType=${reference.relationshipType.storageValue}; ')
        ..write('sourceRole=${reference.sourceRole}; ')
        ..write('generatedCharacterRole=${reference.generatedCharacterRole}; ');
      if (reference.description.trim().isNotEmpty) {
        line.write('description=${reference.description.trim()}; ');
      }
      if (reference.worldviewScope?.trim().isNotEmpty == true) {
        line.write('worldviewScope=${reference.worldviewScope!.trim()};');
      }
      lines.add(line.toString());
    }
    return lines.join('\n');
  }

  static String _bounded(String value, int maxLength) {
    final normalized = value.trim();
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength)}…';
  }
}

/// Candidate-only draft. It cannot be used as a persisted relationship row.
final class CharacterRelationshipDraft {
  const CharacterRelationshipDraft({required this.relationship});

  final CharacterGenerationRelationship relationship;

  bool get isEmpty => relationship.references.isEmpty;
}

/// Identifies one reviewed generation candidate independently of its intent.
///
/// A regenerated candidate receives a new [candidateId]; the relationship
/// draft remains attached to the creation session until acceptance.
final class CharacterGenerationCandidate {
  CharacterGenerationCandidate({
    required this.candidateId,
    required this.creationSessionId,
    required this.revision,
    required this.resourceId,
  })  : assert(candidateId != ''),
        assert(creationSessionId != ''),
        assert(revision > 0);

  final String candidateId;
  final String creationSessionId;
  final int revision;
  final ResourceId resourceId;

  Map<String, Object?> toJson() => {
        'candidateId': candidateId,
        'creationSessionId': creationSessionId,
        'revision': revision,
        'resourceId': resourceId.value,
      };
}
