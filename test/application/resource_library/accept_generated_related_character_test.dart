import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resource_library/accept_generated_related_character.dart';
import 'package:lt_dialogue/application/resource_library/character_generation_reference.dart';
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

  test('accept rejects a candidate whose identity does not match the resource',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('lt_accept_candidate_');
    DatabaseService.customDbDir = directory.path;
    await DatabaseService.resetDatabase();
    final trees =
        ResourceTreeRepositoryImpl(getDb: () => DatabaseService.database);
    final relationships = CharacterRelationshipRepositoryImpl(
      getDb: () => DatabaseService.database,
    );
    final accept = AcceptGeneratedRelatedCharacter(
      resourceRepository: trees,
      relationshipRepository: relationships,
    );
    final candidate = CharacterGenerationCandidate(
      candidateId: 'candidate_session_r1',
      creationSessionId: 'session',
      revision: 1,
      resourceId: const ResourceId('res_other'),
    );
    await expectLater(
      accept(
        resource: const ResourceTreeDraft(
          id: ResourceId('res_b'),
          type: ResourceType.character,
          name: 'B',
        ),
        relationships: const [],
        candidate: candidate,
      ),
      throwsA(isA<ResourceTreeConflictException>()),
    );
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    await directory.delete(recursive: true);
  });

  test('attaches relationships to a generated candidate resource atomically',
      () async {
    final fixture = await _openFixture('lt_accept_candidate_resource_');
    try {
      await fixture.trees.createResourceTree(const ResourceTreeDraft(
        id: ResourceId('res_source'),
        type: ResourceType.character,
        name: 'Source',
      ));
      await fixture.trees.createResourceTree(const ResourceTreeDraft(
        id: ResourceId('res_generated'),
        type: ResourceType.character,
        name: 'Generated',
        metadata: {'creation_session_id': 'session-1'},
      ));

      final candidate = CharacterGenerationCandidate(
        candidateId: 'candidate_session-1_r1',
        creationSessionId: 'session-1',
        revision: 1,
        resourceId: const ResourceId('res_generated'),
      );
      final accepted = await fixture.accept(
        resource: const ResourceTreeDraft(
          id: ResourceId('res_generated'),
          type: ResourceType.character,
          name: 'Generated',
          metadata: {'creation_session_id': 'session-1'},
        ),
        relationships: const [
          CharacterRelationshipDraftInput(
            firstResourceId: ResourceId('res_source'),
            firstRole: 'mentor',
            secondResourceId: ResourceId('res_generated'),
            secondRole: 'student',
            relationType: CharacterRelationshipType.mentorStudent,
          ),
        ],
        idempotencyKey: 'accept-candidate-1',
        creationSessionId: 'session-1',
        candidate: candidate,
      );

      expect(accepted, const ResourceId('res_generated'));
      expect(
        await fixture.relationships
            .listForResource(const ResourceId('res_source')),
        hasLength(1),
      );
      final saved = await fixture.trees.findResource(
        const ResourceId('res_generated'),
      );
      expect(saved?.metadata['related_character_candidate_id'],
          'candidate_session-1_r1');
    } finally {
      await fixture.close();
    }
  });

  test('rejects a candidate from an older blueprint revision', () async {
    final fixture = await _openFixture('lt_accept_stale_candidate_');
    try {
      await fixture.trees.createResourceTree(const ResourceTreeDraft(
        id: ResourceId('res_generated'),
        type: ResourceType.character,
        name: 'Generated',
        metadata: {
          'creation_session_id': 'session-1',
          'blueprint_revision': 2,
        },
      ));

      await expectLater(
        fixture.accept(
          resource: const ResourceTreeDraft(
            id: ResourceId('res_generated'),
            type: ResourceType.character,
            name: 'Generated',
            metadata: {
              'creation_session_id': 'session-1',
              'blueprint_revision': 2,
            },
          ),
          relationships: const [],
          creationSessionId: 'session-1',
          candidate: CharacterGenerationCandidate(
            candidateId: 'candidate_session-1_r1',
            creationSessionId: 'session-1',
            revision: 1,
            resourceId: const ResourceId('res_generated'),
          ),
        ),
        throwsA(isA<ResourceTreeConflictException>()),
      );
      expect(
        (await fixture.trees.findResource(const ResourceId('res_generated')))
            ?.metadata['related_character_candidate_id'],
        isNull,
      );
    } finally {
      await fixture.close();
    }
  });

  test('accept rejects non-character resource types', () async {
    final fixture = await _openFixture('lt_accept_type_');
    try {
      await expectLater(
        fixture.accept(
          resource: const ResourceTreeDraft(
            id: ResourceId('res_world'),
            type: ResourceType.worldview,
            name: 'World',
          ),
          relationships: const [],
        ),
        throwsA(isA<ResourceTreeConflictException>()),
      );
      expect(await fixture.trees.findResource(const ResourceId('res_world')),
          isNull);
    } finally {
      await fixture.close();
    }
  });

  test('rejects a worldview resource used as a relationship endpoint',
      () async {
    final fixture = await _openFixture('lt_accept_worldview_endpoint_');
    try {
      await fixture.trees.createResourceTree(const ResourceTreeDraft(
        id: ResourceId('res_world'),
        type: ResourceType.worldview,
        name: 'World',
      ));

      await expectLater(
        fixture.accept(
          resource: const ResourceTreeDraft(
            id: ResourceId('res_b'),
            type: ResourceType.character,
            name: 'B',
          ),
          relationships: const [
            CharacterRelationshipDraftInput(
              firstResourceId: ResourceId('res_world'),
              firstRole: 'setting',
              secondResourceId: ResourceId('res_b'),
              secondRole: 'resident',
              relationType: CharacterRelationshipType.friend,
            ),
          ],
        ),
        throwsA(isA<CharacterRelationshipValidationException>()),
      );
      expect(
          await fixture.trees.findResource(const ResourceId('res_b')), isNull);
    } finally {
      await fixture.close();
    }
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

  test('rolls back every write when a duplicate edge is encountered', () async {
    final fixture = await _openFixture('lt_accept_duplicate_');
    try {
      await fixture.trees.createResourceTree(const ResourceTreeDraft(
        id: ResourceId('res_a'),
        type: ResourceType.character,
        name: 'A',
      ));
      await expectLater(
        fixture.accept(
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
              firstResourceId: ResourceId('res_b'),
              firstRole: 'friend',
              secondResourceId: ResourceId('res_a'),
              secondRole: 'friend',
              relationType: CharacterRelationshipType.friend,
            ),
          ],
        ),
        throwsA(isA<CharacterRelationshipConflictException>()),
      );
      expect(
          await fixture.trees.findResource(const ResourceId('res_b')), isNull);
      expect(
          await fixture.relationships
              .listForResource(const ResourceId('res_a')),
          isEmpty);
    } finally {
      await fixture.close();
    }
  });

  test('revalidates trashed and purged source endpoints before accept',
      () async {
    final fixture = await _openFixture('lt_accept_lifecycle_');
    try {
      await fixture.trees.createResourceTree(const ResourceTreeDraft(
        id: ResourceId('res_a'),
        type: ResourceType.character,
        name: 'A',
      ));
      final db = await DatabaseService.database;
      await db.update('resources', {'deleted_at': 'trash'},
          where: 'id = ?', whereArgs: ['res_a']);
      await expectLater(
        fixture.accept(
          resource: const ResourceTreeDraft(
            id: ResourceId('res_b_trash'),
            type: ResourceType.character,
            name: 'B trash',
          ),
          relationships: const [
            CharacterRelationshipDraftInput(
              firstResourceId: ResourceId('res_a'),
              firstRole: 'friend',
              secondResourceId: ResourceId('res_b_trash'),
              secondRole: 'friend',
              relationType: CharacterRelationshipType.friend,
            ),
          ],
        ),
        throwsA(isA<CharacterRelationshipValidationException>()),
      );
      expect(await fixture.trees.findResource(const ResourceId('res_b_trash')),
          isNull);

      await db.delete('resources', where: 'id = ?', whereArgs: ['res_a']);
      await expectLater(
        fixture.accept(
          resource: const ResourceTreeDraft(
            id: ResourceId('res_b_purged'),
            type: ResourceType.character,
            name: 'B purged',
          ),
          relationships: const [
            CharacterRelationshipDraftInput(
              firstResourceId: ResourceId('res_a'),
              firstRole: 'friend',
              secondResourceId: ResourceId('res_b_purged'),
              secondRole: 'friend',
              relationType: CharacterRelationshipType.friend,
            ),
          ],
        ),
        throwsA(isA<CharacterRelationshipValidationException>()),
      );
      expect(await fixture.trees.findResource(const ResourceId('res_b_purged')),
          isNull);
    } finally {
      await fixture.close();
    }
  });

  test('same idempotency key returns one accepted aggregate on double submit',
      () async {
    final fixture = await _openFixture('lt_accept_double_');
    try {
      await fixture.trees.createResourceTree(const ResourceTreeDraft(
        id: ResourceId('res_a'),
        type: ResourceType.character,
        name: 'A',
      ));
      const resource = ResourceTreeDraft(
        id: ResourceId('res_b'),
        type: ResourceType.character,
        name: 'B',
      );
      const edges = [
        CharacterRelationshipDraftInput(
          firstResourceId: ResourceId('res_a'),
          firstRole: 'mentor',
          secondResourceId: ResourceId('res_b'),
          secondRole: 'student',
          relationType: CharacterRelationshipType.mentorStudent,
        ),
      ];
      final results = await Future.wait([
        fixture.accept(
          resource: resource,
          relationships: edges,
          idempotencyKey: 'accept-op-1',
          creationSessionId: 'creation-session-1',
        ),
        fixture.accept(
          resource: resource,
          relationships: edges,
          idempotencyKey: 'accept-op-1',
          creationSessionId: 'creation-session-1',
        ),
      ]);
      expect(results, everyElement(const ResourceId('res_b')));
      expect(await fixture.trees.findResource(const ResourceId('res_b')),
          isNotNull);
      expect(
          await fixture.relationships
              .listForResource(const ResourceId('res_a')),
          hasLength(1));
      final resourceRows = await (await DatabaseService.database)
          .query('resources', where: 'id = ?', whereArgs: ['res_b']);
      expect(resourceRows, hasLength(1));
    } finally {
      await fixture.close();
    }
  });

  test('repeated operation key reuses its original resource identity',
      () async {
    final fixture = await _openFixture('lt_accept_operation_');
    try {
      await fixture.trees.createResourceTree(const ResourceTreeDraft(
        id: ResourceId('res_a'),
        type: ResourceType.character,
        name: 'A',
      ));
      final first = await fixture.accept(
        resource: const ResourceTreeDraft(
          id: ResourceId('res_b1'),
          type: ResourceType.character,
          name: 'B1',
        ),
        relationships: const [
          CharacterRelationshipDraftInput(
            firstResourceId: ResourceId('res_a'),
            firstRole: 'friend',
            secondResourceId: ResourceId('res_b1'),
            secondRole: 'friend',
            relationType: CharacterRelationshipType.friend,
          ),
        ],
        idempotencyKey: 'accept-op-reused',
      );
      final second = await fixture.accept(
        resource: const ResourceTreeDraft(
          id: ResourceId('res_b2'),
          type: ResourceType.character,
          name: 'B2',
        ),
        relationships: const [
          CharacterRelationshipDraftInput(
            firstResourceId: ResourceId('res_a'),
            firstRole: 'friend',
            secondResourceId: ResourceId('res_b2'),
            secondRole: 'friend',
            relationType: CharacterRelationshipType.friend,
          ),
        ],
        idempotencyKey: 'accept-op-reused',
      );
      expect(second, first);
      expect(
          await fixture.trees.findResource(const ResourceId('res_b2')), isNull);
      expect(
          await fixture.relationships
              .listForResource(const ResourceId('res_a')),
          hasLength(1));
    } finally {
      await fixture.close();
    }
  });
}

Future<_AcceptFixture> _openFixture(String prefix) async {
  final directory = await Directory.systemTemp.createTemp(prefix);
  DatabaseService.customDbDir = directory.path;
  await DatabaseService.resetDatabase();
  final trees =
      ResourceTreeRepositoryImpl(getDb: () => DatabaseService.database);
  final relationships = CharacterRelationshipRepositoryImpl(
    getDb: () => DatabaseService.database,
  );
  return _AcceptFixture(
    directory: directory,
    trees: trees,
    relationships: relationships,
    accept: AcceptGeneratedRelatedCharacter(
      resourceRepository: trees,
      relationshipRepository: relationships,
    ),
  );
}

final class _AcceptFixture {
  const _AcceptFixture({
    required this.directory,
    required this.trees,
    required this.relationships,
    required this.accept,
  });

  final Directory directory;
  final ResourceTreeRepositoryImpl trees;
  final CharacterRelationshipRepositoryImpl relationships;
  final AcceptGeneratedRelatedCharacter accept;

  Future<void> close() async {
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    await directory.delete(recursive: true);
  }
}
