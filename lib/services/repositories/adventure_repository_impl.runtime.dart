part of 'adventure_repository_impl.dart';

mixin _AdventureRuntimeStore on _AdventureRepositoryBase {
  @override
  Future<RuntimeStateMutationResult> commitRuntimeMutation(
      RuntimeStateMutation mutation) async {
    final db = await _getDb();
    return db.transaction((txn) async {
      final existing = await txn.query('adventure_state_commits',
          columns: ['id', 'revision'],
          where: 'adventure_id = ? AND branch_id = ? AND request_id = ?',
          whereArgs: [
            mutation.adventureId,
            mutation.branchId,
            mutation.requestId
          ],
          limit: 1);
      if (existing.isNotEmpty) {
        return RuntimeStateMutationResult(
          commitId: existing.single['id'] as String,
          revision: existing.single['revision'] as int,
        );
      }
      final adventureRows = await txn.query('adventures',
          columns: ['config'],
          where: 'id = ?',
          whereArgs: [mutation.adventureId],
          limit: 1);
      final configText = adventureRows.firstOrNull?['config'] as String?;
      final config = configText == null
          ? null
          : AdventureConfig.fromJson(
              jsonDecode(configText) as Map<String, dynamic>);
      final stateRows = await txn.query('game_state',
          where: 'adventure_id = ?',
          whereArgs: [mutation.adventureId],
          limit: 1);
      final gameState = stateRows.isEmpty
          ? GameState(adventureId: mutation.adventureId)
          : GameState.fromMap(stateRows.single);
      final applied = await _applyRuntimeMutation(
        txn: txn,
        adventureId: mutation.adventureId,
        branchId: mutation.branchId,
        requestId: mutation.requestId,
        gameState: gameState,
        config: config,
        draft: mutation.draft,
        causeRef: mutation.causeRef,
      );
      if (!applied) {
        return const RuntimeStateMutationResult(commitId: '', revision: 0);
      }
      final projected = await _applyProtagonistRuntimeState(
        txn,
        adventureId: mutation.adventureId,
        branchId: mutation.branchId,
        config: config,
        current: gameState,
      );
      await txn.insert('game_state', projected.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      final headRows = await txn.query('adventure_runtime_heads',
          columns: ['head_commit_id', 'revision'],
          where: 'adventure_id = ? AND branch_id = ?',
          whereArgs: [mutation.adventureId, mutation.branchId],
          limit: 1);
      final head = headRows.single;
      return RuntimeStateMutationResult(
        commitId: head['head_commit_id'] as String,
        revision: head['revision'] as int,
      );
    });
  }

  @override
  Future<RuntimeStateMutationResult> revertRuntimeState({
    required int adventureId,
    required int branchId,
    required int targetRevision,
    required int expectedRevision,
    required String requestId,
  }) async {
    final current = await getCurrentRuntimeState(
        adventureId: adventureId, branchId: branchId);
    final target = await getRuntimeStateAtRevision(
        adventureId: adventureId, branchId: branchId, revision: targetRevision);
    final keys = {...current.entities.keys, ...target.entities.keys};
    final changes = <RuntimeStateChangeProposal>[];
    for (final key in keys) {
      final beforeEntity = current.entities[key];
      final targetEntity = target.entities[key];
      final paths = {
        ...?beforeEntity?.overlay.keys,
        ...?targetEntity?.overlay.keys
      };
      for (final path in paths) {
        final before = beforeEntity?.overlay[path];
        final after = targetEntity?.overlay[path];
        if (_runtimeEquals(before, after)) continue;
        changes.add(RuntimeStateChangeProposal(
          entityType: beforeEntity?.entityType ?? targetEntity!.entityType,
          entityId: beforeEntity?.entityId ?? targetEntity!.entityId,
          changeKind: RuntimeChangeKind.primary,
          operation: after == null
              ? RuntimeChangeOperation.remove
              : RuntimeChangeOperation.set,
          path: path,
          value: after,
          reason: 'Revert to revision $targetRevision',
        ));
      }
    }
    return commitRuntimeMutation(RuntimeStateMutation(
      requestId: requestId,
      adventureId: adventureId,
      branchId: branchId,
      causeType: 'revert',
      causeRef: 'revision:$targetRevision',
      draft: RuntimeStateCommitDraft(
        expectedRevision: expectedRevision,
        changes: changes,
        summary: 'Revert to revision $targetRevision',
        source: RuntimeEventSource.userEdit,
        causeType: 'revert',
        allowNewEntities: true,
      ),
    ));
  }
}
