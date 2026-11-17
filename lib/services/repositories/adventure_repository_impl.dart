import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../application/resources/resource_trash_service.dart';
import '../../application/adventure/adventure_character_identity.dart';
import '../../application/adventure/adventure_tracked_state_registry.dart';
import '../../core/utils/json_value_reader.dart';
import '../../domain/events/app_event.dart';
import '../../domain/events/app_event_codec.dart';
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

part 'adventure_repository_impl.runtime.dart';
part 'adventure_repository_impl.runtime_mutation.dart';
part 'adventure_repository_impl.scene.dart';
part 'adventure_repository_impl.archive.dart';
part 'adventure_repository_impl.diagnostics.dart';

/// Shared database access plus the helpers that more than one store needs.
///
/// The concrete stores are mixins in `part` files: they share this library's
/// privacy (they are one implementation authority) but keep each SQL subdomain
/// in its own file.
abstract class _AdventureRepositoryBase implements IAdventureRepository {
  _AdventureRepositoryBase({
    required Future<Database> Function() getDb,
    ResourceTrashService? trashService,
  })  : _getDb = getDb,
        _trashService = trashService;

  final Future<Database> Function() _getDb;
  final ResourceTrashService? _trashService;

  // Cross-store turn/runtime helpers, implemented by the runtime stores.
  RuntimeStateCommitDraft? _mergeRuntimeDrafts({
    required RuntimeStateCommitDraft? explicit,
    required RuntimeStateCommitDraft? legacy,
  });

  RuntimeStateCommitDraft? _legacyRuntimeDraft(
    SceneDialogueEffects effects,
    AdventureConfig? config,
  );

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
  });

  Future<GameState> _applyProtagonistRuntimeState(
    Transaction txn, {
    required int adventureId,
    required int branchId,
    required AdventureConfig? config,
    required GameState current,
  });

  bool _runtimeEquals(Object? first, Object? second);

  // Cross-store reads used by diagnostics.
  @override
  Future<RuntimeHead> getRuntimeHead(int adventureId, int branchId);

  @override
  Future<List<RuntimeEntityState>> getRuntimeEntities(
      int adventureId, int branchId,
      {int? limit});

  @override
  Future<SceneState?> getSceneState(int adventureId, int branchId);
}

// Markers share the existing trash lifecycle, but never share resource ids.
const _liveAdventure = """
  NOT EXISTS (
    SELECT 1 FROM resource_trash t
    WHERE t.node_id = 'adventure:' || adventures.id
      AND t.restored_at IS NULL
      AND t.resource_id = 'adventure:' || adventures.id
  )
""";

Future<String> _liveAdventureFilter(DatabaseExecutor db) async {
  // Migration acceptance and recovery can read pre-v41 databases. Those
  // databases cannot contain trash markers, so keep their read path valid.
  final tables = await db.query('sqlite_master',
      columns: ['name'],
      where: 'type = ? AND name = ?',
      whereArgs: ['table', 'resource_trash'],
      limit: 1);
  return tables.isEmpty ? '1 = 1' : _liveAdventure;
}

// Legacy Dart ISO timestamps omit the local offset. SQLite otherwise treats
// them as UTC, shifting the calendar date when the UI converts back to local.
// Explicit offsets/Z already describe an instant and must not be converted.
String _activityInstant(String column) => """
  CASE WHEN upper(substr($column, -1)) = 'Z'
    OR (substr($column, -6, 1) IN ('+', '-')
        AND substr($column, -3, 1) = ':')
    THEN julianday($column)
    ELSE julianday($column, 'utc') END
""";

RuntimeEntityType? _runtimeEntityType(Object? raw) {
  final name = raw is String ? raw : null;
  if (name == null) return null;
  for (final type in RuntimeEntityType.values) {
    if (type.name == name) return type;
  }
  return null;
}

