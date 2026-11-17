part of 'adventure_repository_impl.dart';

mixin _AdventureSceneTurnStore on _AdventureRepositoryBase {
  @override
  Future<SceneDialogueCommitResult> commitSceneDialogueTurn(
      SceneDialogueCommit commit) async {
    final db = await _getDb();
    final result = await db.transaction<SceneDialogueCommitResult>((txn) async {
      final existing = await txn.query('scene_dialogue_turns',
          where: 'request_id = ?', whereArgs: [commit.requestId], limit: 1);
      if (existing.isNotEmpty) {
        final stateRows = await txn.query('game_state',
            where: 'adventure_id = ?',
            whereArgs: [commit.adventureId],
            limit: 1);
        final adventureRows = await txn.query('adventures',
            columns: ['config'],
            where: 'id = ?',
            whereArgs: [commit.adventureId],
            limit: 1);
        final configText = adventureRows.firstOrNull?['config'] as String?;
        final sceneRows = await txn.query('scene_runtime_state',
            where: 'adventure_id = ? AND branch_id = ?',
            whereArgs: [commit.adventureId, commit.branchId],
            limit: 1);
        return SceneDialogueCommitResult(
          applied: false,
          gameState: stateRows.isEmpty
              ? commit.gameState
              : GameState.fromMap(stateRows.single),
          adventureConfig: configText == null
              ? null
              : AdventureConfig.fromJson(
                  jsonDecode(configText) as Map<String, dynamic>),
          effects: commit.effects,
          // A malformed persisted row must not abort an idempotent duplicate
          // request. Fall back to the current turn's state, mirroring the
          // empty-row branch, instead of the strict SceneState.decode.
          sceneState: sceneRows.isEmpty
              ? commit.sceneState
              : (_decodeSceneStateForCommit(sceneRows.single['state_json']) ??
                  commit.sceneState),
          statusDiagnostics: commit.statusDiagnostics,
        );
      }
      Future<void> insert(Message message) async {
        await txn.insert(
            'messages',
            {
              'adventure_id': commit.adventureId,
              'role': message.isUser ? 'user' : 'assistant',
              'content': message.content,
              'reasoning_content': message.reasoningContent,
              'is_html': message.isHtml ? 1 : 0,
              'edited': message.isEdited ? 1 : 0,
              'error_type': message.errorType,
              'timestamp': message.timestamp.toIso8601String(),
              'branch_id': commit.branchId,
              'client_message_id': message.id,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      var gameState = commit.effects.applyState(commit.gameState);
      AdventureConfig? config;
      final adventureRows = await txn.query('adventures',
          columns: ['config'],
          where: 'id = ?',
          whereArgs: [commit.adventureId],
          limit: 1);
      final configText = adventureRows.firstOrNull?['config'] as String?;
      if (configText != null && configText.trim().isNotEmpty) {
        config = AdventureConfig.fromJson(
            jsonDecode(configText) as Map<String, dynamic>);
      }

      for (var index = 0; index < commit.effects.itemsGained.length; index++) {
        final item = commit.effects.itemsGained[index];
        await txn.insert('inventory_items', {
          'adventure_id': commit.adventureId,
          'item_id': 'scene_${commit.requestId}_item_$index',
          'item_type': item.type,
          'name': item.name,
          'icon': item.icon,
          'quantity': item.quantity,
          'data_json': jsonEncode(item.data),
          'owner_character_id': item.ownerCharacterId,
        });
      }

      final runtimeDraft = _mergeRuntimeDrafts(
        explicit: commit.runtimeStateDraft,
        legacy: _legacyRuntimeDraft(commit.effects, config),
      );
      await _applyRuntimeMutation(
        txn: txn,
        adventureId: commit.adventureId,
        branchId: commit.branchId,
        requestId: commit.requestId,
        gameState: gameState,
        config: config,
        draft: runtimeDraft,
        contextSnapshotId: commit.contextSnapshotId,
        sourceMessageId:
            runtimeDraft?.sourceMessageId ?? commit.assistantMessage.id,
      );
      gameState = await _applyProtagonistRuntimeState(
        txn,
        adventureId: commit.adventureId,
        branchId: commit.branchId,
        config: config,
        current: gameState,
      );

      final sceneValidation = await _applySceneStateProposal(
        txn: txn,
        commit: commit,
        config: config,
      );
      final committedSceneState = sceneValidation.state;
      if (committedSceneState?.location.trim().isNotEmpty == true) {
        gameState =
            gameState.copyWith(currentScene: committedSceneState!.location);
      }

      final additionalMessages = <Message>[];
      var levelOrdinal = 0;
      while (gameState.experience >= gameState.expToNextLevel) {
        final overflow = gameState.experience - gameState.expToNextLevel;
        final nextLevel = gameState.level + 1;
        gameState = gameState.copyWith(
          level: nextLevel,
          experience: overflow,
          hp: gameState.maxHp + 5,
          maxHp: gameState.maxHp + 5,
          mp: gameState.maxMp + 3,
          maxMp: gameState.maxMp + 3,
          baseAtk: gameState.baseAtk + 1,
          baseDef: gameState.baseDef + 1,
          baseSpeed: gameState.baseSpeed + 1,
          skillPoints: gameState.skillPoints + 2,
        );
        additionalMessages.add(Message(
          id: '${commit.requestId}-level-${levelOrdinal++}',
          content: AppEventCodec.encode(AppEvent(
            code: AppEventCode.levelUpRecovery,
            payload: {'level': nextLevel},
          )),
          isUser: false,
        ));
      }

      await insert(commit.userMessage);
      await insert(commit.assistantMessage);
      for (final message in additionalMessages) {
        await insert(message);
      }
      await txn.insert('game_state', gameState.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      if (committedSceneState case final sceneState?) {
        final storedRows = await txn.query(
          'scene_runtime_state',
          columns: const ['state_json', 'revision'],
          where: 'adventure_id = ? AND branch_id = ?',
          whereArgs: [commit.adventureId, commit.branchId],
          limit: 1,
        );
        final storedText = storedRows.firstOrNull?['state_json'] as String?;
        if (storedText != sceneState.encode()) {
          final revision =
              (storedRows.firstOrNull?['revision'] as int? ?? 0) + 1;
          await _writeSceneState(
            txn,
            commit.adventureId,
            commit.branchId,
            sceneState,
            revision,
          );
          await _writeScenePresenceProjection(
            txn,
            commit.adventureId,
            commit.branchId,
            sceneState.presentCharacterIds,
          );
        }
      }
      await txn.insert('scene_dialogue_turns', {
        'request_id': commit.requestId,
        'adventure_id': commit.adventureId,
        'branch_id': commit.branchId,
        'created_at': DateTime.now().toIso8601String(),
        'assistant_client_message_id': commit.assistantMessage.id,
        'context_snapshot_id': commit.contextSnapshotId,
        'diagnostics_json': jsonEncode({
          ...commit.diagnostics,
          if (commit.statusDiagnostics.isNotEmpty)
            'status_diagnostics': commit.statusDiagnostics,
          if (sceneValidation.diagnostics.isNotEmpty)
            // The engine already records the authorization diagnostics under
            // this key; appending the structural validator's diagnostics keeps
            // both observable instead of letting one overwrite the other.
            'ignored_scene_state_changes': [
              ...(commit.diagnostics['ignored_scene_state_changes'] as List? ??
                  const <Object?>[]),
              ...sceneValidation.diagnostics,
            ],
          if (commit.effects.diagnostics.isNotEmpty)
            'ignored_effects': commit.effects.diagnostics,
          'effect_counts': {
            'items': commit.effects.itemsGained.length,
            'affinity': commit.effects.affinityChanges.length,
            'combat_enemies': commit.effects.enemies.length,
          },
        }),
      });
      for (final candidate in commit.candidates) {
        await txn.insert(
            'scene_setting_candidates',
            {
              'id': candidate.id,
              'adventure_id': commit.adventureId,
              'branch_id': commit.branchId,
              'request_id': commit.requestId,
              'type': candidate.type,
              'content': candidate.content,
              'content_hash': candidate.contentHash,
              'status': SceneSettingCandidateStatus.pending.name,
              'created_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      return SceneDialogueCommitResult(
        applied: true,
        gameState: gameState,
        adventureConfig: config,
        additionalMessages: List.unmodifiable(additionalMessages),
        effects: commit.effects,
        sceneState: committedSceneState,
        statusDiagnostics: commit.statusDiagnostics,
      );
    });
    return result;
  }

  Future<SceneStateProposalValidation> _applySceneStateProposal({
    required Transaction txn,
    required SceneDialogueCommit commit,
    required AdventureConfig? config,
  }) async {
    final stored = await _sceneStateInTransaction(
      txn,
      commit.adventureId,
      commit.branchId,
    );
    final stateRows = await txn.query(
      'scene_runtime_state',
      columns: const ['state_json'],
      where: 'adventure_id = ? AND branch_id = ?',
      whereArgs: [commit.adventureId, commit.branchId],
      limit: 1,
    );
    final snapshot = commit.sceneState;
    final base = stateRows.isEmpty
        ? snapshot
        : snapshot == null
            ? stored
            : stored.copyWith(
                location: snapshot.location,
                time: snapshot.time,
                characterStates: snapshot.characterStates,
                unresolvedEvents: snapshot.unresolvedEvents,
                goals: snapshot.goals,
                recentChanges: snapshot.recentChanges,
              );
    if (base == null) {
      return const SceneStateProposalValidation(null, []);
    }
    if (commit.sceneStateProposal == null) {
      return SceneStateProposalValidation(base, const []);
    }
    final rows = await txn.query('adventure_runtime_entities',
        where: 'adventure_id = ? AND branch_id = ?',
        whereArgs: [commit.adventureId, commit.branchId]);
    final dead = <String>{};
    for (final row in rows) {
      if (row['entity_type'] != RuntimeEntityType.character.name) continue;
      final lifecycle = row['lifecycle_status']?.toString();
      final overlay = _decodeRuntimeOverlay(row['state_json']);
      if (lifecycle == 'dead' || overlay?['life_status'] == 'dead') {
        final id = row['entity_id']?.toString();
        if (id != null && id.isNotEmpty) dead.add(id);
      }
    }
    final known = <String>{
      'protagonist',
      for (final character in config?.supportingCharacters ?? const [])
        character.id,
      for (final character in config?.selectedCharacters ?? const [])
        character.characterId,
    };
    final memberships = await txn.query(
      'adventure_character_memberships',
      columns: const ['character_id'],
      where: 'adventure_id = ? AND branch_id = ?',
      whereArgs: [commit.adventureId, commit.branchId],
    );
    known.addAll(memberships.map((row) => row['character_id'].toString()));
    return const SceneStateProposalValidator().apply(
      current: base,
      proposal: commit.sceneStateProposal,
      knownCharacterIds: known,
      deadCharacterIds: dead,
    );
  }

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

  Future<SceneState> _sceneStateInTransaction(
    Transaction txn,
    int adventureId,
    int branchId,
  ) async {
    final rows = await txn.query(
      'scene_runtime_state',
      columns: const ['state_json'],
      where: 'adventure_id = ? AND branch_id = ?',
      whereArgs: [adventureId, branchId],
      limit: 1,
    );
    final encoded = rows.firstOrNull?['state_json'] as String?;
    return encoded == null
        ? const SceneState()
        : (SceneState.tryDecode(encoded) ?? const SceneState());
  }

  Future<void> _writeSceneState(
    Transaction txn,
    int adventureId,
    int branchId,
    SceneState state,
    int revision,
  ) async {
    await txn.insert(
      'scene_runtime_state',
      {
        'adventure_id': adventureId,
        'branch_id': branchId,
        'state_json': state.encode(),
        'schema_version': SceneState.schemaVersion,
        'revision': revision,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _writeScenePresenceProjection(
    Transaction txn,
    int adventureId,
    int branchId,
    List<String> participantIds, {
    String? actorId,
  }) async {
    final old = await txn.query(
      'scene_presence',
      columns: const ['actor_id'],
      where: 'adventure_id = ? AND branch_id = ?',
      whereArgs: [adventureId, branchId],
      limit: 1,
    );
    final participants = participantIds.toSet();
    final selectedActor = actorId ?? old.firstOrNull?['actor_id'] as String?;
    final projectedActor =
        selectedActor != null && participants.contains(selectedActor)
            ? selectedActor
            : 'protagonist';
    await txn.insert(
      'scene_presence',
      {
        'adventure_id': adventureId,
        'branch_id': branchId,
        'actor_id': projectedActor,
        'participant_ids_json': jsonEncode(participantIds),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
