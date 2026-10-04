import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_lifecycle_projection.dart';
import 'package:lt_dialogue/application/resources/resource_lifecycle_reconciler.dart';
import 'package:lt_dialogue/application/resources/streaming_generation_session_repository.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_repository.dart'
    hide ResourceCreationSession;
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:sqflite/sqflite.dart';

import '../../helpers/phase10_fixture.dart';

/// Concrete database failure — [DatabaseException] itself is abstract.
final class _FakeDatabaseException extends DatabaseException {
  _FakeDatabaseException() : super('database is locked');

  @override
  int? getResultCode() => null;

  @override
  Object? get result => null;
}

/// A tree reader whose [findResource] always throws, modelling a stored
/// resource whose rows cannot be projected.
final class _ThrowingTreeReader implements ResourceTreeReader {
  _ThrowingTreeReader(this.error);

  final Object error;

  @override
  Future<Resource?> findResource(ResourceId id) async => throw error;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used');
}

final class _NoCreationReader implements ResourceCreationSessionReader {
  @override
  Future<ResourceCreationSession?> latestCreationSessionForResource(
    ResourceId id,
  ) async =>
      null;
}

final class _NoGenerationRepository
    implements IStreamingGenerationSessionRepository {
  @override
  Future<StreamingGenerationSession?> findLatestSessionForResource(
    String resourceId,
  ) async =>
      null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used');
}

void main() {
  late Phase10Fixture fixture;

  setUp(() async {
    fixture = Phase10Fixture();
    await fixture.setUp(prefix: 'lt_reconciler_iso_');
  });

  tearDown(() => fixture.tearDown());

  ResourceLifecycleReconciler reconcilerWith(Object readError) =>
      ResourceLifecycleReconciler(
        projection: ResourceLifecycleProjection(
          resourceReader: _ThrowingTreeReader(readError),
          creationReader: _NoCreationReader(),
          generationReader: _NoGenerationRepository(),
          revisionReader: fixture.revisionRepository,
          readinessReader: fixture.readinessRepository,
        ),
        readiness: fixture.coordinator,
      );

  test('a per-resource projection fault yields a terminal failed snapshot',
      () async {
    final reconciler = reconcilerWith(
      const ResourceTreeCorruptedException('损坏的元数据'),
    );

    final result = await reconciler.read(const ResourceId('res_corrupt'));

    expect(result.state, ResourceLifecycleState.failed);
    expect(result.isConsumable, isFalse);
    expect(result.exists, isFalse);
  });

  test('a database-level fault still propagates', () async {
    final reconciler = reconcilerWith(_FakeDatabaseException());

    expect(
      () => reconciler.read(const ResourceId('res_locked')),
      throwsA(isA<DatabaseException>()),
    );
  });
}
