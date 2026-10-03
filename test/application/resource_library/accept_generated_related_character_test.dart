import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resource_library/accept_generated_related_character.dart';
import 'package:lt_dialogue/domain/resources/character_relationship.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/character_relationship_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

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

  test('rolls back resource when an endpoint relationship fails', () async {
    final directory = await Directory.systemTemp.createTemp('lt_accept_');
    DatabaseService.customDbDir = directory.path;
    await DatabaseService.resetDatabase();
    final trees =
        ResourceTreeRepositoryImpl(getDb: () => DatabaseService.database);
    final relationships = CharacterRelationshipRepositoryImpl(
      getDb: () => DatabaseService.database,
    );
    await trees.createResourceTree(const ResourceTreeDraft(
      id: ResourceId('res_a'),
      type: ResourceType.character,
      name: 'A',
    ));
    final accept = AcceptGeneratedRelatedCharacter(
      resourceRepository: trees,
      relationshipRepository: relationships,
    );
    await expectLater(
      accept(
        resource: const ResourceTreeDraft(
          id: ResourceId('res_b'),
          type: ResourceType.character,
          name: 'B',
        ),
        relationships: const [
          CharacterRelationshipDraftInput(
            firstResourceId: ResourceId('res_a'),
            firstRole: 'friend',
            secondResourceId: ResourceId('res_b'),
            secondRole: 'friend',
            relationType: CharacterRelationshipType.friend,
          ),
          CharacterRelationshipDraftInput(
            firstResourceId: ResourceId('missing'),
            firstRole: 'friend',
            secondResourceId: ResourceId('res_b'),
            secondRole: 'friend',
            relationType: CharacterRelationshipType.friend,
          ),
        ],
      ),
      throwsA(anything),
    );
    expect(await trees.findResource(const ResourceId('res_b')), isNull);
    expect(await relationships.listForResource(const ResourceId('res_a')),
        isEmpty);
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    await directory.delete(recursive: true);
  });
}
