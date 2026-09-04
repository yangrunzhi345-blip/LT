import 'package:sqflite/sqflite.dart';
import 'library_repository.dart';
import '../../data/skill_presets.dart';
import '../../models/resource_library_mode.dart';
import '../resource_integrity_validator.dart';

class LibraryRepositoryImpl implements ILibraryRepository {
  final Future<Database> Function() _getDb;

  LibraryRepositoryImpl({required Future<Database> Function() getDb})
      : _getDb = getDb;

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
      return db.query(table, orderBy: orderBy);
    }
    return db.query(
      table,
      where: 'mode = ?',
      whereArgs: [mode.storageValue],
      orderBy: orderBy,
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
      return db.query(
        table,
        where: textWhere,
        whereArgs: textArgs,
        orderBy: orderBy,
      );
    }
    return db.query(
      table,
      where: 'mode = ? AND ($textWhere)',
      whereArgs: [mode.storageValue, ...textArgs],
      orderBy: orderBy,
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
  Future<void> deleteWorldviewPreset(
    String id, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    final db = await _getDb();
    await _deleteByMode(db, 'worldview_presets', id, mode);
  }

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
            },
            mode),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteCharacterCard(
    String id, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    final db = await _getDb();
    await _deleteByMode(db, 'character_cards', id, mode);
  }

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
            'created_at': now,
            'updated_at': now,
          },
          mode),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteNpcCard(
    String id, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    final db = await _getDb();
    await _deleteByMode(db, 'npc_cards', id, mode);
  }

  @override
  Future<int> saveCardBatch({
    required LibraryCardType type,
    required List<LibraryCardBatchItem> items,
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    if (items.isEmpty) return 0;
    final db = await _getDb();
    final table =
        type == LibraryCardType.character ? 'character_cards' : 'npc_cards';
    final saved = await db.transaction<int>((txn) async {
      final hasMode = await _hasModeColumn(txn, table);
      var count = 0;
      for (final item in items) {
        if (type == LibraryCardType.character) {
          ResourceIntegrityValidator.validateCharacterCard(
            name: item.name,
            jsonData: item.jsonData,
          );
        } else {
          ResourceIntegrityValidator.validateNpcCard(
            name: item.name,
            jsonData: item.jsonData,
          );
        }
        if (item.contentHash.isNotEmpty) {
          final duplicate = await txn.query(
            table,
            columns: const ['id'],
            where:
                hasMode ? 'content_hash = ? AND mode = ?' : 'content_hash = ?',
            whereArgs: hasMode
                ? [item.contentHash, mode.storageValue]
                : [item.contentHash],
            limit: 1,
          );
          if (duplicate.isNotEmpty) continue;
        }
        final values = <String, Object?>{
          'id': item.id,
          'name': item.name,
          'json_data': item.jsonData,
          'source': item.source,
          'matching_worldview_id': item.matchingWorldviewId,
          'content_hash': item.contentHash,
          'created_at': item.now,
          'updated_at': item.now,
          if (hasMode) 'mode': mode.storageValue,
        };
        if (type == LibraryCardType.character) values['weight'] = '';
        await txn.insert(
          table,
          values,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        count++;
      }
      return count;
    });
    if (saved > 0) {
    }
    return saved;
  }

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
  Future<Map<String, dynamic>?> getSkillById(String id) async {
    final db = await _getDb();
    final rows =
        await db.query('skills', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<void> saveSkill(Map<String, dynamic> skill) async {
    final db = await _getDb();
    await db.insert('skills', skill,
        conflictAlgorithm: ConflictAlgorithm.replace);
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
