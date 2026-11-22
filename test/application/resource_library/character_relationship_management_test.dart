import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:lt_dialogue/application/resource_library/character_relationship_management.dart';
import 'package:lt_dialogue/domain/resources/character_relationship.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/services/repositories/character_relationship_repository.dart';

void main() {
  test('projects repository relationships through the application boundary',
      () async {
    final repository = _FakeRelationshipRepository();
    final management = CharacterRelationshipManagement(repository);
    final result = await management.listFor(const ResourceId('res_b'));
    expect(result.single.subjectRole, 'student');
    expect(result.single.counterpartRole, 'mentor');
  });

  test('createFromPerspective canonicalizes a swapped subject/counterpart pair',
      () async {
    final repository = _FakeRelationshipRepository();
    final management = CharacterRelationshipManagement(repository);

    final created = await management.createFromPerspective(
      subjectResourceId: const ResourceId('res_b'),
      counterpartResourceId: const ResourceId('res_a'),
      relationType: CharacterRelationshipType.mentorStudent,
      subjectRole: 'student',
      counterpartRole: 'mentor',
      description: 'studies under',
    );

    expect(created.endpointAResourceId, const ResourceId('res_a'));
    expect(created.endpointARole, 'mentor');
    expect(created.endpointBResourceId, const ResourceId('res_b'));
    expect(created.endpointBRole, 'student');
    expect(repository.createdFirstId, const ResourceId('res_a'));
    expect(repository.createdFirstRole, 'mentor');
    expect(repository.createdSecondId, const ResourceId('res_b'));
    expect(repository.createdSecondRole, 'student');
    expect(repository.createdDescription, 'studies under');
  });
}

final class _FakeRelationshipRepository
    implements CharacterRelationshipRepository {
  @override
  Future<List<CharacterRelationship>> listForResource(
          ResourceId resourceId) async =>
      [
        CharacterRelationship(
          id: 'r1',
          endpointAResourceId: const ResourceId('res_a'),
          endpointBResourceId: const ResourceId('res_b'),
          relationType: CharacterRelationshipType.mentorStudent,
          endpointARole: 'mentor',
          endpointBRole: 'student',
          description: '',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      ];

  ResourceId? createdFirstId;
  String? createdFirstRole;
  ResourceId? createdSecondId;
  String? createdSecondRole;
  String? createdDescription;

  @override
  Future<CharacterRelationship> create({
    required ResourceId firstResourceId,
    required String firstRole,
    required ResourceId secondResourceId,
    required String secondRole,
    required CharacterRelationshipType relationType,
    String description = '',
  }) async {
    createdFirstId = firstResourceId;
    createdFirstRole = firstRole;
    createdSecondId = secondResourceId;
    createdSecondRole = secondRole;
    createdDescription = description;
    return CharacterRelationship(
      id: 'r-new',
      endpointAResourceId: firstResourceId,
      endpointBResourceId: secondResourceId,
      relationType: relationType,
      endpointARole: firstRole,
      endpointBRole: secondRole,
      description: description,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
  }

  @override
  Future<CharacterRelationship?> getById(String id) =>
      throw UnimplementedError();
  @override
  Future<CharacterRelationship?> findBetween(
          ResourceId first, ResourceId second) =>
      throw UnimplementedError();
  @override
  Future<CharacterRelationship> update(
          {required String id,
          required CharacterRelationshipType relationType,
          required String endpointARole,
          required String endpointBRole,
          required String description}) =>
      throw UnimplementedError();
  @override
  Future<void> delete(String id) => throw UnimplementedError();
  @override
  Future<int> deleteForResourcePurge(
          DatabaseExecutor txn, ResourceId resourceId) =>
      throw UnimplementedError();
  @override
  Future<CharacterRelationship> createInTransaction(DatabaseExecutor txn,
          {required ResourceId firstResourceId,
          required String firstRole,
          required ResourceId secondResourceId,
          required String secondRole,
          required CharacterRelationshipType relationType,
          String description = ''}) =>
      throw UnimplementedError();
}
