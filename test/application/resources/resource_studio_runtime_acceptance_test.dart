import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resource_library/character_generation_reference.dart';
import 'package:lt_dialogue/controllers/streaming_resource_generation_controller.dart';
import 'package:lt_dialogue/domain/resources/character_relationship.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/resource_studio/application/use_cases/resource_studio_runtime.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/character_relationship_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/r01_streaming_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late _RuntimeFixture fixture;

  setUp(() async {
    fixture = await _openFixture('lt_studio_runtime_accept_');
  });

  tearDown(() async {
    await fixture.close();
  });

  test('accepts a persisted related candidate through the production runtime',
      () async {
    final candidate = await fixture.seedRelatedCandidate();

    final accepted = await fixture.runtime.acceptGeneratedCharacter(
      resourceId: candidate.resourceId,
      creationSessionId: candidate.creationSessionId,
      idempotencyKey: 'runtime-accept-1',
    );

    expect(accepted, candidate.resourceId);
    final saved = await fixture.trees.findResource(candidate.resourceId);
    expect(saved, isNotNull);
    expect(
      saved!.metadata['related_character_candidate_id'],
      'candidate_${candidate.creationSessionId}_r1',
    );
    expect(saved.metadata['related_character_candidate_revision'], 1);
    expect(
      saved.metadata['related_character_accept_creation_session_id'],
      candidate.creationSessionId,
    );
    expect(
      await fixture.relationships
          .listForResource(const ResourceId('runtime_source')),
      hasLength(1),
    );
  });

  test('repeated runtime acceptance is idempotent on the same operation',
      () async {
    final candidate = await fixture.seedRelatedCandidate();

    final first = await fixture.runtime.acceptGeneratedCharacter(
      resourceId: candidate.resourceId,
      creationSessionId: candidate.creationSessionId,
      idempotencyKey: 'runtime-accept-repeat',
    );
    final second = await fixture.runtime.acceptGeneratedCharacter(
      resourceId: candidate.resourceId,
      creationSessionId: candidate.creationSessionId,
      idempotencyKey: 'runtime-accept-repeat',
    );

    expect(second, first);
    expect(
      await fixture.relationships
          .listForResource(const ResourceId('runtime_source')),
      hasLength(1),
    );
    final rows = await (await DatabaseService.database).query(
      'resources',
      where: 'id = ?',
      whereArgs: [candidate.resourceId.value],
    );
    expect(rows, hasLength(1));
  });

  test('rejects a missing or mismatched creation session before writes',
      () async {
    final candidate = await fixture.seedRelatedCandidate();

    await expectLater(
      fixture.runtime.acceptGeneratedCharacter(
        resourceId: candidate.resourceId,
        creationSessionId: 'missing-session',
        idempotencyKey: 'runtime-missing-session',
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      fixture.runtime.acceptGeneratedCharacter(
        resourceId: const ResourceId('wrong-resource'),
        creationSessionId: candidate.creationSessionId,
        idempotencyKey: 'runtime-wrong-resource',
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      await fixture.relationships
          .listForResource(const ResourceId('runtime_source')),
      isEmpty,
    );
  });

  test('rejects a creation session without a relationship draft', () async {
    final result = await fixture.pipeline.create(
      const ResourceCreationRequest(
        resourceType: ResourceType.character,
        method: CreationMethod.manual,
        name: 'Manual character',
        idempotencyKey: 'runtime-manual',
        resourceId: 'runtime_manual',
      ),
    );
    final resourceId = result.resourceId!;

    await expectLater(
      fixture.runtime.acceptGeneratedCharacter(
        resourceId: resourceId,
        creationSessionId: result.sessionId!,
        idempotencyKey: 'runtime-no-draft',
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      await fixture.relationships
          .listForResource(const ResourceId('runtime_source')),
      isEmpty,
    );
  });

  test('rejects a stale unconfirmed blueprint revision', () async {
    final candidate = await fixture.seedRelatedCandidate();
    final latest = (await fixture.blueprints
            .findLatestBlueprint(candidate.creationSessionId))!
        .copyWith(
      blueprintId: 'runtime_blueprint_revision_2',
      revision: 2,
      status: BlueprintStatus.draft,
    );
    await fixture.blueprints.saveBlueprint(latest);

    await expectLater(
      fixture.runtime.acceptGeneratedCharacter(
        resourceId: candidate.resourceId,
        creationSessionId: candidate.creationSessionId,
        idempotencyKey: 'runtime-stale-revision',
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      await fixture.relationships
          .listForResource(const ResourceId('runtime_source')),
      isEmpty,
    );
    final saved = await fixture.trees.findResource(candidate.resourceId);
    expect(saved!.metadata['related_character_candidate_id'], isNull);
  });

  test('rejects a confirmed blueprint bound to another resource', () async {
    final candidate = await fixture.seedRelatedCandidate();
    final latest = (await fixture.blueprints
            .findLatestBlueprint(candidate.creationSessionId))!
        .copyWith(
      blueprintId: 'runtime_blueprint_wrong_resource',
      revision: 2,
      status: BlueprintStatus.confirmed,
      resourceId: const ResourceId('another-resource'),
    );
    await fixture.blueprints.saveBlueprint(latest);

    await expectLater(
      fixture.runtime.acceptGeneratedCharacter(
        resourceId: candidate.resourceId,
        creationSessionId: candidate.creationSessionId,
        idempotencyKey: 'runtime-wrong-blueprint-resource',
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      await fixture.relationships
          .listForResource(const ResourceId('runtime_source')),
      isEmpty,
    );
  });

  test('rejects a candidate when the resource tree revision is stale',
      () async {
    final candidate = await fixture.seedRelatedCandidate();
    final saved = await fixture.trees.findResource(candidate.resourceId);
    final db = await DatabaseService.database;
    await db.update(
      'resources',
      {
        'metadata_json': jsonEncode({
          ...saved!.metadata,
          'blueprint_revision': 2,
        }),
      },
      where: 'id = ?',
      whereArgs: [candidate.resourceId.value],
    );

    await expectLater(
      fixture.runtime.acceptGeneratedCharacter(
        resourceId: candidate.resourceId,
        creationSessionId: candidate.creationSessionId,
        idempotencyKey: 'runtime-stale-resource-revision',
      ),
      throwsA(isA<ResourceTreeConflictException>()),
    );
    expect(
      await fixture.relationships
          .listForResource(const ResourceId('runtime_source')),
      isEmpty,
    );
  });
}

Future<_RuntimeFixture> _openFixture(String prefix) async {
  final directory = await Directory.systemTemp.createTemp(prefix);
  DatabaseService.customDbDir = directory.path;
  await DatabaseService.resetDatabase();

  final streamFixture = R01StreamingFixture();
  final service = streamFixture.buildService(
    r01Completer('runtime acceptance body'),
  );
  final controller = StreamingResourceGenerationController(
    service: service,
    sessionRepository: streamFixture.sessionRepository,
  );
  final runtime = StreamingResourceStudioRuntime(
    controller: controller,
    sessionRepository: streamFixture.sessionRepository,
    treeRepository: streamFixture.treeRepository,
    blueprintRepository: streamFixture.blueprintRepository,
    pipeline: streamFixture.pipeline,
    gateway: const _UnusedGateway(),
  );
  return _RuntimeFixture(
    directory: directory,
    streamFixture: streamFixture,
    controller: controller,
    runtime: runtime,
  );
}

final class _RuntimeFixture {
  const _RuntimeFixture({
    required this.directory,
    required this.streamFixture,
    required this.controller,
    required this.runtime,
  });

  final Directory directory;
  final R01StreamingFixture streamFixture;
  final StreamingResourceGenerationController controller;
  final StreamingResourceStudioRuntime runtime;

  ResourceTreeRepositoryImpl get trees => streamFixture.treeRepository;
  ResourceBlueprintRepositoryImpl get blueprints =>
      streamFixture.blueprintRepository;
  ResourceCreationPipeline get pipeline => streamFixture.pipeline;
  CharacterRelationshipRepositoryImpl get relationships =>
      CharacterRelationshipRepositoryImpl(
        getDb: () => DatabaseService.database,
      );

  Future<_CandidateSetup> seedRelatedCandidate() async {
    await trees.createResourceTree(const ResourceTreeDraft(
      id: ResourceId('runtime_source'),
      type: ResourceType.character,
      name: 'Source character',
    ));
    final relationshipDraft = CharacterRelationshipDraft(
      relationship: CharacterGenerationRelationship.fromReferences([
        CharacterGenerationReference(
          sourceResourceId: const ResourceId('runtime_source'),
          relationshipType: CharacterRelationshipType.mentorStudent,
          sourceRole: 'mentor',
          generatedCharacterRole: 'student',
          description: 'A stable runtime relationship',
        ),
      ]),
    );
    final creation = await pipeline.create(ResourceCreationRequest(
      resourceType: ResourceType.character,
      method: CreationMethod.aiReference,
      name: 'Generated character',
      idempotencyKey: 'runtime-related-generation',
      referenceSource: ReferenceSource.text('Runtime acceptance source'),
      targetCharacters: 1200,
      relationshipDraft: relationshipDraft,
    ));
    final creationSessionId = creation.sessionId!;
    final blueprint = ResourceBlueprint(
      blueprintId: 'runtime_blueprint_revision_1',
      sessionId: creationSessionId,
      resourceType: ResourceType.character,
      suggestedName: 'Generated character',
      summary: 'Runtime acceptance candidate',
      sections: [
        BlueprintSection(
          id: 'sec_1',
          title: 'Profile',
          parts: [
            const BlueprintPart(
              id: 'part_1',
              sectionId: 'sec_1',
              title: 'Identity',
              generationGoal: 'Generate identity',
              estimatedLength: 300,
            ),
          ],
        ),
      ],
    );
    await blueprints.saveBlueprint(blueprint);
    final confirmation = await blueprints.confirmBlueprint(
      blueprintId: blueprint.blueprintId,
    );
    return _CandidateSetup(
      creationSessionId: creationSessionId,
      resourceId: confirmation.resourceId,
    );
  }

  Future<void> close() async {
    controller.dispose();
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }
}

final class _CandidateSetup {
  const _CandidateSetup({
    required this.creationSessionId,
    required this.resourceId,
  });

  final String creationSessionId;
  final ResourceId resourceId;
}

final class _UnusedGateway implements LlmGateway {
  const _UnusedGateway();

  @override
  bool get isConfigured => true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}
