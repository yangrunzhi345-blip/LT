import 'package:sqflite/sqflite.dart';
import 'library_repository.dart';
import '../../application/resources/legacy_tombstone_store.dart';
import '../../data/skill_presets.dart';
import '../../models/resource_library_mode.dart';

class LibraryRepositoryImpl implements ILibraryRepository {
  final Future<Database> Function() _getDb;

  LibraryRepositoryImpl({
    required Future<Database> Function() getDb,
    LegacyTombstoneStore? tombstoneStore,
  })  : _getDb = getDb,
        _tombstoneStore = tombstoneStore;

  /// Legacy tombstone markers.
  ///
  /// Required for the delete paths: a legacy row has no soft-delete column, so
  /// deleting it means writing a tombstone instead of physically removing it.
  /// Reads treat a missing store as "nothing is in the bin", which is harmless.
  final LegacyTombstoneStore? _tombstoneStore;

  Future<bool> _hasModeColumn(DatabaseExecutor db, String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.any((c) => c['name'] == 'mode');
  }

  Future<List<Map<String, dynamic>>> _queryByMode(
    Database db,
    String table, {
    required ResourceLibraryMode mode,
    required String orderBy,
  }) async {
    if (!await _hasModeColumn(db, table)) {
      if (mode != ResourceLibraryMode.adventure) {
        return <Map<String, dynamic>>[];
      }
      return _hideTrashed(db, table, await db.query(table, orderBy: orderBy));
    }
    return _hideTrashed(
      db,
      table,
      await db.query(
        table,
        where: 'mode = ?',
        whereArgs: [mode.storageValue],
        orderBy: orderBy,
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _searchByMode(
    Database db,
    String table, {
    required String query,
    required ResourceLibraryMode mode,
    required String orderBy,
    required List<String> columns,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return _queryByMode(db, table, mode: mode, orderBy: orderBy);
    }
    final like = '%$trimmed%';
    final textWhere = columns.map((column) => '$column LIKE ?').join(' OR ');
    final textArgs = List<Object?>.filled(columns.length, like);
    if (!await _hasModeColumn(db, table)) {
      if (mode != ResourceLibraryMode.adventure) {
        return <Map<String, dynamic>>[];
      }
      return _hideTrashed(
        db,
        table,
        await db.query(
          table,
          where: textWhere,
          whereArgs: textArgs,
          orderBy: orderBy,
        ),
      );
    }
    return _hideTrashed(
      db,
      table,
      await db.query(
        table,
        where: 'mode = ? AND ($textWhere)',
        whereArgs: [mode.storageValue, ...textArgs],
        orderBy: orderBy,
      ),
    );
  }

  /// Drops rows whose resource is currently in the recycle bin.
  ///
  /// Phase 9 stopped deleting legacy rows, so a binned resource disappears from
  /// the library by filtering rather than by removal. Without this a deleted
  /// resource would keep showing up, which is exactly the "delete appears to do
  /// nothing" failure mode the reroute is meant to avoid.
  Future<List<Map<String, dynamic>>> _hideTrashed(
    DatabaseExecutor db,
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    final store = _tombstoneStore;
    if (store == null || rows.isEmpty) return rows;
    final hidden = await store.activeNodeIds(
      sourceTable: table,
      candidateIds: rows.map((row) => row['id']?.toString() ?? ''),
    );
    if (hidden.isEmpty) return rows;
    return rows
        .where((row) => !hidden.contains(row['id']?.toString() ?? ''))
        .toList();
  }

  /// Moves one library row's content into the recycle bin.
  ///
  /// Deliberately has no destructive fallback: if the Phase 9 bridge is missing
  /// the delete fails loudly instead of silently falling back to the legacy
  /// `DELETE` it replaced. A `mode` is not needed — bin entries are keyed by
  /// resource/node id, and legacy ids are unique per row.
  Future<void> _moveToTrash(String table, String id) async {
    final store = _tombstoneStore;
    if (store == null) {
      throw StateError(
        '资源删除需要旧表墓碑存储（LegacyTombstoneStore），未接线时拒绝删除以避免不可逆数据损失',
      );
    }
    await store.markDeleted(
      nodeId: id,
      sourceTable: table,
      sourceId: id,
      title: '',
    );
  }

  /// Deletes one row of a non-resource library table.
  ///
  /// Kept for `prompt_presets` / `adventure_templates`, which hold configuration
  /// rather than user-authored resource content and are outside Phase 9's
  /// recoverability scope. Resource tables must go through [_moveToTrash].
  Future<void> _deleteByMode(
    Database db,
    String table,
    String id,
    ResourceLibraryMode mode,
  ) async {
    if (!await _hasModeColumn(db, table)) {
      if (mode == ResourceLibraryMode.adventure) {
        await db.delete(table, where: 'id = ?', whereArgs: [id]);
      }
      return;
    }
    await db.delete(
      table,
      where: 'id = ? AND mode = ?',
      whereArgs: [id, mode.storageValue],
    );
  }

  Future<Map<String, Object?>> _withModeIfPresent(
    Database db,
    String table,
    Map<String, Object?> values,
    ResourceLibraryMode mode,
  ) async {
    if (!await _hasModeColumn(db, table)) return values;
    return {...values, 'mode': mode.storageValue};
  }

  // ─── Worldview Presets ───

  @override
  Future<List<Map<String, dynamic>>> getWorldviewPresets({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    final db = await _getDb();
    return _queryByMode(db, 'worldview_presets',
        mode: mode, orderBy: 'updated_at DESC');
  }

  @override
  Future<List<Map<String, dynamic>>> searchWorldviewPresets(
    String query, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    final db = await _getDb();
    return _searchByMode(
      db,
      'worldview_presets',
      query: query,
      mode: mode,
      orderBy: 'updated_at DESC',
      columns: const ['name', 'description', 'source'],
    );
  }

  @override
  Future<void> saveWorldviewPreset({
    required String id,
    required String name,
    required String description,
    required String entriesJson,
    required String now,
    String source = '',
    String contentHash = '',
    String detailJson = '{}',
    String authoringMethod = '',
    String aiGenerationDepth = '',
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    final db = await _getDb();
    await db.insert(
      'worldview_presets',
      await _withModeIfPresent(
          db,
          'worldview_presets',
          {
            'id': id,
            'name': name,
            'description': description,
            'entries_json': entriesJson,
            'source': source,
            'created_at': now,
            'updated_at': now,
            'content_hash': contentHash,
            'detail_json': detailJson,
            'authoring_method': authoringMethod,
            'ai_generation_depth': aiGenerationDepth,
            'detail_search_text':
                _worldviewSearchText(name, description, detailJson),
          },
          mode),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  String _worldviewSearchText(
      String name, String description, String detailJson) {
    return '$name\n$description\n$detailJson'
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @override

  /// Moves the content behind this row into the recycle bin.
  ///
  /// Phase 9 replaced the previous "soft delete the tree + hard delete the
  /// legacy row" pair: a delete must now be recoverable, and the legacy row may
  /// still be the only copy of a resource whose migration has not happened,
  /// failed, or gone stale.
  Future<void> deleteWorldviewPreset(
    String id, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _moveToTrash('worldview_presets', id);

  @override
  Future<void> seedDefaultWorldviews() async {
    // 纯净版：不预置任何世界观预设
  }

  // ─── Character Cards ───

  @override
  Future<List<Map<String, dynamic>>> getCharacterCards({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    final db = await _getDb();
    return _queryByMode(db, 'character_cards',
        mode: mode, orderBy: 'updated_at DESC');
  }

  @override
  Future<List<Map<String, dynamic>>> searchCharacterCards(
    String query, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    final db = await _getDb();
    return _searchByMode(
      db,
      'character_cards',
      query: query,
      mode: mode,
      orderBy: 'updated_at DESC',
      columns: const ['name', 'json_data', 'source'],
    );
  }

  @override
  Future<void> saveCharacterCard({
    required String id,
    required String name,
    required String jsonData,
    required String source,
    required String now,
    String matchingWorldviewId = '',
    String weight = '',
    String contentHash = '',
    String authoringMethod = '',
    String aiGenerationDepth = '',
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    final db = await _getDb();
    await db.insert(
        'character_cards',
        await _withModeIfPresent(
            db,
            'character_cards',
            {
              'id': id,
              'name': name,
              'json_data': jsonData,
              'source': source,
              'matching_worldview_id': matchingWorldviewId,
              'weight': weight,
              'created_at': now,
              'updated_at': now,
              'content_hash': contentHash,
              'authoring_method': authoringMethod,
              'ai_generation_depth': aiGenerationDepth,
            },
            mode),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override

  /// See [deleteWorldviewPreset]: routed through the recycle bin.
  Future<void> deleteCharacterCard(
    String id, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _moveToTrash('character_cards', id);

  @override
  Future<void> seedDefaultCharacterCards() async {
    // 纯净版：不预置任何角色卡
  }

  // ─── Prompt Presets ───

  @override
  Future<List<Map<String, dynamic>>> getPromptPresets({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    final db = await _getDb();
    return _queryByMode(db, 'prompt_presets', mode: mode, orderBy: 'name ASC');
  }

  @override
  Future<void> savePromptPreset({
    required String id,
    required String name,
    required String systemPrompt,
    required String authorsNote,
    required int noteDepth,
    required int noteFrequency,
    required String now,
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    final db = await _getDb();
    await db.insert(
        'prompt_presets',
        await _withModeIfPresent(
            db,
            'prompt_presets',
            {
              'id': id,
              'name': name,
              'system_prompt': systemPrompt,
              'authors_note': authorsNote,
              'note_depth': noteDepth,
              'note_frequency': noteFrequency,
              'created_at': now
            },
            mode),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deletePromptPreset(
    String id, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    final db = await _getDb();
    await _deleteByMode(db, 'prompt_presets', id, mode);
  }

  // ─── Personas ───

  @override
  Future<List<Map<String, dynamic>>> getPersonas() async {
    final db = await _getDb();
    return db.query('personas', orderBy: 'name ASC');
  }

  @override
  Future<void> savePersona({
    required String id,
    required String name,
    required String jsonData,
    required String now,
  }) async {
    final db = await _getDb();
    await db.insert('personas',
        {'id': id, 'name': name, 'json_data': jsonData, 'created_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deletePersona(String id) async {
    final db = await _getDb();
    await db.delete('personas', where: 'id=?', whereArgs: [id]);
  }

  // ─── Adventure Templates ───

  @override
  Future<List<Map<String, dynamic>>> getAdventureTemplates({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    final db = await _getDb();
    return _queryByMode(db, 'adventure_templates',
        mode: mode, orderBy: 'created_at DESC');
  }

  @override
  Future<List<Map<String, dynamic>>> searchAdventureTemplates(
    String query, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    final db = await _getDb();
    return _searchByMode(
      db,
      'adventure_templates',
      query: query,
      mode: mode,
      orderBy: 'created_at DESC',
      columns: const ['name', 'worldview_name', 'worldview_desc'],
    );
  }

  @override
  Future<void> saveAdventureTemplate({
    required String id,
    required String name,
    required String worldviewName,
    required String worldviewDesc,
    required String charDataJson,
    required String npcDataJson,
    required String createdAt,
    String status = 'draft',
    String updatedAt = '',
    String contentHash = '',
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    final db = await _getDb();
    await db.insert(
      'adventure_templates',
      await _withModeIfPresent(
          db,
          'adventure_templates',
          {
            'id': id,
            'name': name,
            'worldview_name': worldviewName,
            'worldview_desc': worldviewDesc,
            'char_data_json': charDataJson,
            'npc_data_json': npcDataJson,
            'status': status,
            'updated_at': updatedAt.isNotEmpty ? updatedAt : createdAt,
            'created_at': createdAt,
            'content_hash': contentHash,
          },
          mode),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteAdventureTemplate(
    String id, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    final db = await _getDb();
    await _deleteByMode(db, 'adventure_templates', id, mode);
  }

  @override
  Future<void> updateTemplateStatus(
    String id,
    String status, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    final db = await _getDb();
    final hasMode = await _hasModeColumn(db, 'adventure_templates');
    await db.update(
      'adventure_templates',
      {
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: hasMode ? 'id = ? AND mode = ?' : 'id = ?',
      whereArgs: hasMode ? [id, mode.storageValue] : [id],
    );
  }

  // ─── NPC Cards (v11) ───

  @override
  Future<List<Map<String, dynamic>>> getNpcCards({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    final db = await _getDb();
    return _queryByMode(db, 'npc_cards',
        mode: mode, orderBy: 'updated_at DESC');
  }

  @override
  Future<List<Map<String, dynamic>>> searchNpcCards(
    String query, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    final db = await _getDb();
    return _searchByMode(
      db,
      'npc_cards',
      query: query,
      mode: mode,
      orderBy: 'updated_at DESC',
      columns: const ['name', 'json_data', 'source'],
    );
  }

  @override
  Future<void> saveNpcCard({
    required String id,
    required String name,
    required String jsonData,
    required String source,
    required String now,
    String matchingWorldviewId = '',
    String contentHash = '',
    String authoringMethod = '',
    String aiGenerationDepth = '',
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    final db = await _getDb();
    await db.insert(
      'npc_cards',
      await _withModeIfPresent(
          db,
          'npc_cards',
          {
            'id': id,
            'name': name,
            'json_data': jsonData,
            'source': source,
            'matching_worldview_id': matchingWorldviewId,
            'content_hash': contentHash,
            'authoring_method': authoringMethod,
            'ai_generation_depth': aiGenerationDepth,
            'created_at': now,
            'updated_at': now,
          },
          mode),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override

  /// See [deleteWorldviewPreset]: routed through the recycle bin.
  Future<void> deleteNpcCard(
    String id, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _moveToTrash('npc_cards', id);

  // ─── Import Records (v12) ───

  @override
  Future<List<Map<String, dynamic>>> getImportRecords({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    final db = await _getDb();
    return _queryByMode(db, 'import_records',
        mode: mode, orderBy: 'created_at DESC');
  }

  @override
  Future<void> saveImportRecord({
    required String fileName,
    required String fileType,
    required String importType,
    required String resultSummary,
    required String createdAt,
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    final db = await _getDb();
    await db.insert(
        'import_records',
        await _withModeIfPresent(
            db,
            'import_records',
            {
              'file_name': fileName,
              'file_type': fileType,
              'import_type': importType,
              'result_summary': resultSummary,
              'created_at': createdAt,
            },
            mode));
  }

  // ─── Skills (v13) ───

  @override
  Future<List<Map<String, dynamic>>> getAllSkills() async {
    final db = await _getDb();
    return db.query('skills', orderBy: 'name ASC');
  }

  @override
  Future<List<Map<String, dynamic>>> getCharacterSkills(String charId) async {
    final db = await _getDb();
    return db.query('character_skills',
        where: 'character_id = ?', whereArgs: [charId]);
  }

  @override
  Future<int> saveCharacterSkill(Map<String, dynamic> cs) async {
    final db = await _getDb();
    return db.insert('character_skills', cs,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> updateCharacterSkill(
      int id, Map<String, dynamic> updates) async {
    final db = await _getDb();
    await db
        .update('character_skills', updates, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> seedDefaultSkills() async {
    final db = await _getDb();
    final count =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM skills'));
    if (count != null && count > 0) return; // already seeded

    final now = DateTime.now().toIso8601String();
    final skills = SkillPresets.all(now);
    final batch = db.batch();
    for (final s in skills) {
      batch.insert('skills', s, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }
}
