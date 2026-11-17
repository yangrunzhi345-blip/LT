part of 'adventure_repository_impl.dart';

mixin _AdventureRuntimeStore on _AdventureRepositoryBase {
  @override
  Future<RuntimeHead> getRuntimeHead(int adventureId, int branchId) async {
    final db = await _getDb();
    final rows = await db.query('adventure_runtime_heads',
        where: 'adventure_id = ? AND branch_id = ?',
        whereArgs: [adventureId, branchId],
        limit: 1);
    if (rows.isEmpty) {
      return RuntimeHead(adventureId: adventureId, branchId: branchId);
    }
    final row = rows.single;
    return RuntimeHead(
      adventureId: adventureId,
      branchId: branchId,
      revision: row['revision'] as int? ?? 0,
      headCommitId: row['head_commit_id'] as String?,
    );
  }

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

  @override
  Future<List<RuntimeEntityState>> getRuntimeEntities(
    int adventureId,
    int branchId, {
    int? limit,
  }) async {
    final db = await _getDb();
    final rows = await db.query('adventure_runtime_entities',
        where: 'adventure_id = ? AND branch_id = ?',
        whereArgs: [adventureId, branchId],
        orderBy: 'updated_at DESC',
        // Complete state reads must not silently fall back to snapshot values
        // when an older overlay falls outside a display/retrieval limit.
        limit: limit?.clamp(1, 512));
    // Runtime tables are persisted state, so a single legacy/corrupt row must
    // not block the whole adventure's runtime overlay. Skip malformed rows
    // (unknown entity_type, bad state_json) and keep the readable ones.
    final entities = <RuntimeEntityState>[];
    for (final row in rows) {
      final entityType = _runtimeEntityType(row['entity_type']);
      final entityId = JsonValueReader.stringScalar(row['entity_id'])?.trim();
      final overlay = _decodeRuntimeOverlay(row['state_json']);
      if (entityType == null ||
          entityId == null ||
          entityId.isEmpty ||
          overlay == null) {
        debugPrint(
            '[AdventureRepository] skipping malformed runtime entity row '
            'type=${row['entity_type']} id=${row['entity_id']}');
        continue;
      }
      entities.add(RuntimeEntityState(
        entityType: entityType,
        entityId: entityId,
        overlay: overlay,
        lifecycleStatus: row['lifecycle_status'] as String? ?? 'active',
        lastCommitId: row['last_commit_id'] as String?,
      ));
    }
    return entities.toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> getRecentStateChangesForEntity(
    int adventureId,
    int branchId,
    RuntimeEntityType entityType,
    String entityId, {
    int limit = 5,
  }) async {
    final db = await _getDb();
    return db.rawQuery('''
      SELECT c.*, s.change_index, s.path, s.before_json, s.after_json, s.reason
      FROM adventure_state_changes s
      JOIN adventure_state_commits c ON c.id = s.commit_id
      WHERE c.adventure_id = ? AND c.branch_id = ?
        AND s.entity_type = ? AND s.entity_id = ?
      ORDER BY c.revision DESC, s.change_index DESC LIMIT ?
    ''',
        [adventureId, branchId, entityType.name, entityId, limit.clamp(1, 10)]);
  }

  @override
  Future<List<RuntimeStateEvent>> getRuntimeStateEvents({
    required int adventureId,
    required int branchId,
    String? entityId,
    int limit = 50,
  }) async {
    final db = await _getDb();
    final rows = await db.rawQuery('''
      SELECT c.id AS commit_id, c.revision, c.created_at, c.cause_ref,
             c.request_id, s.id AS change_id, s.entity_type, s.entity_id,
             s.path, s.provenance_json
      FROM adventure_state_changes s
      JOIN adventure_state_commits c ON c.id = s.commit_id
      WHERE c.adventure_id = ? AND c.branch_id = ?
        ${entityId == null ? '' : 'AND s.entity_id = ?'}
      ORDER BY c.revision DESC, s.change_index DESC LIMIT ?
    ''', [
      adventureId,
      branchId,
      if (entityId != null) entityId,
      limit.clamp(1, 200),
    ]);
    final events = <RuntimeStateEvent>[];
    for (final row in rows) {
      final type = RuntimeEntityType.values
          .where((value) => value.name == row['entity_type']?.toString())
          .firstOrNull;
      if (type == null) continue;
      final provenance = _decodeMap(row['provenance_json']);
      final event = provenance['event'];
      if (event is! Map) continue;
      final source = RuntimeEventSource.values
          .where((value) => value.name == event['source']?.toString())
          .firstOrNull;
      final importance = RuntimeEventImportance.values
          .where((value) => value.name == event['importance']?.toString())
          .firstOrNull;
      final visibility = RuntimeEventVisibility.values
          .where((value) => value.name == event['visibility']?.toString())
          .firstOrNull;
      final occurredAt =
          DateTime.tryParse(event['occurred_at']?.toString() ?? '');
      if (source == null ||
          importance == null ||
          visibility == null ||
          occurredAt == null) {
        continue;
      }
      events.add(RuntimeStateEvent(
        eventId: event['event_id']?.toString() ?? row['change_id'].toString(),
        eventTypeId: event['event_type_id']?.toString() ??
            runtimeEventTypeFor(type, row['path'].toString()),
        adventureId: adventureId,
        branchId: branchId,
        commitId: row['commit_id'].toString(),
        revision: (row['revision'] as num).toInt(),
        occurredAt: occurredAt,
        source: source,
        importance: importance,
        visibility: visibility,
        sourceMessageId: event['source_message_id']?.toString(),
        parameters: Map<String, Object?>.from(
            event['parameters'] is Map ? event['parameters'] as Map : const {}),
      ));
    }
    return List.unmodifiable(events);
  }

  @override
  Future<List<RuntimeStateDiff>> getRuntimeStateDiffs({
    required int adventureId,
    required int branchId,
    String? entityId,
    int limit = 100,
  }) async {
    final db = await _getDb();
    final rows = await db.rawQuery('''
      SELECT c.id AS commit_id, c.revision, s.entity_type, s.entity_id,
             s.path, s.before_json, s.after_json, s.provenance_json
      FROM adventure_state_changes s
      JOIN adventure_state_commits c ON c.id = s.commit_id
      WHERE c.adventure_id = ? AND c.branch_id = ?
        ${entityId == null ? '' : 'AND s.entity_id = ?'}
      ORDER BY c.revision DESC, s.change_index DESC LIMIT ?
    ''', [
      adventureId,
      branchId,
      if (entityId != null) entityId,
      limit.clamp(1, 500)
    ]);
    final diffs = <RuntimeStateDiff>[];
    for (final row in rows) {
      final type = RuntimeEntityType.values
          .where((value) => value.name == row['entity_type']?.toString())
          .firstOrNull;
      if (type == null) continue;
      final event = _decodeMap(row['provenance_json'])['event'];
      final source = event is Map
          ? RuntimeEventSource.values
              .where((value) => value.name == event['source']?.toString())
              .firstOrNull
          : null;
      if (source == null) continue;
      diffs.add(RuntimeStateDiff(
        entityId: row['entity_id'].toString(),
        entityType: type,
        path: row['path'].toString(),
        before: _decodeJsonValue(row['before_json']),
        after: _decodeJsonValue(row['after_json']),
        commitId: row['commit_id'].toString(),
        revision: (row['revision'] as num).toInt(),
        source: source,
      ));
    }
    return List.unmodifiable(diffs);
  }

  @override
  Future<List<RuntimeStateDiff>> getRuntimeStateDiffsForCommit({
    required int adventureId,
    required int branchId,
    required String commitId,
  }) async {
    final db = await _getDb();
    final rows = await db.rawQuery('''
      SELECT c.revision, s.entity_type, s.entity_id, s.path,
             s.before_json, s.after_json, s.provenance_json
      FROM adventure_state_changes s
      JOIN adventure_state_commits c ON c.id = s.commit_id
      WHERE c.adventure_id = ? AND c.branch_id = ? AND c.id = ?
      ORDER BY s.change_index ASC
    ''', [adventureId, branchId, commitId]);
    return _typedDiffsFromRows(rows, commitId: commitId);
  }

  @override
  Future<RuntimeStateSnapshot> getRuntimeStateAtRevision({
    required int adventureId,
    required int branchId,
    required int revision,
    RuntimeEntityType? entityType,
    String? entityId,
  }) async {
    if (revision < 0) throw ArgumentError.value(revision, 'revision');
    final db = await _getDb();
    // The branch head freezes its ancestry at fork time. Follow commit
    // parents, rather than the parent branch's mutable current head, to replay
    // inherited fields without including later sibling/ancestor changes.
    final rows = await db.rawQuery('''
      WITH RECURSIVE lineage(id, parent_commit_id, revision) AS (
        SELECT c.id, c.parent_commit_id, c.revision
        FROM adventure_state_commits c
        JOIN adventure_runtime_heads h ON h.head_commit_id = c.id
        WHERE h.adventure_id = ? AND h.branch_id = ? AND c.adventure_id = ?
        UNION
        SELECT c.id, c.parent_commit_id, c.revision
        FROM adventure_state_commits c
        JOIN lineage child ON child.parent_commit_id = c.id
        WHERE c.adventure_id = ?
      )
      SELECT c.id AS commit_id, c.revision, s.entity_type, s.entity_id,
             s.operation, s.path, s.after_json, s.provenance_json
      FROM adventure_state_changes s
      JOIN adventure_state_commits c ON c.id = s.commit_id
      JOIN lineage ON lineage.id = c.id
      WHERE c.revision <= ?
        ${entityType == null ? '' : 'AND s.entity_type = ?'}
        ${entityId == null ? '' : 'AND s.entity_id = ?'}
      ORDER BY c.revision ASC, s.change_index ASC
    ''', [
      adventureId,
      branchId,
      adventureId,
      adventureId,
      revision,
      if (entityType != null) entityType.name,
      if (entityId != null) entityId,
    ]);
    final overlays = <String, Map<String, Object?>>{};
    final lifecycles = <String, String>{};
    for (final row in rows) {
      final type = RuntimeEntityType.values
          .where((value) => value.name == row['entity_type']?.toString())
          .firstOrNull;
      if (type == null) continue;
      final key = '${type.name}:${row['entity_id']}';
      final overlay = overlays.putIfAbsent(key, () => <String, Object?>{});
      final path = row['path'].toString();
      final after = _decodeJsonValue(row['after_json']);
      if (after == null) {
        overlay.remove(path);
      } else {
        overlay[path] = after;
      }
      if (path == 'lifecycle_status' && after is String) {
        lifecycles[key] = after;
      } else if (path == 'life_status' && after == 'dead') {
        lifecycles[key] = 'dead';
      }
    }
    final entities = <String, RuntimeEntityState>{};
    for (final entry in overlays.entries) {
      final separator = entry.key.indexOf(':');
      final type = RuntimeEntityType.values.firstWhere(
        (value) => value.name == entry.key.substring(0, separator),
      );
      final id = entry.key.substring(separator + 1);
      entities[entry.key] = RuntimeEntityState(
        entityType: type,
        entityId: id,
        overlay: entry.value,
        lifecycleStatus: lifecycles[entry.key] ?? 'active',
      );
    }
    return RuntimeStateSnapshot(
      adventureId: adventureId,
      branchId: branchId,
      revision: revision,
      entities: entities,
    );
  }

  @override
  Future<RuntimeStateSnapshot> getCurrentRuntimeState({
    required int adventureId,
    required int branchId,
    RuntimeEntityType? entityType,
    String? entityId,
  }) async {
    final head = await getRuntimeHead(adventureId, branchId);
    final entities = await getRuntimeEntities(adventureId, branchId);
    final selected = <String, RuntimeEntityState>{};
    for (final entity in entities) {
      if (entityType != null && entity.entityType != entityType) continue;
      if (entityId != null && entity.entityId != entityId) continue;
      selected['${entity.entityType.name}:${entity.entityId}'] = entity;
    }
    return RuntimeStateSnapshot(
      adventureId: adventureId,
      branchId: branchId,
      revision: head.revision,
      entities: selected,
    );
  }

  @override
  Future<List<RuntimeTimelineEntry>> getRuntimeTimeline({
    required int adventureId,
    required int branchId,
    int? beforeRevision,
    RuntimeEntityType? entityType,
    String? entityId,
    String? eventTypeId,
    int limit = 50,
  }) async {
    final db = await _getDb();
    final boundedLimit = limit.clamp(1, 200);
    final rows = await db.rawQuery('''
      WITH selected_commits AS (
        SELECT c.id, c.revision, c.created_at, c.summary, c.cause_ref, c.cause_type
        FROM adventure_state_commits c
        WHERE c.adventure_id = ? AND c.branch_id = ?
          ${beforeRevision == null ? '' : 'AND c.revision < ?'}
          AND EXISTS (
            SELECT 1 FROM adventure_state_changes filter_changes
            WHERE filter_changes.commit_id = c.id
              ${entityType == null ? '' : 'AND filter_changes.entity_type = ?'}
              ${entityId == null ? '' : 'AND filter_changes.entity_id = ?'}
              ${eventTypeId == null ? '' : "AND json_extract(filter_changes.provenance_json, '\$.event.event_type_id') = ?"}
          )
        ORDER BY c.revision DESC
        LIMIT ?
      )
      SELECT c.id AS commit_id, c.revision, c.created_at, c.summary,
             c.cause_ref, c.cause_type, s.entity_type, s.entity_id, s.path,
             s.before_json, s.after_json, s.provenance_json
      FROM selected_commits c
      JOIN adventure_state_changes s ON s.commit_id = c.id
      ORDER BY c.revision DESC, s.change_index DESC
    ''', [
      adventureId,
      branchId,
      if (beforeRevision != null) beforeRevision,
      if (entityType != null) entityType.name,
      if (entityId != null) entityId,
      if (eventTypeId != null) eventTypeId,
      boundedLimit,
    ]);
    final grouped = <String, List<Map<String, Object?>>>{};
    for (final raw in rows) {
      final row = Map<String, Object?>.from(raw);
      grouped.putIfAbsent(row['commit_id'].toString(), () => []).add(row);
    }
    final entries = <RuntimeTimelineEntry>[];
    for (final group in grouped.values) {
      final first = group.first;
      final commitId = first['commit_id'].toString();
      final diffs = _typedDiffsFromRows(group, commitId: commitId);
      final events = <RuntimeStateEvent>[];
      var legacy = false;
      for (final row in group) {
        final event = _decodeMap(row['provenance_json'])['event'];
        final parsed = _eventFromRow(event, row, adventureId, branchId);
        if (parsed == null) {
          legacy = true;
        } else {
          events.add(parsed);
        }
      }
      final occurredAt = DateTime.tryParse(first['created_at'].toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      entries.add(RuntimeTimelineEntry(
        commitId: commitId,
        adventureId: adventureId,
        branchId: branchId,
        revision: (first['revision'] as num).toInt(),
        occurredAt: occurredAt,
        summary: first['summary']?.toString() ?? '',
        sourceMessageId: first['cause_ref']?.toString(),
        causeType: first['cause_type']?.toString() ?? 'scene_dialogue',
        events: List.unmodifiable(events),
        diffs: List.unmodifiable(diffs),
        isLegacy: legacy,
      ));
    }
    entries.sort((a, b) => b.revision.compareTo(a.revision));
    return List.unmodifiable(entries.take(boundedLimit));
  }

  @override
  Future<List<TurnStateChangeGroup>> getTurnStateHistory({
    required int adventureId,
    required int branchId,
    int? beforeTurnRowId,
    int limit = 30,
    Set<RuntimeEntityType>? entityTypes,
    String? entityId,
  }) async {
    final db = await _getDb();
    final boundedLimit = limit.clamp(1, 100);
    final typeFilter = entityTypes == null || entityTypes.isEmpty
        ? ''
        : 'AND s.entity_type IN (${List.filled(entityTypes.length, '?').join(',')})';
    final entityFilter = entityId == null ? '' : 'AND s.entity_id = ?';
    final turnFilter = entityTypes == null && entityId == null
        ? ''
        : '''AND EXISTS (
          SELECT 1 FROM adventure_state_changes s
          JOIN adventure_state_commits c ON c.id = s.commit_id
          WHERE c.adventure_id = t.adventure_id
            AND c.branch_id = t.branch_id
            AND (c.request_id = t.request_id OR c.cause_ref = t.request_id)
            $typeFilter $entityFilter
        )''';
    final turns = await db.rawQuery('''
      SELECT t.rowid AS turn_row_id, t.request_id, t.created_at,
             t.assistant_client_message_id,
             (SELECT COUNT(*) FROM scene_dialogue_turns earlier
                WHERE earlier.adventure_id = t.adventure_id
                  AND earlier.branch_id = t.branch_id
                  AND earlier.rowid <= t.rowid) AS turn_number
      FROM scene_dialogue_turns t
      WHERE t.adventure_id = ? AND t.branch_id = ?
        ${beforeTurnRowId == null ? '' : 'AND t.rowid < ?'}
        $turnFilter
      ORDER BY t.rowid DESC
      LIMIT ?
    ''', [
      adventureId,
      branchId,
      if (beforeTurnRowId != null) beforeTurnRowId,
      if (entityTypes != null) ...entityTypes.map((type) => type.name),
      if (entityId != null) entityId,
      boundedLimit,
    ]);
    if (turns.isEmpty) return const [];

    final requestIds =
        turns.map((row) => row['request_id'].toString()).toList();
    final placeholders = List.filled(requestIds.length, '?').join(',');
    final commitRows = await db.rawQuery('''
      SELECT id, request_id, revision, created_at, cause_type, cause_ref
      FROM adventure_state_commits
      WHERE adventure_id = ? AND branch_id = ?
        AND (request_id IN ($placeholders) OR cause_ref IN ($placeholders))
      ORDER BY revision ASC
    ''', [adventureId, branchId, ...requestIds, ...requestIds]);
    final commitIds = commitRows.map((row) => row['id'].toString()).toList();
    final changesByCommit = <String, List<Map<String, Object?>>>{};
    if (commitIds.isNotEmpty) {
      final commitPlaceholders = List.filled(commitIds.length, '?').join(',');
      final changes = await db.rawQuery('''
        SELECT s.commit_id, s.entity_type, s.entity_id, s.path,
               s.before_json, s.after_json, s.reason, s.provenance_json,
               c.request_id, c.revision, c.cause_type, c.cause_ref
        FROM adventure_state_changes s
        JOIN adventure_state_commits c ON c.id = s.commit_id
        WHERE s.commit_id IN ($commitPlaceholders) $typeFilter $entityFilter
        ORDER BY c.revision ASC, s.change_index ASC
      ''', [
        ...commitIds,
        if (entityTypes != null) ...entityTypes.map((type) => type.name),
        if (entityId != null) entityId,
      ]);
      for (final change in changes) {
        changesByCommit
            .putIfAbsent(change['commit_id'].toString(), () => [])
            .add(Map<String, Object?>.from(change));
      }
    }

    Object? decode(Object? raw) {
      if (raw is! String || raw.isEmpty) return raw;
      try {
        return jsonDecode(raw);
      } catch (_) {
        return raw;
      }
    }

    final commitsByRequest = <String, List<Map<String, Object?>>>{};
    for (final commit in commitRows) {
      final projected = Map<String, Object?>.from(commit);
      commitsByRequest
          .putIfAbsent(commit['request_id'].toString(), () => [])
          .add(projected);
      final causeRef = commit['cause_ref']?.toString();
      if (causeRef != null &&
          causeRef != commit['request_id']?.toString() &&
          requestIds.contains(causeRef)) {
        commitsByRequest.putIfAbsent(causeRef, () => []).add(projected);
      }
    }
    final result = <TurnStateChangeGroup>[];
    for (final turn in turns) {
      final requestId = turn['request_id'].toString();
      final changes = <TurnStateChange>[];
      final commits = commitsByRequest[requestId] ?? const [];
      for (final commit in commits) {
        final commitId = commit['id'].toString();
        for (final row in changesByCommit[commitId] ?? const []) {
          final entityType = RuntimeEntityType.values
              .where((type) => type.name == row['entity_type']?.toString())
              .firstOrNull;
          if (entityType == null) continue;
          final provenance = _decodeMap(row['provenance_json'])['event'];
          final eventVisibility =
              provenance is Map ? provenance['visibility']?.toString() : null;
          if (eventVisibility == RuntimeEventVisibility.internal.name ||
              eventVisibility == 'hidden') {
            continue;
          }
          changes.add(TurnStateChange(
            entityType: entityType,
            entityId: row['entity_id'].toString(),
            path: row['path'].toString(),
            before: decode(row['before_json']),
            after: decode(row['after_json']),
            reason: row['reason']?.toString() ?? '',
            commitId: commitId,
            revision: (row['revision'] as num?)?.toInt() ?? 0,
            causeType: row['cause_type']?.toString() ?? 'scene_dialogue',
            isLegacy: provenance is! Map,
            sourceMessageId: provenance is Map
                ? provenance['source_message_id']?.toString()
                : row['cause_ref']?.toString(),
          ));
        }
      }
      final revisions = commits
          .map((row) => (row['revision'] as num?)?.toInt() ?? 0)
          .where((revision) => revision > 0)
          .toList();
      result.add(TurnStateChangeGroup(
        adventureId: adventureId,
        branchId: branchId,
        turnId: requestId,
        turnRowId: (turn['turn_row_id'] as num?)?.toInt() ?? 0,
        turnNumber: (turn['turn_number'] as num?)?.toInt() ?? 0,
        requestId: requestId,
        assistantMessageId: turn['assistant_client_message_id']?.toString(),
        occurredAt: DateTime.tryParse(turn['created_at'].toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        revisionStart: revisions.isEmpty ? 0 : revisions.reduce(math.min),
        revisionEnd: revisions.isEmpty ? 0 : revisions.reduce(math.max),
        changes: List.unmodifiable(changes),
      ));
    }
    return List.unmodifiable(result);
  }

  @override
  Future<RuntimeStateCheckpoint> createRuntimeCheckpoint(
      RuntimeStateCheckpoint checkpoint) async {
    final name = checkpoint.name.trim();
    final note = checkpoint.note.trim();
    if (name.isEmpty || name.length > RuntimeStateCheckpoint.maxNameLength) {
      throw ArgumentError.value(checkpoint.name, 'name');
    }
    if (note.length > RuntimeStateCheckpoint.maxNoteLength) {
      throw ArgumentError.value(checkpoint.note, 'note');
    }
    if (checkpoint.revision < 0) {
      throw ArgumentError.value(checkpoint.revision, 'revision');
    }
    final head =
        await getRuntimeHead(checkpoint.adventureId, checkpoint.branchId);
    if (checkpoint.revision > head.revision) {
      throw ArgumentError.value(checkpoint.revision, 'revision', 'beyond HEAD');
    }
    await getRuntimeStateAtRevision(
      adventureId: checkpoint.adventureId,
      branchId: checkpoint.branchId,
      revision: checkpoint.revision,
    );
    final db = await _getDb();
    final now = DateTime.now().toUtc();
    final normalized = RuntimeStateCheckpoint(
      id: checkpoint.id,
      adventureId: checkpoint.adventureId,
      branchId: checkpoint.branchId,
      revision: checkpoint.revision,
      name: name,
      note: note,
      createdAt: checkpoint.createdAt.toUtc(),
      updatedAt: now,
    );
    await db.insert(
        'runtime_state_checkpoints',
        {
          'id': normalized.id,
          'adventure_id': normalized.adventureId,
          'branch_id': normalized.branchId,
          'revision': normalized.revision,
          'name': normalized.name,
          'note': normalized.note,
          'created_at': normalized.createdAt.toIso8601String(),
          'updated_at': normalized.updatedAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    return (await getRuntimeCheckpoint(normalized.id)) ?? normalized;
  }

  RuntimeStateCheckpoint _checkpointFromRow(Map<String, Object?> row) {
    final created = DateTime.tryParse(row['created_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final updated =
        DateTime.tryParse(row['updated_at']?.toString() ?? '') ?? created;
    return RuntimeStateCheckpoint(
      id: row['id'].toString(),
      adventureId: (row['adventure_id'] as num).toInt(),
      branchId: (row['branch_id'] as num).toInt(),
      revision: (row['revision'] as num).toInt(),
      name: row['name']?.toString() ?? '',
      note: row['note']?.toString() ?? '',
      createdAt: created,
      updatedAt: updated,
    );
  }

  @override
  Future<List<RuntimeStateCheckpoint>> getRuntimeCheckpoints({
    required int adventureId,
    required int branchId,
    int? beforeRevision,
    int limit = 100,
  }) async {
    final db = await _getDb();
    final rows = await db.query(
      'runtime_state_checkpoints',
      where:
          'adventure_id = ? AND branch_id = ?${beforeRevision == null ? '' : ' AND revision < ?'}',
      whereArgs: [
        adventureId,
        branchId,
        if (beforeRevision != null) beforeRevision
      ],
      orderBy: 'revision DESC',
      limit: limit.clamp(1, 200),
    );
    return List.unmodifiable(rows.map(_checkpointFromRow));
  }

  @override
  Future<RuntimeStateCheckpoint?> getRuntimeCheckpoint(String id) async {
    final db = await _getDb();
    final rows = await db.query('runtime_state_checkpoints',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _checkpointFromRow(rows.first);
  }

  @override
  Future<void> renameRuntimeCheckpoint(String id, String name) async {
    final value = name.trim();
    if (value.isEmpty || value.length > RuntimeStateCheckpoint.maxNameLength) {
      throw ArgumentError.value(name, 'name');
    }
    final db = await _getDb();
    await db.update('runtime_state_checkpoints',
        {'name': value, 'updated_at': DateTime.now().toUtc().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> updateRuntimeCheckpointNote(String id, String note) async {
    final value = note.trim();
    if (value.length > RuntimeStateCheckpoint.maxNoteLength) {
      throw ArgumentError.value(note, 'note');
    }
    final db = await _getDb();
    await db.update('runtime_state_checkpoints',
        {'note': value, 'updated_at': DateTime.now().toUtc().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> deleteRuntimeCheckpoint(String id) async {
    final db = await _getDb();
    await db
        .delete('runtime_state_checkpoints', where: 'id = ?', whereArgs: [id]);
  }

  List<RuntimeStateDiff> _typedDiffsFromRows(
    Iterable<Map<String, Object?>> rows, {
    required String commitId,
  }) {
    final result = <RuntimeStateDiff>[];
    for (final row in rows) {
      final type = RuntimeEntityType.values
          .where((value) => value.name == row['entity_type']?.toString())
          .firstOrNull;
      final event = _decodeMap(row['provenance_json'])['event'];
      final source = event is Map
          ? RuntimeEventSource.values
              .where((value) => value.name == event['source']?.toString())
              .firstOrNull
          : null;
      if (type == null || source == null) continue;
      result.add(RuntimeStateDiff(
        entityId: row['entity_id'].toString(),
        entityType: type,
        path: row['path'].toString(),
        before: _decodeJsonValue(row['before_json']),
        after: _decodeJsonValue(row['after_json']),
        commitId: commitId,
        revision: (row['revision'] as num).toInt(),
        source: source,
      ));
    }
    return result;
  }

  RuntimeStateEvent? _eventFromRow(
    Object? raw,
    Map<String, Object?> row,
    int adventureId,
    int branchId,
  ) {
    if (raw is! Map) return null;
    final source = RuntimeEventSource.values
        .where((value) => value.name == raw['source']?.toString())
        .firstOrNull;
    final importance = RuntimeEventImportance.values
        .where((value) => value.name == raw['importance']?.toString())
        .firstOrNull;
    final visibility = RuntimeEventVisibility.values
        .where((value) => value.name == raw['visibility']?.toString())
        .firstOrNull;
    final occurredAt = DateTime.tryParse(raw['occurred_at']?.toString() ?? '');
    if (source == null ||
        importance == null ||
        visibility == null ||
        occurredAt == null) {
      return null;
    }
    return RuntimeStateEvent(
      eventId: raw['event_id']?.toString() ?? row['id'].toString(),
      eventTypeId: raw['event_type_id']?.toString() ?? 'legacy',
      adventureId: adventureId,
      branchId: branchId,
      commitId: row['commit_id'].toString(),
      revision: (row['revision'] as num).toInt(),
      occurredAt: occurredAt,
      source: source,
      importance: importance,
      visibility: visibility,
      sourceMessageId: raw['source_message_id']?.toString(),
      parameters: Map<String, Object?>.from(
          raw['parameters'] is Map ? raw['parameters'] as Map : const {}),
    );
  }

  @override
  Future<void> seedRuntimeEntity({
    required int adventureId,
    required int branchId,
    required RuntimeEntityType entityType,
    required String entityId,
  }) async {
    // The seed id is the adventure's own stable identity for the entity —
    // exactly the frozen config's id. Resource ids are opaque strings, so this
    // must use the shared runtime entity id rule rather than an ASCII-only
    // guard, or a real (e.g. imported `name_creator`) card id would abort the
    // whole Adventure creation after its row was already inserted.
    if (!isValidRuntimeEntityId(entityId)) {
      throw ArgumentError.value(entityId, 'entityId');
    }
    final db = await _getDb();
    await db.insert(
        'adventure_runtime_entities',
        {
          'adventure_id': adventureId,
          'branch_id': branchId,
          'entity_type': entityType.name,
          'entity_id': entityId,
          'state_json': '{}',
          'lifecycle_status': 'active',
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert(
      'adventure_runtime_heads',
      {
        'adventure_id': adventureId,
        'branch_id': branchId,
        'revision': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}
