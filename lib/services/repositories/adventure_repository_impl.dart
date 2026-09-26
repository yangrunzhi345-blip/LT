import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../application/adventure/adventure_character_identity.dart';
import '../../core/utils/json_value_reader.dart';
import '../../models/adventure_config.dart';
import '../../models/adventure_response.dart';
import '../../models/adventure_runtime_state.dart';
import '../../models/diagnostics/diagnostic_session_export.dart';
import '../../models/diagnostics/diagnostic_turn_export.dart';
import '../../models/scene_dialogue.dart';
import '../../models/scene_dialogue_effects.dart';
import '../../models/scene_state.dart';
import '../../models/game_state.dart';
import '../../models/message.dart';
import '../../models/typed_runtime_state.dart';
import '../../models/runtime_state_history.dart';
import '../../models/turn_state_history.dart';
import '../runtime_state_validator.dart';
import '../scene_state_proposal_validator.dart';
import 'adventure_repository.dart';

class AdventureRepositoryImpl implements IAdventureRepository {
  final Future<Database> Function() _getDb;

  AdventureRepositoryImpl({required Future<Database> Function() getDb})
      : _getDb = getDb;

  // ─── Adventures ───

  @override
  Future<int> createAdventure(String title, AdventureConfig config) async {
    final db = await _getDb();
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('adventures', {
      'title': title,
      'config': jsonEncode(config.toJson()),
      'created_at': now,
    });
    return id;
  }

  @override
  Future<List<Map<String, dynamic>>> getAdventures() async {
    final db = await _getDb();
    return db.query('adventures', orderBy: 'created_at DESC');
  }

