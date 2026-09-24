import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/assembly_readiness_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_lifecycle_projection.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart'
    as revision;
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';

void main() {
  const id = ResourceId('resource-1');
  const resource = Resource(id: id, type: ResourceType.character, name: 'R');

  test('manual resource is draft', () {
    expect(
      ResourceLifecycleProjection.evaluate(resourceId: id, resource: resource)
          .state,
      ResourceLifecycleState.draft,
    );
  });

  test('missing resources fail closed', () {
    final result = ResourceLifecycleProjection.evaluate(resourceId: id);
    expect(result.state, ResourceLifecycleState.missing);
    expect(result.isConsumable, isFalse);
  });

  test('planning creation is planning', () {
    final session = ResourceCreationSession(
      sessionId: 'c',
      idempotencyKey: 'k',
      resourceType: ResourceType.character,
      method: CreationMethod.aiReference,
      name: 'R',
      status: CreationSessionStatus.planning,
      referenceSource: ReferenceSource.text('source'),
      targetCharacters: 100,
    );
    expect(
      ResourceLifecycleProjection.evaluate(
        resourceId: id,
        creationSession: session,
      ).state,
      ResourceLifecycleState.planning,
    );
  });

  test('running, failed, validating and ready states compose', () {
    final running = StreamingGenerationSession(
      sessionId: 'g',
      resourceId: id,
      blueprintId: 'b',
      status: StreamingLifecycleStatus.generatingPart,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    expect(
      ResourceLifecycleProjection.evaluate(
        resourceId: id,
        resource: resource,
        generationSession: running,
      ).state,
      ResourceLifecycleState.generating,
    );
    final failed = running.copyWith(status: StreamingLifecycleStatus.failed);
    expect(
      ResourceLifecycleProjection.evaluate(
        resourceId: id,
        resource: resource,
        generationSession: failed,
      ).state,
      ResourceLifecycleState.failed,
    );
    final validating =
        running.copyWith(status: StreamingLifecycleStatus.validating);
    expect(
      ResourceLifecycleProjection.evaluate(
        resourceId: id,
        resource: resource,
        generationSession: validating,
      ).state,
      ResourceLifecycleState.validating,
    );
    final completed =
        running.copyWith(status: StreamingLifecycleStatus.completed);
    expect(
      ResourceLifecycleProjection.evaluate(
        resourceId: id,
        resource: resource,
        generationSession: completed,
      ).state,
      ResourceLifecycleState.validating,
    );
    final readiness = AssemblyReadinessRecord(
      resourceId: id.value,
      state: ReadinessState.ready,
      assemblyRevisionId: 'assembly-1',
    );
    expect(
      ResourceLifecycleProjection.evaluate(
        resourceId: id,
        resource: resource,
        generationSession: completed,
        assemblyReadiness: readiness,
      ).state,
      ResourceLifecycleState.ready,
    );
    expect(
      ResourceLifecycleProjection.evaluate(
        resourceId: id,
        resource: resource,
        generationSession: completed,
        assemblyReadiness: readiness,
      ).isConsumable,
      isTrue,
    );
  });

  test('creation completed does not imply consumable', () {
    final creation = ResourceCreationSession(
      sessionId: 'c',
      idempotencyKey: 'k',
      resourceType: ResourceType.character,
      method: CreationMethod.aiReference,
      name: 'R',
      status: CreationSessionStatus.completed,
      referenceSource: ReferenceSource.text('source'),
      targetCharacters: 100,
    );
    final failed = StreamingGenerationSession(
      sessionId: 'g',
      resourceId: id,
      blueprintId: 'b',
      status: StreamingLifecycleStatus.failed,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final result = ResourceLifecycleProjection.evaluate(
      resourceId: id,
      resource: resource,
      creationSession: creation,
      generationSession: failed,
    );
    expect(result.state, ResourceLifecycleState.failed);
    expect(result.isConsumable, isFalse);
  });

  test('paused and recovering generation remain non-consumable', () {
    final session = StreamingGenerationSession(
      sessionId: 'g',
      resourceId: id,
      blueprintId: 'b',
      status: StreamingLifecycleStatus.paused,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    expect(
      ResourceLifecycleProjection.evaluate(
        resourceId: id,
        resource: resource,
        generationSession: session,
      ).state,
      ResourceLifecycleState.paused,
    );
    expect(
      ResourceLifecycleProjection.evaluate(
        resourceId: id,
        resource: resource,
        generationSession: session.copyWith(
          status: StreamingLifecycleStatus.recovering,
        ),
      ).state,
      ResourceLifecycleState.recovering,
    );
  });

  test('latest revision is carried by the projection', () {
    const latest = revision.ResourceRevision(
      revisionId: ResourceRevisionId('rev-1'),
      resourceId: id,
      kind: ResourceRevisionKind.latestHead,
      cause: revision.RevisionCause.manualSave,
      isHead: true,
      createdAtToken: '2026-01-01',
    );
    final result = ResourceLifecycleProjection.evaluate(
      resourceId: id,
      resource: resource,
      latestRevision: latest,
    );
    expect(result.latestRevision?.revisionId.value, 'rev-1');
  });
}
