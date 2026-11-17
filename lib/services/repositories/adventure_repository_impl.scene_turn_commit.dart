part of 'adventure_repository_impl.dart';

mixin _AdventureSceneTurnCommitStore on _AdventureRepositoryBase {
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
}
