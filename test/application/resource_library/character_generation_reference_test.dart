import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/application/resource_library/character_generation_reference.dart';
import 'package:lt_dialogue/domain/resources/character_relationship.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';

void main() {
  test('candidate identity changes across regeneration revisions', () {
    final first = CharacterGenerationCandidate(
      candidateId: 'candidate_b1',
      creationSessionId: 'creation_1',
      revision: 1,
      resourceId: const ResourceId('res_b1'),
    );
    final second = CharacterGenerationCandidate(
      candidateId: 'candidate_b2',
      creationSessionId: first.creationSessionId,
      revision: 2,
      resourceId: const ResourceId('res_b2'),
    );
    expect(
        first.toJson()['candidateId'], isNot(second.toJson()['candidateId']));
    expect(second.revision, greaterThan(first.revision));
  });

  test('copies metadata and prevents reserved identity overrides', () {
    final metadata = {'resourceId': 'wrong', 'sourceRole': 'wrong'};
    final reference = CharacterGenerationReference(
      sourceResourceId: const ResourceId('res_a'),
      relationshipType: CharacterRelationshipType.friend,
      sourceRole: 'friend',
      generatedCharacterRole: 'friend',
      metadata: metadata,
    );
    metadata['resourceId'] = 'changed';
    expect(reference.metadata['resourceId'], 'wrong');
    expect(() => reference.metadata['x'] = 'y', throwsUnsupportedError);
    final payload = CharacterGenerationRelationship(references: [reference])
        .toLegacyPromptMaps()
        .single;
    expect(payload['resourceId'], 'res_a');
    expect(payload['sourceRole'], 'friend');
  });

  test('rejects invalid directional roles before generation', () {
    expect(
      () => CharacterGenerationReference(
        sourceResourceId: const ResourceId('res_a'),
        relationshipType: CharacterRelationshipType.mentorStudent,
        sourceRole: 'mentor',
        generatedCharacterRole: 'mentor',
      ),
      throwsA(isA<CharacterRelationshipValidationException>()),
    );
  });

  test('serializes and restores a typed reference', () {
    final reference = CharacterGenerationReference(
      sourceResourceId: const ResourceId('res_a'),
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
    final first = CharacterGenerationReference(
      sourceResourceId: const ResourceId('res_a'),
      relationshipType: CharacterRelationshipType.friend,
      sourceRole: 'friend',
      generatedCharacterRole: 'friend',
      description: 'A',
    );
    final second = CharacterGenerationReference(
      sourceResourceId: const ResourceId('res_b'),
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

  test('projects only typed constraints for every studio prompt attempt', () {
    final relationship = CharacterGenerationRelationship.fromReferences([
      CharacterGenerationReference(
        sourceResourceId: const ResourceId('res_source'),
        relationshipType: CharacterRelationshipType.mentorStudent,
        sourceRole: 'mentor',
        generatedCharacterRole: 'student',
        description: 'A guarded apprenticeship',
        worldviewScope: 'world_main',
      ),
    ]);

    final constraints = relationship.toPromptConstraints();
    expect(constraints, contains('sourceResourceId=res_source'));
    expect(constraints, contains('relationType=mentor_student'));
    expect(constraints, contains('sourceRole=mentor'));
    expect(constraints, contains('generatedCharacterRole=student'));
    expect(constraints, contains('description=A guarded apprenticeship'));
    expect(constraints, contains('worldviewScope=world_main'));
    expect(constraints, isNot(contains('targetRole')));
  });
}
