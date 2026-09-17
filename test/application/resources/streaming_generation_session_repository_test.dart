import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/streaming_generation_session_repository.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late StreamingGenerationSessionRepositoryImpl repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_gen_session_repo_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    repo = StreamingGenerationSessionRepositoryImpl(
      getDb: () => DatabaseService.database,
    );
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('StreamingGenerationSessionRepository', () {
    test('creates and retrieves a generation runtime session', () async {
      final now = DateTime.now();
      final session = StreamingGenerationSession(
        sessionId: 'gen_sess_100',
        resourceId: const ResourceId('res_100'),
        blueprintId: 'bp_100',
        creationSessionId: 'cre_100',
        status: StreamingLifecycleStatus.created,
        totalPartsCount: 5,
        createdAt: now,
        updatedAt: now,
      );

      final created = await repo.createSession(session);
      expect(created.sessionId, 'gen_sess_100');

      final fetched = await repo.findSession('gen_sess_100');
      expect(fetched, isNotNull);
      expect(fetched!.sessionId, 'gen_sess_100');
      expect(fetched.resourceId.value, 'res_100');
      expect(fetched.blueprintId, 'bp_100');
      expect(fetched.creationSessionId, 'cre_100');
      expect(fetched.status, StreamingLifecycleStatus.created);
      expect(fetched.completedPartsCount, 0);
      expect(fetched.totalPartsCount, 5);
      expect(fetched.currentPartId, isNull);
    });

    test(
        'updates status according to state machine and rejects illegal transition',
        () async {
      final now = DateTime.now();
      await repo.createSession(StreamingGenerationSession(
        sessionId: 'gen_sess_200',
        resourceId: const ResourceId('res_200'),
        blueprintId: 'bp_200',
        status: StreamingLifecycleStatus.created,
        totalPartsCount: 3,
        createdAt: now,
        updatedAt: now,
      ));

      // Valid transition: created -> planning
      await repo.updateStatus(
        'gen_sess_200',
        StreamingLifecycleStatus.planning,
      );
      var fetched = await repo.findSession('gen_sess_200');
      expect(fetched!.status, StreamingLifecycleStatus.planning);

      // Valid transition: planning -> generatingPart with active part/task
      await repo.updateStatus(
        'gen_sess_200',
        StreamingLifecycleStatus.generatingPart,
        currentPartId: 'part_1',
        currentTaskId: 'task_1',
        currentAttemptId: 'att_1',
      );
      fetched = await repo.findSession('gen_sess_200');
      expect(fetched!.status, StreamingLifecycleStatus.generatingPart);
      expect(fetched.currentPartId?.value, 'part_1');
      expect(fetched.currentTaskId, 'task_1');
      expect(fetched.currentAttemptId, 'att_1');

      // Invalid transition: generatingPart -> completed (cannot jump straight to completed)
      expect(
        () => repo.updateStatus(
          'gen_sess_200',
          StreamingLifecycleStatus.completed,
        ),
        throwsStateError,
      );
    });

    test('updates progress and lists latest session for resource', () async {
      final now = DateTime.now();
      await repo.createSession(StreamingGenerationSession(
        sessionId: 'gen_sess_300',
        resourceId: const ResourceId('res_300'),
        blueprintId: 'bp_300',
        status: StreamingLifecycleStatus.created,
        totalPartsCount: 4,
        createdAt: now,
        updatedAt: now,
      ));

      await repo.updateProgress('gen_sess_300', completedCount: 2);
      final fetched = await repo.findSession('gen_sess_300');
      expect(fetched!.completedPartsCount, 2);
      expect(fetched.totalPartsCount, 4);

      final latest = await repo.findLatestSessionForResource('res_300');
      expect(latest, isNotNull);
      expect(latest!.sessionId, 'gen_sess_300');
    });

    test(
        'rejects duplicate sessions and invalid progress without replacing data',
        () async {
      final now = DateTime.now();
      final session = StreamingGenerationSession(
        sessionId: 'gen_sess_invariants',
        resourceId: const ResourceId('res_invariants'),
        blueprintId: 'bp_invariants',
        status: StreamingLifecycleStatus.created,
        totalPartsCount: 2,
        createdAt: now,
        updatedAt: now,
      );
      await repo.createSession(session);

      await expectLater(repo.createSession(session), throwsA(isA<Exception>()));
      await expectLater(
        repo.createSession(StreamingGenerationSession(
          sessionId: 'gen_sess_same_resource',
          resourceId: const ResourceId('res_invariants'),
          blueprintId: 'bp_same_resource',
          status: StreamingLifecycleStatus.created,
          totalPartsCount: 1,
          createdAt: now,
          updatedAt: now,
        )),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        repo.updateProgress(
          session.sessionId,
          completedCount: 3,
        ),
        throwsArgumentError,
      );

      final persisted = await repo.findSession(session.sessionId);
      expect(persisted, isNotNull);
      expect(persisted!.status, StreamingLifecycleStatus.created);
      expect(persisted.completedPartsCount, 0);
      expect(persisted.totalPartsCount, 2);
    });

    test('detects interrupted sessions and marks them recovering', () async {
      final now = DateTime.now();
      // Completed session
      await repo.createSession(StreamingGenerationSession(
        sessionId: 'sess_done',
        resourceId: const ResourceId('res_400'),
        blueprintId: 'bp_400',
        status: StreamingLifecycleStatus.completed,
        createdAt: now,
        updatedAt: now,
      ));

      // In-flight session (generating_part)
      await repo.createSession(StreamingGenerationSession(
        sessionId: 'sess_interrupted',
        resourceId: const ResourceId('res_400'),
        blueprintId: 'bp_400',
        status: StreamingLifecycleStatus.generatingPart,
        currentPartId: const PartId('part_in_flight'),
        createdAt: now,
        updatedAt: now,
      ));

      final interrupted = await repo.findInterruptedSessions();
      expect(interrupted.map((s) => s.sessionId), contains('sess_interrupted'));
      expect(interrupted.map((s) => s.sessionId), isNot(contains('sess_done')));

      await repo.markSessionRecovering('sess_interrupted');
      final recovered = await repo.findSession('sess_interrupted');
      expect(recovered!.status, StreamingLifecycleStatus.recovering);
    });
  });
}
