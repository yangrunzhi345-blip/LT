import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/runtime_state_history.dart';
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
    directory = await Directory.systemTemp.createTemp('lt_history_stress_');
    DatabaseService.customDbDir = directory.path;
    await DatabaseService.resetDatabase();
    repository = AdventureRepositoryImpl(getDb: () => DatabaseService.database);
    adventureId = await repository.createAdventure(
      'History stress',
      AdventureConfig(name: 'Stress'),
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

  test('1000 revisions remain cursor bounded and compareable', () async {
    for (var revision = 0; revision < 1000; revision++) {
      await repository.commitRuntimeMutation(RuntimeStateMutation(
        requestId: 'stress-$revision',
        adventureId: adventureId,
        branchId: 0,
        draft: RuntimeStateCommitDraft(
          expectedRevision: revision,
          changes: [
            RuntimeStateChangeProposal(
              entityType: RuntimeEntityType.character,
              entityId: 'protagonist',
              changeKind: RuntimeChangeKind.primary,
              operation: RuntimeChangeOperation.set,
              path: 'hp',
              value: revision,
              reason: 'stress',
            ),
          ],
          summary: 'stress $revision',
          source: RuntimeEventSource.userEdit,
          causeType: 'stress',
        ),
      ));
    }
    final page = await repository.getRuntimeTimeline(
      adventureId: adventureId,
      branchId: 0,
      limit: 30,
    );
    expect((await repository.getRuntimeHead(adventureId, 0)).revision, 1000);
    expect(page, hasLength(30));
    expect(page.first.revision, 1000);
    expect(page.last.revision, 971);

    final checkpointRows = <RuntimeStateCheckpoint>[];
    for (var revision = 1; revision <= 100; revision++) {
      checkpointRows.add(await repository.createRuntimeCheckpoint(
        RuntimeStateCheckpoint(
          id: 'stress-checkpoint-$revision',
          adventureId: adventureId,
          branchId: 0,
          revision: revision,
          name: 'R$revision',
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      ));
    }
    expect(checkpointRows, hasLength(100));
    expect(
      (await repository.getRuntimeCheckpoints(
        adventureId: adventureId,
        branchId: 0,
        limit: 30,
      )),
      hasLength(30),
    );

    final comparison = RuntimeStateComparison.fromSnapshots(
      await repository.getRuntimeStateAtRevision(
        adventureId: adventureId,
        branchId: 0,
        revision: 1,
      ),
      await repository.getRuntimeStateAtRevision(
        adventureId: adventureId,
        branchId: 0,
        revision: 1000,
      ),
    );
    expect(comparison.changeCount, 1);
    expect(comparison.diffs.single.before, 0);
    expect(comparison.diffs.single.after, 999);
  });
}
