import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/application/resource_library/character_generation_reference.dart';
import 'package:lt_dialogue/domain/resources/character_relationship.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';

void main() {
  test('serializes and restores a typed reference', () {
    const reference = CharacterGenerationReference(
      sourceResourceId: ResourceId('res_a'),
      relationshipType: CharacterRelationshipType.mentorStudent,
      sourceRole: 'mentor',
      generatedCharacterRole: 'student',
      description: 'A patient teacher',
      worldviewScope: 'world_x',
      metadata: {'origin': 'detail'},
    );

    final restored = CharacterGenerationReference.fromJson(reference.toJson());
    expect(restored.sourceResourceId, const ResourceId('res_a'));
    expect(restored.relationshipType, CharacterRelationshipType.mentorStudent);
    expect(restored.sourceRole, 'mentor');
    expect(restored.generatedCharacterRole, 'student');
    expect(restored.metadata, {'origin': 'detail'});
  });

  test('keeps multiple references isolated and immutable', () {
    const first = CharacterGenerationReference(
      sourceResourceId: ResourceId('res_a'),
      relationshipType: CharacterRelationshipType.friend,
      sourceRole: 'friend',
      generatedCharacterRole: 'friend',
      description: 'A',
    );
    const second = CharacterGenerationReference(
      sourceResourceId: ResourceId('res_b'),
      relationshipType: CharacterRelationshipType.custom,
      sourceRole: 'guardian',
      generatedCharacterRole: 'ward',
      description: 'B',
    );

    final relationship = CharacterGenerationRelationship.fromReferences(
      [first, second],
    );
    expect(relationship.references, hasLength(2));
    expect(relationship.references[0].description, 'A');
    expect(relationship.references[1].description, 'B');
    expect(
        () => (relationship.references as List).add(first), throwsA(anything));
    expect(relationship.toLegacyPromptMaps(), [
      {
        'resourceId': 'res_a',
        'relationType': 'friend',
        'sourceRole': 'friend',
        'targetRole': 'friend',
        'description': 'A',
      },
      {
        'resourceId': 'res_b',
        'relationType': 'custom',
        'sourceRole': 'guardian',
        'targetRole': 'ward',
        'description': 'B',
      },
    ]);
  });
}
