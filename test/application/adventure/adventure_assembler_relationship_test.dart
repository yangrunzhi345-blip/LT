import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/adventure_assembler.dart';
import 'package:lt_dialogue/domain/resources/character_relationship.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/models/adventure_config.dart';

void main() {
  test('assembler freezes selected resource relationships into config', () {
    final config = AdventureConfig();
    final assembled =
        const AdventureAssembler().assembleWithResourceRelationships(
      input: config,
      relationships: [
        CharacterRelationship(
          id: 'edge-1',
          endpointAResourceId: const ResourceId('a'),
          endpointBResourceId: const ResourceId('b'),
          relationType: CharacterRelationshipType.friend,
          endpointARole: 'friend',
          endpointBRole: 'friend',
          description: 'frozen',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      ],
      selectedResourceIds: {'a', 'b'},
    );
    expect(assembled.characterRelationships.single.description, 'frozen');
  });
}