/// Decodes `state_json`; returns null when it is not a JSON object.
Map<String, Object?>? _decodeRuntimeOverlay(Object? raw) {
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
SceneState? _decodeSceneStateForCommit(Object? raw) {
  final text = raw is String ? raw : JsonValueReader.stringScalar(raw);
  if (text == null) return null;
  final state = SceneState.tryDecode(text);
  if (state == null) {
    debugPrint(
        '[AdventureRepository] skipping malformed scene state row during commit');
  }
  return state;
}

Object? _decodeJsonValue(Object? raw) {
  if (raw is! String) return null;
  try {
    return jsonDecode(raw);
  } catch (_) {
    return null;
  }
}

Map<String, Object?> _decodeMap(Object? raw) {
  if (raw is! String) return const {};
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, Object?>.from(decoded) : const {};
  } catch (_) {
    return const {};
  }
}

class AdventureRepositoryImpl extends _AdventureRepositoryBase
    with
        _AdventureRuntimeStore,
        _AdventureRuntimeMutationStore,
        _AdventureSceneTurnStore,
        _AdventureArchiveStore,
        _AdventureDiagnosticsStore
    implements IAdventureRepository {
  AdventureRepositoryImpl({
    required super.getDb,
    super.trashService,
  });

  @override
  Future<int> createAdventure(String title, AdventureConfig config) async {
    final db = await _getDb();
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await db.insert('adventures', {
      'title': title,
      'config': jsonEncode(config.toJson()),
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  @override
  Future<List<Map<String, dynamic>>> getAdventures() async {
    final db = await _getDb();
    final liveAdventure = await _liveAdventureFilter(db);
    // Compare instants rather than ISO strings, which may use different offsets.
    // The empty updated_at written by old migrations falls back to creation.
    return db.rawQuery("""
      SELECT recent.*, strftime('%Y-%m-%dT%H:%M:%fZ', activity, 'julianday')
        AS recent_activity_at
      FROM (
        SELECT adventures.*, MAX(
          COALESCE(${_activityInstant('adventures.updated_at')}, 0),
          COALESCE((SELECT MAX(${_activityInstant('timestamp')}) FROM messages
            WHERE adventure_id = adventures.id), 0),
          COALESCE(${_activityInstant('adventures.created_at')}, 0)
        ) AS activity
        FROM adventures WHERE $liveAdventure
      ) recent
      ORDER BY activity DESC, id DESC
    """);
  }

  @override
  Future<Map<String, dynamic>?> getAdventureById(int id) async {
    final db = await _getDb();
    final liveAdventure = await _liveAdventureFilter(db);
    final rows = await db.query(
      'adventures',
      where: 'id = ? AND $liveAdventure',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  @override
  Future<void> renameAdventure(int id, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(title, 'title');
    final db = await _getDb();
    final liveAdventure = await _liveAdventureFilter(db);
    final changed = await db.update('adventures', {'title': trimmed},
        where: 'id = ? AND $liveAdventure', whereArgs: [id]);
    if (changed == 0) throw StateError('冒险不存在或已移至回收站');
  }

  @override
  Future<void> markAdventureOpened(int id) async {
    final db = await _getDb();
    final liveAdventure = await _liveAdventureFilter(db);
    final changed = await db.update(
        'adventures', {'updated_at': DateTime.now().toUtc().toIso8601String()},
        where: 'id = ? AND $liveAdventure', whereArgs: [id]);
    if (changed == 0) throw StateError('冒险不存在或已移至回收站');
  }

  @override
  Future<void> moveAdventureToTrash(int id) async {
    final trash = _trashService;
    if (trash == null) throw StateError('冒险回收站服务未配置');
    final db = await _getDb();
    final rows = await db.query('adventures',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) throw StateError('冒险不存在');
    await trash.deleteLegacyOnlyResource(
      resourceId: 'adventure:$id',
      markerNodeId: 'adventure:$id',
      sourceTable: 'adventures',
      sourceId: '$id',
      title: rows.single['title'] as String,
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
}
