part of 'adventure_repository_impl.dart';

mixin _AdventureRuntimeMutationStore on _AdventureRepositoryBase {
  @override
  RuntimeStateCommitDraft? _mergeRuntimeDrafts({
    required RuntimeStateCommitDraft? explicit,
    required RuntimeStateCommitDraft? legacy,
  }) {
    if (explicit == null) return legacy;
    if (legacy == null) return explicit;
    // The explicit draft is the canonical response protocol. Legacy effects
    // are a compatibility projection, so they must not re-apply the same
    // entity/path or make the validator reject the whole atomic turn.
    final explicitPaths = <String>{
      for (final change in explicit.changes)
        '${change.entityType.name}:${change.entityId}:${RuntimeStateSchemaRegistry.canonicalPath(change.entityType, change.path)}',
    };
    return RuntimeStateCommitDraft(
      expectedRevision: explicit.expectedRevision,
      changes: List.unmodifiable([
        ...explicit.changes,
        ...legacy.changes.where(
          (change) => !explicitPaths.contains(
            '${change.entityType.name}:${change.entityId}:${RuntimeStateSchemaRegistry.canonicalPath(change.entityType, change.path)}',
          ),
        ),
      ]),
      summary: explicit.summary.isNotEmpty ? explicit.summary : legacy.summary,
      contextSnapshotId: explicit.contextSnapshotId ?? legacy.contextSnapshotId,
      sourceMessageId: explicit.sourceMessageId ?? legacy.sourceMessageId,
    );
  }

  @override
  RuntimeStateCommitDraft? _legacyRuntimeDraft(
    SceneDialogueEffects effects,
    AdventureConfig? config,
  ) {
    if (config == null ||
        (effects.affinityChanges.isEmpty && effects.deadCharacters.isEmpty)) {
      return null;
    }
    final byName = {
      for (final item in config.supportingCharacters) item.name: item
    };
    final changes = <RuntimeStateChangeProposal>[];
    for (final entry in effects.affinityChanges.entries) {
      final character = byName[entry.key];
      if (character == null) continue;
      changes.add(RuntimeStateChangeProposal(
        entityType: RuntimeEntityType.character,
        entityId: character.id,
        changeKind: RuntimeChangeKind.primary,
        operation: RuntimeChangeOperation.increment,
        path: 'affinity',
        value: entry.value,
        reason: 'Legacy affinity_change for ${character.name}',
      ));
    }
    for (final name in effects.deadCharacters) {
      final character = byName[name];
      if (character == null) continue;
      changes.add(RuntimeStateChangeProposal(
        entityType: RuntimeEntityType.character,
        entityId: character.id,
        changeKind: RuntimeChangeKind.primary,
        operation: RuntimeChangeOperation.set,
        path: 'life_status',
        value: 'dead',
        reason: 'Legacy character_dead for ${character.name}',
      ));
    }
    if (changes.isEmpty) return null;
    return RuntimeStateCommitDraft(
      expectedRevision: -1,
      changes: List.unmodifiable(changes),
      summary: 'Legacy narrative state effects',
    );
  }

  @override
  Future<bool> _applyRuntimeMutation({
    required Transaction txn,
    required int adventureId,
    required int branchId,
    required String requestId,
    required GameState gameState,
    required AdventureConfig? config,
    required RuntimeStateCommitDraft? draft,
    String? contextSnapshotId,
    String? sourceMessageId,
    String? causeRef,
  }) async {
    if (draft == null || draft.changes.isEmpty) return false;
    final acceptedChanges = const RuntimeStateValidator().accept(
      draft.changes,
      config: config,
    );
    if (acceptedChanges.isEmpty) return false;
    final headRows = await txn.query('adventure_runtime_heads',
        where: 'adventure_id = ? AND branch_id = ?',
        whereArgs: [adventureId, branchId],
        limit: 1);
    final currentRevision =
        headRows.isEmpty ? 0 : headRows.single['revision'] as int;
    if (draft.expectedRevision >= 0 &&
        draft.expectedRevision != currentRevision) {
      throw RuntimeHeadConflict(draft.expectedRevision, currentRevision);
    }
    final knownCharacterIds = <String>{
      for (final character in config?.supportingCharacters ?? const [])
        character.id,
      for (final character in config?.selectedCharacters ?? const [])
        character.characterId,
      if (config != null)
        config.protagonistCharacter?.characterId ?? 'protagonist',
      'protagonist',
    };
    final states = <String, Map<String, Object?>>{};
    final lifecycles = <String, String>{};
    final valid = <(RuntimeStateChangeProposal, Object?, Object?)>[];
    final touchedPaths = <String>{};
    // Range authority for `custom_attributes.*` increments: the frozen
    // AdventureConfig declares the bounds, so an increment can never push a
    // monitor outside its definition.
    final trackedRegistry = AdventureTrackedStateRegistry.fromConfig(config);
    for (final proposal in acceptedChanges) {
      final key = '${proposal.entityType.name}:${proposal.entityId}';
      final conflictKey = '$key:${proposal.path}';
      // Duplicate paths have already been rejected by RuntimeStateValidator.
      touchedPaths.add(conflictKey);
      final entityRows = await txn.query('adventure_runtime_entities',
          where:
              'adventure_id = ? AND branch_id = ? AND entity_type = ? AND entity_id = ?',
          whereArgs: [
            adventureId,
            branchId,
            proposal.entityType.name,
            proposal.entityId
          ],
          limit: 1);
      final existsInRuntime = entityRows.isNotEmpty;
      if (!existsInRuntime && draft.allowNewEntities) {
        // Revert may recreate an entity that existed at the target revision.
      } else if (!existsInRuntime &&
          proposal.entityType == RuntimeEntityType.character &&
          !knownCharacterIds.contains(proposal.entityId)) {
        continue;
      } else if (!existsInRuntime &&
          proposal.entityType != RuntimeEntityType.character) {
        // Non-character source identities need an explicit, user-confirmed seed
        // before narrative output may alter them.
        continue;
      }
      final state = states.putIfAbsent(key, () {
        if (entityRows.isEmpty) return <String, Object?>{};
        // Reuse the tolerant overlay decoder: a corrupt persisted row must not
        // abort an otherwise valid runtime commit. The new change applies from
        // an empty baseline and heals the row on write.
        final overlay = _decodeRuntimeOverlay(entityRows.single['state_json']);
        if (overlay == null) {
          debugPrint(
              '[AdventureRepository] skipping malformed runtime entity state '
              'during commit entity=${proposal.entityType.name}:${proposal.entityId}');
          return <String, Object?>{};
        }
        return overlay;
      });
      lifecycles.putIfAbsent(
          key,
          () => entityRows.isEmpty
              ? 'active'
              : JsonValueReader.stringScalar(
                      entityRows.single['lifecycle_status']) ??
                  'active');
      final baselineAffinity = proposal.path == 'affinity'
          ? config?.supportingCharacters
              .where((character) => character.id == proposal.entityId)
              .firstOrNull
              ?.affinity
          : null;
      final baselineCustomValue = _baselineCustomAttributeValue(
        config,
        proposal.entityId,
        proposal.path,
      );
      final baselineGameValue = _baselineGameStateValue(
        gameState,
        config,
        proposal.entityId,
        proposal.path,
      );
      final before = state[proposal.path] ??
          baselineAffinity ??
          baselineCustomValue ??
          baselineGameValue;
      final customAttributeId =
          RuntimeStateChangeProposal.customAttributeIdFromPath(proposal.path);
      final trackedDefinition = customAttributeId == null
          ? null
          : trackedRegistry
              .find(proposal.entityType, proposal.entityId, customAttributeId)
              ?.definition;
      final schemaDefinition = RuntimeStateSchemaRegistry.find(proposal.path);
      final after = _applyRuntimeOperation(
        before,
        proposal,
        minimum: trackedDefinition?.minimum ?? schemaDefinition?.minimum,
        maximum: trackedDefinition?.maximum ?? schemaDefinition?.maximum,
      );
      if (_runtimeEquals(before, after)) continue;
      if (after == null) {
        state.remove(proposal.path);
      } else {
        state[proposal.path] = after;
      }
      if (proposal.path == 'life_status' && after == 'dead') {
        lifecycles[key] = 'dead';
      }
      if (proposal.path == 'lifecycle_status' && after is String) {
        lifecycles[key] = after;
      }
      valid.add((proposal, before, after));
    }
    if (valid.isEmpty) return false;
    final now = DateTime.now().toIso8601String();
    final revision = currentRevision + 1;
    final commitId = 'runtime-$requestId';
    final parentCommitId =
        headRows.isEmpty ? null : headRows.single['head_commit_id'] as String?;
    await txn.insert('adventure_state_commits', {
      'id': commitId,
      'adventure_id': adventureId,
      'branch_id': branchId,
      'request_id': requestId,
      'parent_commit_id': parentCommitId,
      'revision': revision,
      'context_snapshot_id': draft.contextSnapshotId ?? contextSnapshotId,
      'summary': draft.summary,
      'cause_type': draft.causeType,
      'cause_ref': causeRef ?? draft.sourceMessageId,
      'created_at': now,
    });
    for (var index = 0; index < valid.length; index++) {
      final (proposal, before, after) = valid[index];
      final event = RuntimeStateEvent(
        eventId: '$commitId-event-$index',
        eventTypeId: runtimeEventTypeFor(proposal.entityType, proposal.path),
        adventureId: adventureId,
        branchId: branchId,
        commitId: commitId,
        revision: revision,
        occurredAt: DateTime.parse(now),
        source: draft.source,
        importance: proposal.changeKind == RuntimeChangeKind.derived
            ? RuntimeEventImportance.minor
            : RuntimeEventImportance.normal,
        visibility: RuntimeEventVisibility.user,
        sourceMessageId: draft.sourceMessageId ?? sourceMessageId,
        parameters: {
          'entity_type': proposal.entityType.name,
          'entity_id': proposal.entityId,
          'path': proposal.path,
          'before': before,
          'after': after,
        },
      );
      await txn.insert('adventure_state_changes', {
        'id': '$commitId-$index',
        'commit_id': commitId,
        'change_index': index,
        'entity_type': proposal.entityType.name,
        'entity_id': proposal.entityId,
        'change_kind': proposal.changeKind.name,
        'operation': proposal.operation.name,
        'path': proposal.path,
        'before_json': jsonEncode(before),
        'after_json': jsonEncode(after),
        'reason': proposal.reason,
        'provenance_json': jsonEncode({
          'request_id': requestId,
          'event': event.toJson(),
        }),
      });
    }
    for (final entry in states.entries) {
      final parts = entry.key.split(':');
      await txn.insert(
          'adventure_runtime_entities',
          {
            'adventure_id': adventureId,
            'branch_id': branchId,
            'entity_type': parts.first,
            'entity_id': parts.sublist(1).join(':'),
            'state_json': jsonEncode(entry.value),
            'lifecycle_status': lifecycles[entry.key],
            'last_commit_id': commitId,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await txn.insert(
        'adventure_runtime_heads',
        {
          'adventure_id': adventureId,
          'branch_id': branchId,
          'revision': revision,
          'head_commit_id': commitId,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  @override
  Future<GameState> _applyProtagonistRuntimeState(
    Transaction txn, {
    required int adventureId,
    required int branchId,
    required AdventureConfig? config,
    required GameState current,
  }) async {
    final protagonistId =
        config?.protagonistCharacter?.characterId ?? 'protagonist';
    var rows = await txn.query(
      'adventure_runtime_entities',
      where: 'adventure_id = ? AND branch_id = ? AND entity_type = ? AND '
          'entity_id = ?',
      whereArgs: [
        adventureId,
        branchId,
        RuntimeEntityType.character.name,
        protagonistId,
      ],
      limit: 1,
    );
    if (rows.isEmpty && protagonistId != 'protagonist') {
      rows = await txn.query(
        'adventure_runtime_entities',
        where: 'adventure_id = ? AND branch_id = ? AND entity_type = ? AND '
            'entity_id = ?',
        whereArgs: [
          adventureId,
          branchId,
          RuntimeEntityType.character.name,
          'protagonist',
        ],
        limit: 1,
      );
    }
    if (rows.isEmpty) return current;
    final overlay = _decodeRuntimeOverlay(rows.single['state_json']);
    if (overlay == null || overlay.isEmpty) return current;
    int value(String key, int fallback) =>
        (overlay[key] as num?)?.toInt() ?? fallback;
    return current.copyWith(
      hp: value('hp', current.hp).clamp(0, current.maxHp),
      mp: value('mp', current.mp).clamp(0, current.maxMp),
      energy: value('energy', current.energy).clamp(0, current.maxEnergy),
      level: value('level', current.level).clamp(1, 9999),
      experience: value('experience', current.experience).clamp(0, 999999999),
      baseAtk: value('base_atk', current.baseAtk).clamp(0, 999999),
      baseDef: value('base_def', current.baseDef).clamp(0, 999999),
      baseSpeed: value('base_speed', current.baseSpeed).clamp(0, 999999),
    );
  }

  Object? _applyRuntimeOperation(
    Object? before,
    RuntimeStateChangeProposal change, {
    num? minimum,
    num? maximum,
  }) {
    final value = change.value;
    final Object? result;
    if (change.operation == RuntimeChangeOperation.increment &&
        value is num &&
        const {
          'hp',
          'mp',
          'energy',
          'experience',
          'level',
          'base_atk',
          'base_def',
          'base_speed',
        }.contains(change.path)) {
      final current = before is num
          ? before
          : const {'hp', 'mp', 'energy'}.contains(change.path)
              ? 100
              : change.path == 'level'
                  ? 1
                  : 0;
      final next = current + value;
      result = switch (change.path) {
        'hp' || 'mp' || 'energy' => next.clamp(0, 999999),
        'experience' => next.clamp(0, 999999999),
        'level' => next.clamp(1, 9999),
        'base_atk' || 'base_def' || 'base_speed' => next.clamp(0, 999999),
        _ => next,
      };
    } else {
      result = switch (change.operation) {
        RuntimeChangeOperation.set => change.value,
        RuntimeChangeOperation.remove => null,
        RuntimeChangeOperation.increment
            when before is num && change.value is num =>
          change.path == 'affinity'
              ? (before + (change.value as num)).clamp(0, 100)
              : before + (change.value as num),
        RuntimeChangeOperation.increment
            when before == null && change.value is num =>
          change.path == 'affinity'
              ? (50 + (change.value as num)).clamp(0, 100)
              : change.value,
        RuntimeChangeOperation.appendUnique
            when before is List && change.value is String =>
          before.contains(change.value) ? before : [...before, change.value],
        RuntimeChangeOperation.appendUnique
            when before == null && change.value is String =>
          [change.value],
        _ =>
          throw ArgumentError('Invalid runtime operation for ${change.path}'),
      };
    }
    // Apply frozen monitor or typed schema bounds before creating events and
    // persisting the overlay, so live state, timeline and replay share the
    // same settled value.
    if (result is num) {
      var clamped = result;
      if (minimum != null && clamped < minimum) clamped = minimum;
      if (maximum != null && clamped > maximum) clamped = maximum;
      return clamped;
    }
    return result;
  }

  Object? _baselineCustomAttributeValue(
    AdventureConfig? config,
    String entityId,
    String path,
  ) {
    final attributeId =
        RuntimeStateChangeProposal.customAttributeIdFromPath(path);
    if (config == null || attributeId == null) return null;
    final protagonistId =
        config.protagonistCharacter?.characterId ?? 'protagonist';
    final attributes = entityId == protagonistId || entityId == 'protagonist'
        ? config.customAttributes
        : config.supportingCharacters
                .where((character) => character.id == entityId)
                .firstOrNull
                ?.customAttributes ??
            const [];
    final attribute =
        attributes.where((item) => item.identityRef == attributeId).firstOrNull;
    if (attribute == null) return null;
    return attribute.isNumeric
        ? attribute.effectiveCurrentValue
        : attribute.value.trim();
  }

  Object? _baselineGameStateValue(
    GameState gameState,
    AdventureConfig? config,
    String entityId,
    String path,
  ) {
    final protagonistId =
        config?.protagonistCharacter?.characterId ?? 'protagonist';
    if (entityId != protagonistId && entityId != 'protagonist') return null;
    return switch (path) {
      'hp' => gameState.hp,
      'mp' => gameState.mp,
      'energy' => gameState.energy,
      'experience' => gameState.experience,
      'level' => gameState.level,
      'base_atk' => gameState.baseAtk,
      'base_def' => gameState.baseDef,
      'base_speed' => gameState.baseSpeed,
      _ => null,
    };
  }

  @override
  bool _runtimeEquals(Object? first, Object? second) =>
      jsonEncode(first) == jsonEncode(second);
}
