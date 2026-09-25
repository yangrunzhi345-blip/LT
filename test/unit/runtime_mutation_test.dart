import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory directory;
  late AdventureRepositoryImpl repository;
  late int adventureId;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lt_mutation_test_');
    DatabaseService.customDbDir = directory.path;
    await DatabaseService.resetDatabase();
    repository = AdventureRepositoryImpl(getDb: () => DatabaseService.database);
    adventureId = await repository.createAdventure(
      'Mutation test',
      AdventureConfig(name: 'Test'),
    );
    await repository.seedRuntimeEntity(
      adventureId: adventureId,
      branchId: 0,
      entityType: RuntimeEntityType.character,
      entityId: 'protagonist',
    );
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('user mutation uses CAS and revert creates a new append-only revision',
      () async {
    final first = await repository.commitRuntimeMutation(RuntimeStateMutation(
      requestId: 'user-1',
      adventureId: adventureId,
      branchId: 0,
      draft: const RuntimeStateCommitDraft(
        expectedRevision: 0,
        changes: [
          RuntimeStateChangeProposal(
            entityType: RuntimeEntityType.character,
            entityId: 'protagonist',
            changeKind: RuntimeChangeKind.primary,
            operation: RuntimeChangeOperation.set,
            path: 'hp',
            value: 10,
            reason: 'user edit',
          ),
        ],
        summary: 'Set HP',
        source: RuntimeEventSource.userEdit,
        causeType: 'user_edit',
      ),
    ));
    expect(first.revision, 1);
    final stateAfterFirst = await repository.getGameState(adventureId);
    expect(stateAfterFirst?.hp, 10);

    await expectLater(
        repository.commitRuntimeMutation(RuntimeStateMutation(
          requestId: 'stale',
          adventureId: adventureId,
          branchId: 0,
          draft: const RuntimeStateCommitDraft(
            expectedRevision: 0,
            changes: [
              RuntimeStateChangeProposal(
                entityType: RuntimeEntityType.character,
                entityId: 'protagonist',
                changeKind: RuntimeChangeKind.primary,
                operation: RuntimeChangeOperation.set,
                path: 'hp',
                value: 30,
                reason: 'stale edit',
              ),
            ],
            summary: 'stale',
          ),
        )),
        throwsA(isA<RuntimeHeadConflict>()));

    final second = await repository.commitRuntimeMutation(RuntimeStateMutation(
      requestId: 'user-2',
      adventureId: adventureId,
      branchId: 0,
      draft: const RuntimeStateCommitDraft(
        expectedRevision: 1,
        changes: [
          RuntimeStateChangeProposal(
            entityType: RuntimeEntityType.character,
            entityId: 'protagonist',
            changeKind: RuntimeChangeKind.primary,
            operation: RuntimeChangeOperation.set,
            path: 'hp',
            value: 20,
            reason: 'user edit',
          ),
        ],
        summary: 'Set HP again',
        source: RuntimeEventSource.userEdit,
        causeType: 'user_edit',
      ),
    ));
    expect(second.revision, 2);

    final reverted = await repository.revertRuntimeState(
      adventureId: adventureId,
      branchId: 0,
      targetRevision: 1,
      expectedRevision: 2,
      requestId: 'revert-1',
    );
    expect(reverted.revision, 3);
    expect(
        (await repository.getCurrentRuntimeState(
          adventureId: adventureId,
          branchId: 0,
        ))
            .entities['character:protagonist']
            ?.overlay['hp'],
        10);
    expect((await repository.getGameState(adventureId))?.hp, 10);

    final timeline = await repository.getRuntimeTimeline(
      adventureId: adventureId,
      branchId: 0,
    );
    expect(timeline.map((entry) => entry.revision), [3, 2, 1]);
    final db = await DatabaseService.database;
    final rows = await db.query('adventure_state_commits',
        where: 'adventure_id = ?', whereArgs: [adventureId]);
    expect(rows.map((row) => row['cause_type']), contains('revert'));
    expect(
        (await db.query('messages',
            where: 'adventure_id = ?', whereArgs: [adventureId])),
        isEmpty);
    expect(
        (await db.query('scene_dialogue_turns',
            where: 'adventure_id = ?', whereArgs: [adventureId])),
        isEmpty);
  });
}
