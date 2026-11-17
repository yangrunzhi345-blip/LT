part of 'adventure_repository_impl.dart';

mixin _AdventureArchiveStore on _AdventureRepositoryBase {
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
