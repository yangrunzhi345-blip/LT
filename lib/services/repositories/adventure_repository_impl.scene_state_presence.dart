part of 'adventure_repository_impl.dart';

mixin _AdventureScenePresenceStore on _AdventureRepositoryBase {
  @override
  Future<ScenePresence?> getScenePresence(int adventureId, int branchId) async {
    final db = await _getDb();
    final rows = await db.query(
      'scene_presence',
      where: 'adventure_id = ? AND branch_id = ?',
      whereArgs: [adventureId, branchId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final actorId =
        row['actor_id'] is String ? (row['actor_id'] as String).trim() : null;
    final stateRows = await db.query(
      'scene_runtime_state',
      columns: const ['state_json'],
      where: 'adventure_id = ? AND branch_id = ?',
      whereArgs: [adventureId, branchId],
      limit: 1,
    );
    final encoded = stateRows.firstOrNull?['state_json'] as String?;
    final state = encoded == null ? null : SceneState.tryDecode(encoded);
    if (encoded != null && state == null) {
      debugPrint('[AdventureRepository] skipping malformed scene state row '
          'adventure=$adventureId branch=$branchId');
      return null;
    }
    final ids = state?.presentCharacterIds ?? const ['protagonist'];
    return ScenePresence(
        adventureId: adventureId,
        branchId: branchId,
        actorId:
            actorId != null && ids.contains(actorId) ? actorId : 'protagonist',
        participantIds: ids);
  }

  @override
  Future<void> saveScenePresence(ScenePresence presence) async {
    final db = await _getDb();
    await db.transaction((txn) async {
      final stateRows = await txn.query(
        'scene_runtime_state',
        columns: const ['state_json'],
        where: 'adventure_id = ? AND branch_id = ?',
        whereArgs: [presence.adventureId, presence.branchId],
        limit: 1,
      );
      final encoded = stateRows.firstOrNull?['state_json'] as String?;
      final authoritativeParticipants = encoded == null
          ? const ['protagonist']
          : (SceneState.tryDecode(encoded)?.presentCharacterIds ??
              const ['protagonist']);
      await _writeScenePresenceProjection(
        txn,
        presence.adventureId,
        presence.branchId,
        authoritativeParticipants,
        actorId: presence.actorId,
      );
    });
  }

  @override
  Future<SceneState?> getSceneState(int adventureId, int branchId) async {
    final db = await _getDb();
    final rows = await db.query(
      'scene_runtime_state',
      where: 'adventure_id = ? AND branch_id = ?',
      whereArgs: [adventureId, branchId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    // scene_runtime_state is persisted state: tolerate malformed rows by
    // reporting "no state" so callers bootstrap a fresh state instead of
    // letting one bad row collapse scene context construction.
    final row = rows.single;
    final text = row['state_json'] is String
        ? row['state_json'] as String
        : JsonValueReader.stringScalar(row['state_json']);
    if (text == null) {
      debugPrint('[AdventureRepository] skipping malformed scene state row '
          'adventure=$adventureId branch=$branchId');
      return null;
    }
    final state = SceneState.tryDecode(text);
    if (state == null) {
      debugPrint('[AdventureRepository] skipping malformed scene state row '
          'adventure=$adventureId branch=$branchId');
    }
    return state;
  }

  @override
  Future<int> getSceneStateRevision(int adventureId, int branchId) async {
    final db = await _getDb();
    final rows = await db.query(
      'scene_runtime_state',
      columns: const ['revision'],
      where: 'adventure_id = ? AND branch_id = ?',
      whereArgs: [adventureId, branchId],
      limit: 1,
    );
    return rows.firstOrNull?['revision'] as int? ?? 0;
  }

  @override
  Future<void> saveSceneState(
    int adventureId,
    int branchId,
    SceneState state,
  ) async {
    final db = await _getDb();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'scene_runtime_state',
        columns: const ['revision'],
        where: 'adventure_id = ? AND branch_id = ?',
        whereArgs: [adventureId, branchId],
        limit: 1,
      );
      final revision = (rows.firstOrNull?['revision'] as int? ?? 0) + 1;
      await _writeSceneState(txn, adventureId, branchId, state, revision);
      await _writeScenePresenceProjection(
        txn,
        adventureId,
        branchId,
        state.presentCharacterIds,
      );
    });
  }

  @override
  Future<ScenePresenceMutationResult> applyScenePresenceMutation(
    ScenePresenceMutation mutation,
  ) async {
    final db = await _getDb();
    return db.transaction((txn) async {
      final duplicate = await txn.query(
        'scene_presence_mutation_requests',
        columns: const ['revision'],
        where: 'adventure_id = ? AND branch_id = ? AND request_id = ?',
        whereArgs: [
          mutation.adventureId,
          mutation.branchId,
          mutation.requestId,
        ],
        limit: 1,
      );
      final current = await _sceneStateInTransaction(
        txn,
        mutation.adventureId,
        mutation.branchId,
      );
      final stateRows = await txn.query(
        'scene_runtime_state',
        columns: const ['revision'],
        where: 'adventure_id = ? AND branch_id = ?',
        whereArgs: [mutation.adventureId, mutation.branchId],
        limit: 1,
      );
      final revision = stateRows.firstOrNull?['revision'] as int? ?? 0;
      if (duplicate.isNotEmpty) {
        return ScenePresenceMutationResult(
          status: SceneMutationStatus.duplicate,
          state: current,
          revision: revision,
        );
      }
      if (revision != mutation.expectedRevision) {
        return ScenePresenceMutationResult(
          status: SceneMutationStatus.revisionConflict,
          state: current,
          revision: revision,
        );
      }

      final adventureRows = await txn.query(
        'adventures',
        columns: const ['config'],
        where: 'id = ?',
        whereArgs: [mutation.adventureId],
        limit: 1,
      );
      final configText = adventureRows.firstOrNull?['config'] as String?;
      final config = configText == null
          ? null
          : AdventureConfig.fromJson(
              jsonDecode(configText) as Map<String, dynamic>,
            );
      final attaching = mutation.attachCharacter;
      final attachedId = attaching == null
          ? null
          : AdventureCharacterIdentity.effectiveId(attaching);
      if (attaching != null &&
          (attachedId?.isEmpty != false || attaching.isProtagonist)) {
        return ScenePresenceMutationResult(
          status: SceneMutationStatus.rejected,
          state: current,
          revision: revision,
          diagnostics: const ['scene_membership:invalid_identity'],
        );
      }
      if (attachedId != null) {
        final startupIds = <String>{
          for (final character in config?.selectedCharacters ?? const [])
            AdventureCharacterIdentity.effectiveId(character),
          for (final character in config?.supportingCharacters ?? const [])
            character.id.trim(),
        };
        if (startupIds.contains(attachedId)) {
          return ScenePresenceMutationResult(
            status: SceneMutationStatus.alreadyAttached,
            state: current,
            revision: revision,
          );
        }
        final existingMembership = await txn.query(
          'adventure_character_memberships',
          columns: const ['character_id'],
          where: 'adventure_id = ? AND branch_id = ? AND character_id = ?',
          whereArgs: [mutation.adventureId, mutation.branchId, attachedId],
          limit: 1,
        );
        if (existingMembership.isNotEmpty) {
          return ScenePresenceMutationResult(
            status: SceneMutationStatus.alreadyAttached,
            state: current,
            revision: revision,
          );
        }
      }
      final runtimeRows = await txn.query(
        'adventure_runtime_entities',
        columns: const ['entity_id', 'lifecycle_status', 'state_json'],
        where: 'adventure_id = ? AND branch_id = ? AND entity_type = ?',
        whereArgs: [
          mutation.adventureId,
          mutation.branchId,
          RuntimeEntityType.character.name,
        ],
      );
      final dead = <String>{};
      for (final row in runtimeRows) {
        final overlay = _decodeRuntimeOverlay(row['state_json']);
        if (row['lifecycle_status'] == 'dead' ||
            overlay?['life_status'] == 'dead') {
          dead.add(row['entity_id'].toString());
        }
      }
      final known = <String>{
        'protagonist',
        for (final character in config?.supportingCharacters ?? const [])
          character.id,
        for (final character in config?.selectedCharacters ?? const [])
          if (character.characterId.trim().isNotEmpty)
            character.characterId.trim(),
        if (attachedId != null) attachedId,
      };
      final memberships = await txn.query(
        'adventure_character_memberships',
        columns: const ['character_id'],
        where: 'adventure_id = ? AND branch_id = ?',
        whereArgs: [mutation.adventureId, mutation.branchId],
      );
      known.addAll(memberships.map((row) => row['character_id'].toString()));
      final validation = const SceneStateProposalValidator().apply(
        current: current,
        proposal: SceneStateChangeProposal(
          charactersEnter: mutation.charactersEnter,
          charactersLeave: mutation.charactersLeave,
        ),
        knownCharacterIds: known,
        deadCharacterIds: dead,
      );
      final diagnostics = validation.diagnostics;
      if (diagnostics.isNotEmpty) {
        return ScenePresenceMutationResult(
          status: SceneMutationStatus.rejected,
          state: current,
          revision: revision,
          diagnostics: diagnostics,
        );
      }
      if (attaching != null) {
        final now = DateTime.now().toIso8601String();
        await txn.insert('adventure_character_memberships', {
          'adventure_id': mutation.adventureId,
          'branch_id': mutation.branchId,
          'character_id': attachedId,
          'snapshot_json': jsonEncode(attaching.toJson()),
          'request_id': mutation.requestId,
          'attached_at': now,
          'updated_at': now,
        });
        await txn.insert(
          'adventure_runtime_entities',
          {
            'adventure_id': mutation.adventureId,
            'branch_id': mutation.branchId,
            'entity_type': RuntimeEntityType.character.name,
            'entity_id': attachedId,
            'state_json': '{}',
            'lifecycle_status': 'active',
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await txn.insert(
          'adventure_runtime_heads',
          {
            'adventure_id': mutation.adventureId,
            'branch_id': mutation.branchId,
            'revision': 0,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      final next = validation.state!;
      final requestedActor = mutation.actorId;
      final present = next.presentCharacterIds.toSet();
      final actorId = requestedActor != null &&
              present.contains(requestedActor) &&
              !dead.contains(requestedActor)
          ? requestedActor
          : 'protagonist';
      final sceneChanged = next.encode() != current.encode();
      final nextRevision = sceneChanged ? revision + 1 : revision;
      if (sceneChanged) {
        await _writeSceneState(
          txn,
          mutation.adventureId,
          mutation.branchId,
          next,
          nextRevision,
        );
      }
      await _writeScenePresenceProjection(
        txn,
        mutation.adventureId,
        mutation.branchId,
        next.presentCharacterIds,
        actorId: actorId,
      );
      await txn.insert('scene_presence_mutation_requests', {
        'adventure_id': mutation.adventureId,
        'branch_id': mutation.branchId,
        'request_id': mutation.requestId,
        'source': mutation.source.name,
        'revision': nextRevision,
        'created_at': DateTime.now().toIso8601String(),
      });
      return ScenePresenceMutationResult(
        status: SceneMutationStatus.applied,
        state: next,
        revision: nextRevision,
        diagnostics: diagnostics,
      );
    });
  }

  @override
  Future<List<AdventureSelectedCharacter>> getAdventureCharacterMemberships(
    int adventureId,
    int branchId,
  ) async {
    final db = await _getDb();
    final rows = await db.query(
      'adventure_character_memberships',
      columns: const ['snapshot_json'],
      where: 'adventure_id = ? AND branch_id = ?',
      whereArgs: [adventureId, branchId],
      orderBy: 'attached_at ASC',
    );
    final characters = <AdventureSelectedCharacter>[];
    for (final row in rows) {
      final encoded = row['snapshot_json'];
      if (encoded is! String) continue;
      try {
        characters.add(AdventureSelectedCharacter.fromJson(
          Map<String, dynamic>.from(jsonDecode(encoded) as Map),
        ));
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    return List.unmodifiable(characters);
  }
}
