import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resource_library/accept_generated_related_character.dart';
import 'package:lt_dialogue/domain/resources/character_relationship.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';

void main() {
  test('accept input preserves typed endpoint identity', () {
    const input = CharacterRelationshipDraftInput(
      firstResourceId: ResourceId('a'),
      firstRole: 'mentor',
      secondResourceId: ResourceId('b'),
      secondRole: 'student',
      relationType: CharacterRelationshipType.mentorStudent,
    );
    expect(input.firstResourceId, const ResourceId('a'));
    expect(input.relationType, CharacterRelationshipType.mentorStudent);
  });
}