  @override
  Future<Map<String, dynamic>?> getAdventureById(int id) async {
    final db = await _getDb();
    final rows = await db.query(
      'adventures',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

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
    int limit = 256,
  }) async {
    final db = await _getDb();
    final rows = await db.query('adventure_runtime_entities',
        where: 'adventure_id = ? AND branch_id = ?',
        whereArgs: [adventureId, branchId],
        orderBy: 'updated_at DESC',
        limit: limit.clamp(1, 512));
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

  static RuntimeEntityType? _runtimeEntityType(Object? raw) {
    final name = raw is String ? raw : null;
    if (name == null) return null;
    for (final type in RuntimeEntityType.values) {
      if (type.name == name) return type;
    }
    return null;
  }

  /// Decodes `state_json`; returns null when it is not a JSON object.
  static Map<String, Object?>? _decodeRuntimeOverlay(Object? raw) {
    if (raw == null) return <String, Object?>{};
    if (raw is Map) return Map<String, Object?>.from(raw);
    if (raw is! String) return null;
    if (raw.trim().isEmpty) return <String, Object?>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Tolerant scene-state decode for the idempotent commit path.
  ///
  /// Uses the same `SceneState.tryDecode` boundary as `getSceneState`; a
  /// corrupt row logs a diagnostic and returns null so the caller can fall
  /// back to the current turn's state.
  static SceneState? _decodeSceneStateForCommit(Object? raw) {
    final text = raw is String ? raw : JsonValueReader.stringScalar(raw);
    if (text == null) return null;
    final state = SceneState.tryDecode(text);
    if (state == null) {
      debugPrint(
          '[AdventureRepository] skipping malformed scene state row during commit');
    }
    return state;
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
    final rows = await db.rawQuery('''
      SELECT c.id AS commit_id, c.revision, s.entity_type, s.entity_id,
             s.operation, s.path, s.after_json, s.provenance_json
      FROM adventure_state_changes s
      JOIN adventure_state_commits c ON c.id = s.commit_id
      WHERE c.adventure_id = ? AND c.branch_id = ? AND c.revision <= ?
        ${entityType == null ? '' : 'AND s.entity_type = ?'}
        ${entityId == null ? '' : 'AND s.entity_id = ?'}
      ORDER BY c.revision ASC, s.change_index ASC
    ''', [
      adventureId,
      branchId,
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
  }) async {
    final db = await _getDb();
    final boundedLimit = limit.clamp(1, 100);
    final typeFilter = entityTypes == null || entityTypes.isEmpty
        ? ''
        : 'AND s.entity_type IN (${List.filled(entityTypes.length, '?').join(',')})';
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
      ORDER BY t.rowid DESC
      LIMIT ?
    ''', [
      adventureId,
      branchId,
      if (beforeTurnRowId != null) beforeTurnRowId,
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
        WHERE s.commit_id IN ($commitPlaceholders) $typeFilter
        ORDER BY c.revision ASC, s.change_index ASC
      ''', [
        ...commitIds,
        if (entityTypes != null) ...entityTypes.map((type) => type.name),
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

  static Object? _decodeJsonValue(Object? raw) {
    if (raw is! String) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  static Map<String, Object?> _decodeMap(Object? raw) {
    if (raw is! String) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, Object?>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<void> seedRuntimeEntity({
    required int adventureId,
    required int branchId,
    required RuntimeEntityType entityType,
    required String entityId,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9_.:-]{1,200}$').hasMatch(entityId)) {
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

  @override
  Future<void> updateAdventureConfig(int id, AdventureConfig config) async {
    final db = await _getDb();
    await db.update('adventures', {'config': jsonEncode(config.toJson())},
        where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> deleteAdventure(int id) async {
    final db = await _getDb();
    await db.transaction((txn) async {
      await txn.delete('messages', where: 'adventure_id = ?', whereArgs: [id]);
      await txn
          .delete('game_state', where: 'adventure_id = ?', whereArgs: [id]);
      await txn.delete('summaries', where: 'adventure_id = ?', whereArgs: [id]);
      await txn
          .delete('world_entries', where: 'adventure_id = ?', whereArgs: [id]);
      await txn.delete('branches', where: 'adventure_id = ?', whereArgs: [id]);
      await txn.delete('bookmarks', where: 'adventure_id = ?', whereArgs: [id]);
      await txn.delete('adventures', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ─── Messages ───

  @override
  Future<int> insertMessage(int adventureId, Message msg,
      {int branchId = 0}) async {
    final db = await _getDb();
    final id = await db.insert('messages', {
      'adventure_id': adventureId,
      'role': msg.isUser ? 'user' : 'assistant',
      'content': msg.content,
      'reasoning_content': msg.reasoningContent,
      'is_html': msg.isHtml ? 1 : 0,
      'edited': msg.isEdited ? 1 : 0,
      'error_type': msg.errorType,
      'timestamp': msg.timestamp.toIso8601String(),
      'branch_id': branchId,
      'client_message_id': msg.id,
    });
    return id;
  }

  @override
  Future<List<Message>> getMessages(int adventureId, {int branchId = 0}) async {
    final db = await _getDb();
    final rows = await db.query('messages',
        where: 'adventure_id = ? AND branch_id = ?',
        whereArgs: [adventureId, branchId],
        orderBy: 'timestamp ASC');
    return rows
        .map((r) => Message(
              id: (r['client_message_id'] as String?) ?? r['id'].toString(),
              content: r['content'] as String,
              reasoningContent: r['reasoning_content'] as String?,
              isUser: r['role'] == 'user',
              timestamp: DateTime.parse(r['timestamp'] as String),
              isHtml: (r['is_html'] as int?) == 1,
              isEdited: (r['edited'] as int?) == 1,
              errorType: r['error_type'] as String?,
            ))
        .toList();
  }

  @override
  Future<List<Message>> getTurnMessages({
    required int adventureId,
    required int branchId,
    required String? assistantMessageId,
  }) async {
    if (assistantMessageId == null || assistantMessageId.trim().isEmpty) {
      return const [];
    }
    final db = await _getDb();
    final assistantRows = await db.query(
      'messages',
      where: 'adventure_id = ? AND branch_id = ? AND client_message_id = ?',
      whereArgs: [adventureId, branchId, assistantMessageId],
      limit: 1,
    );
    if (assistantRows.isEmpty) return const [];
    final assistant = assistantRows.single;
    final assistantId = (assistant['id'] as num).toInt();
    final userRows = await db.query(
      'messages',
      where: 'adventure_id = ? AND branch_id = ? AND role = ? AND id < ?',
      whereArgs: [adventureId, branchId, 'user', assistantId],
      orderBy: 'id DESC',
      limit: 1,
    );
    final rows = [
      ...userRows,
      assistant
    ]..sort((left, right) => (left['id'] as num).compareTo(right['id'] as num));
    return rows
        .map((row) => Message(
              id: row['client_message_id']?.toString() ?? row['id'].toString(),
              content: row['content']?.toString() ?? '',
              isUser: row['role'] == 'user',
              timestamp:
                  DateTime.tryParse(row['timestamp']?.toString() ?? '') ??
                      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
              isHtml: (row['is_html'] as int?) == 1,
              isEdited: (row['edited'] as int?) == 1,
              errorType: row['error_type']?.toString(),
            ))
        .toList(growable: false);
  }

  @override
  Future<void> updateMessageContent(
      int adventureId, String messageId, String newContent) async {
    final db = await _getDb();
    await db.update(
      'messages',
      {'content': newContent, 'edited': 1},
      where: 'adventure_id = ? AND (CAST(id AS TEXT) = ? OR '
          'client_message_id = ?)',
      whereArgs: [adventureId, messageId, messageId],
    );
  }

  @override
  Future<void> updateMessageAndDeleteFollowing({
    required int adventureId,
    required int branchId,
    required String messageId,
    required String newContent,
  }) async {
    final db = await _getDb();
    await db.transaction((txn) async {
      final rowId = await _messageRowId(
        txn,
        adventureId: adventureId,
        branchId: branchId,
        messageId: messageId,
      );
      await txn.update(
        'messages',
        {'content': newContent, 'edited': 1},
        where: 'id = ?',
        whereArgs: [rowId],
      );
      await txn.delete(
        'messages',
        where: 'adventure_id = ? AND branch_id = ? AND id > ?',
        whereArgs: [adventureId, branchId, rowId],
      );
    });
  }

  @override
  Future<void> deleteMessageHistory({
    required int adventureId,
    required int branchId,
    required String messageId,
    required bool inclusive,
  }) async {
    final db = await _getDb();
    await db.transaction((txn) async {
      final rowId = await _messageRowId(
        txn,
        adventureId: adventureId,
        branchId: branchId,
        messageId: messageId,
      );
      await txn.delete(
        'messages',
        where: 'adventure_id = ? AND branch_id = ? AND '
            'id ${inclusive ? '>=' : '>'} ?',
        whereArgs: [adventureId, branchId, rowId],
      );
    });
  }

  Future<int> _messageRowId(
    DatabaseExecutor executor, {
    required int adventureId,
    required int branchId,
    required String messageId,
  }) async {
    final rows = await executor.query(
      'messages',
      columns: const ['id'],
      where: 'adventure_id = ? AND branch_id = ? AND '
          '(CAST(id AS TEXT) = ? OR client_message_id = ?)',
      whereArgs: [adventureId, branchId, messageId, messageId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Message $messageId is not part of the active branch');
    }
    return rows.single['id'] as int;
  }

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
          content: '🌟 升级！现在是 Lv.$nextLevel\n'
              'HP/MP 完全恢复 | 全属性 +1 | 获得 2 技能点',
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
            'ignored_scene_state_changes': sceneValidation.diagnostics,
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
        '${change.entityType.name}:${change.entityId}:${change.path}',
    };
    return RuntimeStateCommitDraft(
      expectedRevision: explicit.expectedRevision,
      changes: List.unmodifiable([
        ...explicit.changes,
        ...legacy.changes.where(
          (change) => !explicitPaths.contains(
            '${change.entityType.name}:${change.entityId}:${change.path}',
          ),
        ),
      ]),
      summary: explicit.summary.isNotEmpty ? explicit.summary : legacy.summary,
      contextSnapshotId: explicit.contextSnapshotId ?? legacy.contextSnapshotId,
      sourceMessageId: explicit.sourceMessageId ?? legacy.sourceMessageId,
    );
  }

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
      final after = _applyRuntimeOperation(before, proposal);
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
      Object? before, RuntimeStateChangeProposal change) {
    final value = change.value;
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
      final result = current + value;
      return switch (change.path) {
        'hp' || 'mp' || 'energy' => result.clamp(0, 999999),
        'experience' => result.clamp(0, 999999999),
        'level' => result.clamp(1, 9999),
        'base_atk' || 'base_def' || 'base_speed' => result.clamp(0, 999999),
        _ => result,
      };
    }
    return switch (change.operation) {
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
      _ => throw ArgumentError('Invalid runtime operation for ${change.path}'),
    };
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

  bool _runtimeEquals(Object? first, Object? second) =>
      jsonEncode(first) == jsonEncode(second);

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

  @override
  Future<DiagnosticSessionExport> getDiagnosticSessionExport({
    required int adventureId,
    required int branchId,
    int? turnLimit,
    String appVersion = '1.1.11',
    String platformName = 'unknown',
  }) async {
    final db = await _getDb();
    final exportWarnings = <String>[];

    // 1. 获取冒险与分支基本信息
    final advRows = await db.query(
      'adventures',
      columns: ['title'],
      where: 'id = ?',
      whereArgs: [adventureId],
      limit: 1,
    );
    final adventureTitle =
        advRows.firstOrNull?['title'] as String? ?? 'Adventure $adventureId';

    var branchName = 'main';
    if (branchId > 0) {
      final branchRows = await db.query(
        'branches',
        columns: ['name'],
        where: 'id = ? AND adventure_id = ?',
        whereArgs: [branchId, adventureId],
        limit: 1,
      );
      if (branchRows.isNotEmpty) {
        branchName = branchRows.first['name'] as String? ?? 'branch_$branchId';
      } else {
        branchName = 'branch_$branchId';
      }
    }

    // 2. 获取当前会话状态快照 (Runtime Head, Scene State, Runtime Entities)
    final head = await getRuntimeHead(adventureId, branchId);
    final entities = await getRuntimeEntities(adventureId, branchId, limit: 64);
    final sceneState = await getSceneState(adventureId, branchId);

    final sceneStateSnapshot = sceneState != null
        ? DiagnosticSceneStateSnapshot(
            location: sceneState.location,
            time: sceneState.time,
            presentCharacterIds: sceneState.presentCharacterIds,
            activeGoals: sceneState.activeGoals.map((g) => g.toJson()).toList(),
          )
        : null;

    final entitySnapshots = entities
        .map((e) => DiagnosticEntitySnapshot(
              entityType: e.entityType.name,
              entityId: e.entityId,
              lifecycleStatus: e.lifecycleStatus,
              lastCommitId: e.lastCommitId,
              overlay: e.overlay,
            ))
        .toList();

    final runtimeSnapshot = DiagnosticRuntimeSnapshot(
      headRevision: head.revision,
      headCommitId: head.headCommitId,
      sceneState: sceneStateSnapshot,
      entities: entitySnapshots,
    );

    // 3. 查询此分支上成功持久化的 Turns (按 rowid DESC 限制，随后按 rowid ASC 正序排布)
    final turnRows = await db.query(
      'scene_dialogue_turns',
      where: 'adventure_id = ? AND branch_id = ?',
      whereArgs: [adventureId, branchId],
      orderBy: 'rowid DESC',
      limit: turnLimit,
    );
    final orderedTurns = turnRows.reversed.toList(growable: false);

    if (orderedTurns.isEmpty) {
      return DiagnosticSessionExport(
        exportedAt: DateTime.now().toIso8601String(),
        application: DiagnosticApplicationInfo(
          name: 'LT Dialogue',
          version: appVersion,
          platform: platformName,
        ),
        scope: DiagnosticScope(
          adventureId: adventureId,
          adventureTitle: adventureTitle,
          branchId: branchId,
          branchName: branchName,
          headRevision: head.revision,
          turnRange: DiagnosticTurnRange(
            mode: turnLimit == null ? 'all' : 'recent',
            requested: turnLimit,
            actual: 0,
          ),
        ),
        runtimeSnapshot: runtimeSnapshot,
        turns: const [],
        exportWarnings: exportWarnings,
      );
    }

    // 4. 收集 turn request_ids
    final requestIds = orderedTurns
        .map((r) => r['request_id'] as String?)
        .whereType<String>()
        .toList();

    // 5. 批量查询相关的 State Commits 与 Changes (O(1) 批量查询，杜绝 N+1)
    final Map<String, Map<String, dynamic>> commitsByRequestId = {};
    final Map<String, List<DiagnosticRuntimeChange>> changesByCommitId = {};

    if (requestIds.isNotEmpty) {
      final commitPlaceholders = List.filled(requestIds.length, '?').join(',');
      final commitRows = await db.rawQuery(
        'SELECT id, request_id, revision, summary, created_at '
        'FROM adventure_state_commits '
        'WHERE adventure_id = ? AND branch_id = ? AND request_id IN ($commitPlaceholders)',
        [adventureId, branchId, ...requestIds],
      );

      final commitIds = <String>[];
      for (final c in commitRows) {
        final reqId = c['request_id'] as String?;
        final commitId = c['id'] as String?;
        if (reqId != null) {
          commitsByRequestId[reqId] = c;
        }
        if (commitId != null) {
          commitIds.add(commitId);
        }
      }

      if (commitIds.isNotEmpty) {
        final changePlaceholders = List.filled(commitIds.length, '?').join(',');
        final changeRows = await db.rawQuery(
          'SELECT commit_id, change_index, entity_type, entity_id, change_kind, operation, path, before_json, after_json, reason '
          'FROM adventure_state_changes '
          'WHERE commit_id IN ($changePlaceholders) '
          'ORDER BY commit_id ASC, change_index ASC',
          commitIds,
        );

        for (final cr in changeRows) {
          final commitId = cr['commit_id'] as String;
          final entityType = cr['entity_type']?.toString() ?? '';
          final entityId = cr['entity_id']?.toString() ?? '';
          final changeKind = cr['change_kind']?.toString() ?? '';
          final operation = cr['operation']?.toString() ?? '';
          final path = cr['path']?.toString() ?? '';
          final reason = cr['reason']?.toString() ?? '';

          Object? before;
          final beforeRaw = cr['before_json'];
          if (beforeRaw is String && beforeRaw.isNotEmpty) {
            try {
              before = jsonDecode(beforeRaw);
            } catch (_) {
              before = beforeRaw;
            }
          }

          Object? after;
          final afterRaw = cr['after_json'];
          if (afterRaw is String && afterRaw.isNotEmpty) {
            try {
              after = jsonDecode(afterRaw);
            } catch (_) {
              after = afterRaw;
            }
          }

          changesByCommitId.putIfAbsent(commitId, () => []).add(
                DiagnosticRuntimeChange(
                  entityType: entityType,
                  entityId: entityId,
                  changeKind: changeKind,
                  operation: operation,
                  path: path,
                  before: before,
                  after: after,
                  reason: reason,
                ),
              );
        }
      }
    }

    // 6. 批量拉取该分支所有消息（排除 reasoning_content，严格遵守 Rule 8）
    final messageRows = await db.query(
      'messages',
      columns: [
        'id',
        'client_message_id',
        'role',
        'content',
        'timestamp',
        'error_type'
      ],
      where: 'adventure_id = ? AND branch_id = ?',
      whereArgs: [adventureId, branchId],
      orderBy: 'id ASC',
    );

    // 构建按 client_message_id 与 id 的索引映射
    final Map<String, int> messageIndexByClientMsgId = {};
    for (var i = 0; i < messageRows.length; i++) {
      final clientMsgId = messageRows[i]['client_message_id'] as String?;
      if (clientMsgId != null && clientMsgId.isNotEmpty) {
        messageIndexByClientMsgId[clientMsgId] = i;
      }
      final numId = messageRows[i]['id']?.toString();
      if (numId != null) {
        messageIndexByClientMsgId.putIfAbsent(numId, () => i);
      }
    }

    // 7. 遍历 Turns，使用确定性原子事务写入顺序关联用户消息与 AI 消息 (Rule 2 & 5)
    final turns = <DiagnosticTurnExport>[];
    var lastConsumedUserMsgIndex = -1;

    for (var i = 0; i < orderedTurns.length; i++) {
      final turnRow = orderedTurns[i];
      final turnIndex =
          i + 1; // 1-based sequential index within current session (Rule 5)
      final requestId = turnRow['request_id'] as String? ?? 'req_unknown';
      final createdAt = turnRow['created_at'] as String? ?? '';
      final assistantClientMsgId =
          turnRow['assistant_client_message_id'] as String?;

      // 7.1 确定性寻找助理消息
      Map<String, dynamic>? assistantRow;
      int? assistantIdx;
      if (assistantClientMsgId != null) {
        assistantIdx = messageIndexByClientMsgId[assistantClientMsgId];
        if (assistantIdx != null && assistantIdx < messageRows.length) {
          assistantRow = messageRows[assistantIdx];
        }
      }

      final String assistantContentRaw;
      final String assistantMsgId;
      final String assistantTimestamp;
      final String? assistantErrorType;

      if (assistantRow != null) {
        assistantContentRaw = assistantRow['content'] as String? ?? '';
        assistantMsgId = assistantClientMsgId ?? assistantRow['id'].toString();
        assistantTimestamp = assistantRow['timestamp'] as String? ?? createdAt;
        assistantErrorType = assistantRow['error_type'] as String?;
      } else {
        assistantContentRaw = '';
        assistantMsgId = assistantClientMsgId ?? 'msg_missing';
        assistantTimestamp = createdAt;
        assistantErrorType = null;
        exportWarnings.add(
            'Turn $turnIndex (request: $requestId): assistant message not found in database');
      }

      // 提取可见正文与推荐选项 (Rule 9)
      final visibleNarrative =
          AdventureResponse.streamingDisplayText(assistantContentRaw).trim();
      final assistantContent =
          visibleNarrative.isNotEmpty ? visibleNarrative : assistantContentRaw;

      List<String>? parsedOptions;
      try {
        final split = AdventureResponse.tryParseSplit(assistantContentRaw);
        if (split != null && split.options.isNotEmpty) {
          parsedOptions = List<String>.from(split.options);
        } else {
          parsedOptions = const [];
        }
      } catch (e) {
        parsedOptions = const [];
        exportWarnings.add(
            'Turn $turnIndex (request: $requestId): failed to parse options: $e');
      }

      final assistantMessage = DiagnosticMessage(
        messageId: assistantMsgId,
        content: assistantContent,
        timestamp: assistantTimestamp,
        isUser: false,
        options: parsedOptions,
        errorType: assistantErrorType,
      );

      // 7.2 确定性关联前序用户消息 (Rule 2)
      // 事务内原子写入保证：同一回合中，userMessage 紧邻在 assistantMessage 之前写入。
      DiagnosticMessage? userMessage;
      if (assistantIdx != null && assistantIdx > 0) {
        final candidateUserIdx = assistantIdx - 1;
        final candidateUserRow = messageRows[candidateUserIdx];
        final role = candidateUserRow['role'] as String?;

        if (role == 'user' && candidateUserIdx > lastConsumedUserMsgIndex) {
          lastConsumedUserMsgIndex = candidateUserIdx;
          final userMsgId =
              (candidateUserRow['client_message_id'] as String?) ??
                  candidateUserRow['id'].toString();
          final userContent = candidateUserRow['content'] as String? ?? '';
          final userTimestamp =
              candidateUserRow['timestamp'] as String? ?? createdAt;

          userMessage = DiagnosticMessage(
            messageId: userMsgId,
            content: userContent,
            timestamp: userTimestamp,
            isUser: true,
          );
        } else if (role != 'user') {
          exportWarnings.add(
            'Turn $turnIndex (request: $requestId): preceding message is not a user message (role: $role)',
          );
        } else {
          exportWarnings.add(
            'Turn $turnIndex (request: $requestId): ambiguous user message association (already consumed)',
          );
        }
      } else {
        exportWarnings.add(
          'Turn $turnIndex (request: $requestId): no preceding message found for assistant message',
        );
      }

      // 7.3 关联 Runtime Commit 与 Changes
      final commitRow = commitsByRequestId[requestId];
      final DiagnosticTurnRuntime turnRuntime;
      if (commitRow != null) {
        final commitId = commitRow['id'] as String;
        final revision = commitRow['revision'] as int? ?? head.revision;
        final summary = commitRow['summary'] as String?;
        final changes = changesByCommitId[commitId] ?? const [];

        turnRuntime = DiagnosticTurnRuntime(
          committed: true,
          commitId: commitId,
          revisionBefore: revision > 0 ? revision - 1 : 0,
          revisionAfter: revision,
          summary: summary,
          changes: changes,
        );
      } else {
        turnRuntime = const DiagnosticTurnRuntime(
          committed: false,
          changes: [],
        );
      }

      // 7.4 解码 Diagnostics JSON
      Map<String, dynamic> diagnostics = {};
      final rawDiag = turnRow['diagnostics_json'];
      if (rawDiag is String && rawDiag.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawDiag);
          if (decoded is Map) {
            diagnostics = Map<String, dynamic>.from(decoded);
          }
        } catch (e) {
          exportWarnings.add(
              'Turn $turnIndex (request: $requestId): malformed diagnostics_json: $e');
        }
      }

      turns.add(
        DiagnosticTurnExport(
          turnIndex: turnIndex,
          requestId: requestId,
          createdAt: createdAt,
          user: userMessage,
          assistant: assistantMessage,
          runtime: turnRuntime,
          diagnostics: diagnostics,
        ),
      );
    }

    return DiagnosticSessionExport(
      exportedAt: DateTime.now().toIso8601String(),
      application: DiagnosticApplicationInfo(
        name: 'LT Dialogue',
        version: appVersion,
        platform: platformName,
      ),
      scope: DiagnosticScope(
        adventureId: adventureId,
        adventureTitle: adventureTitle,
        branchId: branchId,
        branchName: branchName,
        headRevision: head.revision,
        turnRange: DiagnosticTurnRange(
          mode: turnLimit == null ? 'all' : 'recent',
          requested: turnLimit,
          actual: turns.length,
        ),
      ),
      runtimeSnapshot: runtimeSnapshot,
      turns: turns,
      exportWarnings: exportWarnings,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getSceneSettingCandidates(
      int adventureId, int branchId) async {
    final db = await _getDb();
    return db.query('scene_setting_candidates',
        where: 'adventure_id = ? AND branch_id = ?',
        whereArgs: [adventureId, branchId],
        orderBy: 'created_at ASC');
  }

  @override
  Future<List<Message>> getMessagesByBranch(
      int adventureId, int branchId) async {
    final db = await _getDb();
    final rows = await db.query('messages',
        where: 'adventure_id = ? AND branch_id = ?',
        whereArgs: [adventureId, branchId],
        orderBy: 'timestamp ASC');
    return rows
        .map((r) => Message(
              id: r['id'].toString(),
              content: r['content'] as String,
              reasoningContent: r['reasoning_content'] as String?,
              isUser: r['role'] == 'user',
              timestamp: DateTime.parse(r['timestamp'] as String),
              isHtml: (r['is_html'] as int?) == 1,
              isEdited: (r['edited'] as int?) == 1,
              errorType: r['error_type'] as String?,
            ))
        .toList();
  }

  // ─── Game State ───

  @override
  Future<void> saveGameState(GameState state) async {
    final db = await _getDb();
    await db.insert('game_state', state.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<GameState?> getGameState(int adventureId) async {
    final db = await _getDb();
    final rows = await db.query('game_state',
        where: 'adventure_id = ?', whereArgs: [adventureId], limit: 1);
    if (rows.isEmpty) return null;
    return GameState.fromMap(rows.first);
  }

  // ─── Summaries ───

  @override
  Future<int> saveSummary(int adventureId, String content, int upToId,
      {int branchId = 0, String? stateSnapshot}) async {
    final db = await _getDb();
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('summaries', {
      'adventure_id': adventureId,
      'content': content,
      'up_to_id': upToId,
      'branch_id': branchId,
      'state_snapshot': stateSnapshot,
      'created_at': now,
    });
    return id;
  }

  @override
  Future<String?> getLatestSummary(int adventureId, {int branchId = 0}) async {
    final db = await _getDb();
    final rows = await db.query('summaries',
        where: 'adventure_id = ? AND branch_id = ?',
        whereArgs: [adventureId, branchId],
        orderBy: 'id DESC',
        limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['content'] as String;
  }

  @override
  Future<int> getLatestSummaryUpToId(int adventureId,
      {int branchId = 0}) async {
    final db = await _getDb();
    final rows = await db.query('summaries',
        where: 'adventure_id = ? AND branch_id = ?',
        whereArgs: [adventureId, branchId],
        orderBy: 'id DESC',
        limit: 1);
    if (rows.isEmpty) return 0;
    return rows.first['up_to_id'] as int;
  }

  @override
  Future<Map<String, dynamic>?> getLatestSummaryWithSnapshot(int adventureId,
      {int branchId = 0}) async {
    final db = await _getDb();
    final rows = await db.query('summaries',
        where: 'adventure_id = ? AND branch_id = ?',
        whereArgs: [adventureId, branchId],
        orderBy: 'id DESC',
        limit: 1);
    if (rows.isEmpty) return null;
    return {
      'content': rows.first['content'] as String,
      'state_snapshot': rows.first['state_snapshot'] as String?,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getSummaries(int adventureId) async {
    final db = await _getDb();
    return db.query('summaries',
        where: 'adventure_id = ?', whereArgs: [adventureId], orderBy: 'id ASC');
  }

  @override
  Future<void> cleanupOldSummaries(int adventureId,
      {int branchId = 0, int maxKeep = 5}) async {
    final db = await _getDb();
    final all = await db.query('summaries',
        where: 'adventure_id = ? AND branch_id = ?',
        whereArgs: [adventureId, branchId],
        orderBy: 'id DESC');
    if (all.length > maxKeep) {
      final batch = db.batch();
      for (final row in all.skip(maxKeep)) {
        batch.delete('summaries', where: 'id = ?', whereArgs: [row['id']]);
      }
      await batch.commit(noResult: true);
    }
  }

  // ─── Branches ───

  @override
  Future<int> createBranch({
    required int adventureId,
    int? parentId,
    required int forkAfterId,
    String name = '',
  }) async {
    final db = await _getDb();
    final now = DateTime.now().toIso8601String();
    late final int id;
    await db.transaction((txn) async {
      id = await txn.insert('branches', {
        'adventure_id': adventureId,
        'parent_id': parentId,
        'fork_after_id': forkAfterId,
        'name': name.isNotEmpty ? name : '分支 ${now.substring(11, 19)}',
        'created_at': now,
      });
      final presenceTable = await txn.query('sqlite_master',
          columns: const ['name'],
          where: "type = 'table' AND name = ?",
          whereArgs: ['scene_presence'],
          limit: 1);
      if (presenceTable.isNotEmpty) {
        final sourceBranch = parentId ?? 0;
        final presence = await txn.query('scene_presence',
            where: 'adventure_id = ? AND branch_id = ?',
            whereArgs: [adventureId, sourceBranch],
            limit: 1);
        if (presence.isNotEmpty) {
          await txn.insert(
              'scene_presence',
              {
                ...presence.first,
                'branch_id': id,
                'updated_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      final membershipTable = await txn.query(
        'sqlite_master',
        columns: const ['name'],
        where: "type = 'table' AND name = ?",
        whereArgs: ['adventure_character_memberships'],
        limit: 1,
      );
      if (membershipTable.isNotEmpty) {
        final memberships = await txn.query(
          'adventure_character_memberships',
          where: 'adventure_id = ? AND branch_id = ?',
          whereArgs: [adventureId, parentId ?? 0],
        );
        for (final membership in memberships) {
          await txn.insert(
            'adventure_character_memberships',
            {
              ...membership,
              'branch_id': id,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      final runtimeTable = await txn.query('sqlite_master',
          columns: const ['name'],
          where: "type = 'table' AND name = ?",
          whereArgs: ['scene_runtime_state'],
          limit: 1);
      if (runtimeTable.isNotEmpty) {
        final sourceBranch = parentId ?? 0;
        final runtimeState = await txn.query(
          'scene_runtime_state',
          where: 'adventure_id = ? AND branch_id = ?',
          whereArgs: [adventureId, sourceBranch],
          limit: 1,
        );
        if (runtimeState.isNotEmpty) {
          await txn.insert(
            'scene_runtime_state',
            {
              ...runtimeState.first,
              'branch_id': id,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      // The state archive is retained when a branch is removed, because a
      // descendant can still reference its commits. Only HEAD overlays clone.
      final sourceBranch = parentId ?? 0;
      final runtimeHead = await txn.query('adventure_runtime_heads',
          where: 'adventure_id = ? AND branch_id = ?',
          whereArgs: [adventureId, sourceBranch],
          limit: 1);
      if (runtimeHead.isNotEmpty) {
        await txn.insert(
            'adventure_runtime_heads',
            {
              ...runtimeHead.single,
              'branch_id': id,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
        final entities = await txn.query('adventure_runtime_entities',
            where: 'adventure_id = ? AND branch_id = ?',
            whereArgs: [adventureId, sourceBranch]);
        for (final entity in entities) {
          await txn.insert(
              'adventure_runtime_entities',
              {
                ...entity,
                'branch_id': id,
                'updated_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
    return id;
  }

  @override
  Future<List<Map<String, dynamic>>> getBranches(int adventureId) async {
    final db = await _getDb();
    return db.query('branches',
        where: 'adventure_id = ?',
        whereArgs: [adventureId],
        orderBy: 'created_at ASC');
  }

  @override
  Future<void> deleteBranch(int id) async {
    final db = await _getDb();
    final branch =
        await db.query('branches', where: 'id = ?', whereArgs: [id], limit: 1);
    if (branch.isNotEmpty) {
      final advId = branch.first['adventure_id'] as int;
      await db.delete('bookmarks',
          where: 'adventure_id = ? AND message_id IN '
              '(SELECT id FROM messages WHERE branch_id = ?)',
          whereArgs: [advId, id]);
      await db.delete('summaries',
          where: 'adventure_id = ? AND branch_id = ?', whereArgs: [advId, id]);
      await db.delete('messages', where: 'branch_id = ?', whereArgs: [id]);
      await db.delete('adventure_runtime_entities',
          where: 'adventure_id = ? AND branch_id = ?', whereArgs: [advId, id]);
      await db.delete('adventure_runtime_heads',
          where: 'adventure_id = ? AND branch_id = ?', whereArgs: [advId, id]);
    }
    await db.delete('branches', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Equipment (v15) ───

  @override
  Future<List<Map<String, dynamic>>> getEquipment(int adventureId) async {
    final db = await _getDb();
    return db.query('equipment',
        where: 'adventure_id = ?', whereArgs: [adventureId]);
  }

  @override
  Future<void> saveEquipment(Map<String, dynamic> equipment) async {
    final db = await _getDb();
    await db.insert('equipment', equipment,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<Map<String, dynamic>>> getEquippedItems(
      int adventureId, String charId) async {
    final db = await _getDb();
    return db.query('equipment',
        where: 'adventure_id = ? AND owner_character_id = ?',
        whereArgs: [adventureId, charId]);
  }

  // ─── Inventory Items (v15) ───

  @override
  Future<List<Map<String, dynamic>>> getInventoryItems(int adventureId) async {
    final db = await _getDb();
    return db.query('inventory_items',
        where: 'adventure_id = ?', whereArgs: [adventureId]);
  }

  @override
  Future<List<Map<String, dynamic>>> getInventoryItemsByCharacter(
      int adventureId, String? characterId) async {
    final db = await _getDb();
    if (characterId == null || characterId.isEmpty) {
      return db.query('inventory_items',
          where:
              'adventure_id = ? AND (owner_character_id IS NULL OR owner_character_id = ?)',
          whereArgs: [adventureId, '']);
    }
    return db.query('inventory_items',
        where: 'adventure_id = ? AND owner_character_id = ?',
        whereArgs: [adventureId, characterId]);
  }

  @override
  Future<int> saveInventoryItem(Map<String, dynamic> item) async {
    final db = await _getDb();
    // Check if item already exists (same item_id + adventure)
    final existing = await db.query('inventory_items',
        where: 'adventure_id = ? AND item_id = ?',
        whereArgs: [item['adventure_id'], item['item_id']],
        limit: 1);
    if (existing.isNotEmpty) {
      // Update quantity
      final currentQty = existing.first['quantity'] as int? ?? 0;
      final addQty = item['quantity'] as int? ?? 1;
      await db.update('inventory_items', {'quantity': currentQty + addQty},
          where: 'id = ?', whereArgs: [existing.first['id']]);
      return existing.first['id'] as int;
    }
    final id = await db.insert('inventory_items', item,
        conflictAlgorithm: ConflictAlgorithm.replace);
    return id;
  }

  @override
  Future<void> deleteInventoryItem(int id) async {
    final db = await _getDb();
    await db.delete('inventory_items', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> updateInventoryItem(int id, Map<String, dynamic> updates) async {
    final db = await _getDb();
    await db
        .update('inventory_items', updates, where: 'id = ?', whereArgs: [id]);
  }
}
