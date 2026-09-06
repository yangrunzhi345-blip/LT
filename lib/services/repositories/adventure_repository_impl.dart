import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../models/adventure_config.dart';
import '../../models/scene_dialogue.dart';
import '../../models/world_entry.dart';
import '../../models/game_state.dart';
import '../../models/message.dart';
import '../../models/narrative_map.dart';
import '../../models/quest.dart';
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

  @override
  Future<void> updateMessageContent(
      int adventureId, String messageId, String newContent) async {
    final db = await _getDb();
    await db.update(
      'messages',
      {'content': newContent, 'edited': 1},
      where: 'id = ? AND adventure_id = ?',
      whereArgs: [messageId, adventureId],
    );
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

      for (final progress in commit.effects.questProgress) {
        final rows = await txn.query('quests',
            where: 'id = ? AND adventure_id = ?',
            whereArgs: [progress.questId, commit.adventureId],
            limit: 1);
        if (rows.isEmpty) continue;
        final quest = Quest.fromRow(rows.single);
        if (progress.objectiveIndex < 0 ||
            progress.objectiveIndex >= quest.objectives.length) {
          continue;
        }
        final objective = quest.objectives[progress.objectiveIndex];
        objective.currentCount = (objective.currentCount + progress.increment)
            .clamp(0, objective.targetCount);
        await txn.update(
            'quests', {'objectives_json': quest.toRow()['objectives_json']},
            where: 'id = ? AND adventure_id = ?',
            whereArgs: [quest.id, commit.adventureId]);
      }

      for (final questId in commit.effects.completedQuestIds) {
        final rows = await txn.query('quests',
            where: 'id = ? AND adventure_id = ?',
            whereArgs: [questId, commit.adventureId],
            limit: 1);
        if (rows.isEmpty) continue;
        final quest = Quest.fromRow(rows.single);
        if (quest.status != QuestStatus.active || quest.progress < 1.0) {
          continue;
        }
        final completedAt = DateTime.now().toIso8601String();
        await txn.update('quests',
            {'status': QuestStatus.completed.name, 'completed_at': completedAt},
            where: 'id = ? AND adventure_id = ?',
            whereArgs: [quest.id, commit.adventureId]);
        var gold = 0;
        var experience = 0;
        for (final reward in quest.rewards) {
          if (reward.type == RewardType.gold) gold += reward.amount;
          if (reward.type == RewardType.exp) experience += reward.amount;
        }
        gameState = gameState.copyWith(
          gold: gameState.gold + gold,
          experience: gameState.experience + experience,
        );
      }

      final trigger = commit.effects.questTriggered;
      if (trigger != null) {
        final objectives = <QuestObjective>[];
        final rawObjectives = trigger['objectives'];
        if (rawObjectives is List) {
          for (final raw in rawObjectives.take(50)) {
            if (raw is! Map) continue;
            final value = Map<String, dynamic>.from(raw);
            final description = value['description']?.toString().trim() ?? '';
            if (description.isEmpty || description.length > 500) continue;
            final target = value['target_count'];
            objectives.add(QuestObjective(
              description: description,
              targetCount: target is num ? target.toInt().clamp(1, 100000) : 1,
              type: ObjectiveType.values.firstWhere(
                (item) => item.name == value['type']?.toString(),
                orElse: () => ObjectiveType.collect,
              ),
              targetId: value['target_id']?.toString(),
            ));
          }
        }
        final rewards = <QuestReward>[];
        final rawRewards = trigger['rewards'];
        if (rawRewards is List) {
          for (final raw in rawRewards.take(50)) {
            if (raw is! Map) continue;
            final value = Map<String, dynamic>.from(raw);
            final amount = value['amount'];
            rewards.add(QuestReward(
              type: RewardType.values.firstWhere(
                (item) => item.name == value['type']?.toString(),
                orElse: () => RewardType.gold,
              ),
              amount: amount is num ? amount.toInt().clamp(0, 100000000) : 0,
              itemId: value['item_id']?.toString(),
              skillId: value['skill_id']?.toString(),
            ));
          }
        }
        final quest = Quest(
          id: 'scene_${commit.requestId}_quest',
          adventureId: commit.adventureId,
          title: trigger['title'].toString().trim(),
          description: trigger['description']?.toString().trim() ?? '',
          type: QuestType.values.firstWhere(
            (item) => item.name == trigger['quest_type']?.toString(),
            orElse: () => QuestType.side,
          ),
          objectives: objectives,
          rewards: rewards,
          giverNpcId: trigger['giver_npc_id']?.toString(),
          createdAt: DateTime.now().toIso8601String(),
        );
        await txn.insert('quests', quest.toRow(),
            conflictAlgorithm: ConflictAlgorithm.ignore);
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

      if (config != null &&
          (commit.effects.affinityChanges.isNotEmpty ||
              commit.effects.deadCharacters.isNotEmpty)) {
        for (final character in config.supportingCharacters) {
          final delta = commit.effects.affinityChanges[character.name];
          if (delta != null) {
            character.affinity = (character.affinity + delta).clamp(0, 100);
            for (int i = 0; i < character.customAttributes.length; i++) {
              final attr = character.customAttributes[i];
              if (attr.name.contains('好感') ||
                  attr.name.toLowerCase().contains('affinity')) {
                final maxVal = attr.maxValue ?? attr.effectiveMaxValue;
                character.customAttributes[i] = attr.copyWith(
                  currentValue: character.affinity,
                  value: attr.value.contains('/') || maxVal == 100
                      ? '${character.affinity}/$maxVal'
                      : '${character.affinity}',
                );
              }
            }
          }
          if (commit.effects.deadCharacters.contains(character.name)) {
            character.isAlive = false;
          }
        }
        await txn.update('adventures', {'config': jsonEncode(config.toJson())},
            where: 'id = ?', whereArgs: [commit.adventureId]);
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
      await txn.insert('scene_dialogue_turns', {
        'request_id': commit.requestId,
        'adventure_id': commit.adventureId,
        'branch_id': commit.branchId,
        'created_at': DateTime.now().toIso8601String(),
        'assistant_client_message_id': commit.assistantMessage.id,
        'context_snapshot_id': commit.contextSnapshotId,
        'diagnostics_json': jsonEncode({
          ...commit.diagnostics,
          if (commit.effects.diagnostics.isNotEmpty)
            'ignored_effects': commit.effects.diagnostics,
          'effect_counts': {
            'quest_progress': commit.effects.questProgress.length,
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
      );
    });
    return result;
  }

  @override
  Future<ScenePresence?> getScenePresence(int adventureId, int branchId) async {
    final db = await _getDb();
    final rows = await db.query('scene_presence',
        where: 'adventure_id = ? AND branch_id = ?',
        whereArgs: [adventureId, branchId],
        limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final ids = (jsonDecode(row['participant_ids_json'] as String) as List)
        .map((e) => e.toString())
        .toList();
    return ScenePresence(
        adventureId: adventureId,
        branchId: branchId,
        actorId: row['actor_id'] as String,
        participantIds: ids);
  }

  @override
  Future<void> saveScenePresence(ScenePresence presence) async {
    final db = await _getDb();
    await db.insert('scene_presence',
        {...presence.toRow(), 'updated_at': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace);
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
  Future<void> updateSceneSettingCandidateStatus(
      String id, SceneSettingCandidateStatus status) async {
    final db = await _getDb();
    await db.update('scene_setting_candidates', {'status': status.name},
        where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<bool> rejectSceneSettingCandidate(
      int adventureId, int branchId, String id) async {
    final db = await _getDb();
    final changed = await db.update('scene_setting_candidates',
        {'status': SceneSettingCandidateStatus.rejected.name},
        where: 'id = ? AND adventure_id = ? AND branch_id = ? AND status = ?',
        whereArgs: [
          id,
          adventureId,
          branchId,
          SceneSettingCandidateStatus.pending.name
        ]);
    return changed == 1;
  }

  @override
  Future<bool> approveSceneNpcCandidate({
    required int adventureId,
    required int branchId,
    required String candidateId,
    required AdventureConfig config,
    required ScenePresence presence,
  }) async {
    final db = await _getDb();
    var applied = false;
    await db.transaction((txn) async {
      final candidate = await txn.query('scene_setting_candidates',
          where: 'id = ? AND adventure_id = ? AND branch_id = ? AND '
              'type = ? AND status = ?',
          whereArgs: [
            candidateId,
            adventureId,
            branchId,
            'npc',
            SceneSettingCandidateStatus.pending.name
          ],
          limit: 1);
      if (candidate.isEmpty ||
          presence.adventureId != adventureId ||
          presence.branchId != branchId) {
        return;
      }
      await txn.update('adventures', {'config': jsonEncode(config.toJson())},
          where: 'id = ?', whereArgs: [adventureId]);
      await txn.insert(
          'scene_presence',
          {
            ...presence.toRow(),
            'updated_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      final changed = await txn.update('scene_setting_candidates',
          {'status': SceneSettingCandidateStatus.acceptedAdventure.name},
          where: 'id = ? AND adventure_id = ? AND branch_id = ? AND status = ?',
          whereArgs: [
            candidateId,
            adventureId,
            branchId,
            SceneSettingCandidateStatus.pending.name
          ]);
      applied = changed == 1;
    });
    if (applied) {
    }
    return applied;
  }

  @override
  Future<int?> approveSceneWorldCandidate({
    required int adventureId,
    required int branchId,
    required String candidateId,
    required WorldEntry entry,
  }) async {
    if (!SceneSettingCandidate.worldSettingTypes.contains(entry.sourceType) ||
        entry.adventureId != adventureId) {
      return null;
    }
    final db = await _getDb();
    int? entryId;
    await db.transaction((txn) async {
      final candidate = await txn.query('scene_setting_candidates',
          where: 'id = ? AND adventure_id = ? AND branch_id = ? AND '
              'status = ?',
          whereArgs: [
            candidateId,
            adventureId,
            branchId,
            SceneSettingCandidateStatus.pending.name,
          ],
          limit: 1);
      if (candidate.isEmpty ||
          !SceneSettingCandidate.worldSettingTypes
              .contains(candidate.first['type'])) {
        return;
      }
      entryId = await txn.insert('world_entries', entry.toDbMap());
      final changed = await txn.update('scene_setting_candidates',
          {'status': SceneSettingCandidateStatus.acceptedAdventure.name},
          where: 'id = ? AND adventure_id = ? AND branch_id = ? AND status = ?',
          whereArgs: [
            candidateId,
            adventureId,
            branchId,
            SceneSettingCandidateStatus.pending.name,
          ]);
      if (changed != 1) throw StateError('场景设定候选状态已变更');
    });
    if (entryId != null) {
    }
    return entryId;
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
    }
    await db.delete('branches', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Quests (v14) ───

  @override
  Future<List<Map<String, dynamic>>> getQuests(int adventureId) async {
    final db = await _getDb();
    return db
        .query('quests', where: 'adventure_id = ?', whereArgs: [adventureId]);
  }

  @override
  Future<void> saveQuest(Map<String, dynamic> quest) async {
    final db = await _getDb();
    await db.insert('quests', quest,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteQuest(String id) async {
    final db = await _getDb();
    await db.delete('quests', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> updateQuest(String id, Map<String, dynamic> updates) async {
    final db = await _getDb();
    await db.update('quests', updates, where: 'id = ?', whereArgs: [id]);
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

  // ─── Map (v15) ───

  @override
  Future<List<Map<String, dynamic>>> getMapNodes(int adventureId) async {
    final db = await _getDb();
    return db.query('map_nodes',
        where: 'adventure_id = ?', whereArgs: [adventureId]);
  }

  @override
  Future<void> saveMapNode(Map<String, dynamic> node) async {
    final db = await _getDb();
    await db.insert('map_nodes', node,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<Map<String, dynamic>>> getMapConnections(int adventureId) async {
    final db = await _getDb();
    return db.query('map_connections',
        where: 'node_a_id IN (SELECT id FROM map_nodes WHERE adventure_id = ?)',
        whereArgs: [adventureId]);
  }

  @override
  Future<void> saveMapConnection(Map<String, dynamic> conn) async {
    final db = await _getDb();
    await db.insert('map_connections', conn,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<NarrativeMapGraph> getNarrativeMap(int adventureId) async {
    final db = await _getDb();
    final nodeRows = await db.rawQuery('''
      SELECT n.*, COALESCE(s.discovery_state, CASE WHEN n.explored = 1 THEN 'visited' ELSE 'discovered' END) AS discovery_state,
             COALESCE(s.availability_state, 'available') AS availability_state
      FROM map_nodes n
      LEFT JOIN adventure_map_node_states s ON s.adventure_id = n.adventure_id AND s.node_id = n.id
      WHERE n.adventure_id = ? ORDER BY n.map_level, n.created_at, n.id
    ''', [adventureId]);
    final connectionRows = await db.rawQuery('''
      SELECT c.*, COALESCE(s.availability_state, c.availability_state, 'available') AS availability_state
      FROM map_connections c
      LEFT JOIN adventure_map_connection_states s ON s.adventure_id = ? AND s.connection_id = c.id
      WHERE c.adventure_id = ? OR c.node_a_id IN (SELECT id FROM map_nodes WHERE adventure_id = ?)
      ORDER BY c.id
    ''', [adventureId, adventureId, adventureId]);
    final state = await db.query('adventure_map_state',
        columns: ['current_node_id'],
        where: 'adventure_id = ?',
        whereArgs: [adventureId],
        limit: 1);
    return NarrativeMapGraph(
      nodes: nodeRows.map(NarrativeMapNode.fromRow).toList(growable: false),
      connections: connectionRows
          .map(NarrativeMapConnection.fromRow)
          .toList(growable: false),
      currentNodeId:
          state.isEmpty ? null : state.first['current_node_id'] as String?,
    );
  }

  @override
  Future<void> bootstrapNarrativeMap(
      int adventureId, List<MapNodeSeed> seeds) async {
    final db = await _getDb();
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final existing = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COUNT(*) FROM map_nodes WHERE adventure_id = ?',
              [adventureId])) ??
          0;
      if (existing > 0) return;
      String? currentNodeId;
      for (var index = 0; index < seeds.length; index++) {
        final seed = seeds[index];
        final id = 'map_${adventureId}_${index + 1}';
        await txn.insert('map_nodes', {
          'id': id,
          'adventure_id': adventureId,
          'name': seed.name,
          'canonical_name': seed.name,
          'display_name': seed.name,
          'icon': seed.icon,
          'node_type': _canonicalLegacyNodeType(seed.type),
          'terrain_type': seed.terrainType.name,
          'description': seed.description,
          'explored': seed.isCurrent ? 1 : 0,
          'x': seed.positionX.clamp(0.0, 1.0),
          'y': seed.positionY.clamp(0.0, 1.0),
          'map_level': 1,
          'position_locked': 0,
          'source_type': 'legacyBootstrap',
          'confidence': seed.isCurrent ? 'confirmed' : 'probable',
          'created_at': now,
          'updated_at': now,
        });
        await txn.insert('adventure_map_node_states', {
          'adventure_id': adventureId,
          'node_id': id,
          'discovery_state': seed.isCurrent ? 'visited' : 'discovered',
          'availability_state': 'available',
          'updated_at': now,
        });
        await txn.insert('map_layouts', {
          'adventure_id': adventureId,
          'node_id': id,
          'map_level': 1,
          'parent_node_id': '',
          'position_x': seed.positionX.clamp(0.0, 1.0),
          'position_y': seed.positionY.clamp(0.0, 1.0),
          'updated_at': now,
        });
        if (seed.isCurrent) currentNodeId = id;
      }
      currentNodeId ??= 'map_${adventureId}_${seeds.length}';
      await txn.insert('adventure_map_state', {
        'adventure_id': adventureId,
        'current_node_id': currentNodeId,
        'updated_at': now,
      });
    });
  }

  @override
  Future<void> mergeNarrativeMapSeeds(
      int adventureId, List<MapNodeSeed> seeds) async {
    if (seeds.isEmpty) return;
    final db = await _getDb();
    final now = DateTime.now().toIso8601String();
    var changed = false;
    await db.transaction((txn) async {
      final existingRows = await txn.rawQuery('''
        SELECT canonical_name AS name FROM map_nodes WHERE adventure_id = ?
        UNION SELECT normalized_alias AS name FROM map_node_aliases WHERE adventure_id = ?
      ''', [adventureId, adventureId]);
      final existing = existingRows
          .map((row) => _normalizeMapName((row['name'] ?? '').toString()))
          .where((name) => name.isNotEmpty)
          .toSet();
      for (final seed in seeds) {
        final normalized = _normalizeMapName(seed.name);
        if (normalized.isEmpty || existing.contains(normalized)) continue;
        final id = _stableMapNodeId(adventureId, normalized);
        await txn.insert(
            'map_nodes',
            {
              'id': id,
              'adventure_id': adventureId,
              'name': seed.name,
              'canonical_name': seed.name,
              'display_name': seed.name,
              'icon': seed.icon,
              'node_type': _canonicalLegacyNodeType(seed.type),
              'terrain_type': seed.terrainType.name,
              'description': seed.description,
              'explored': 0,
              'x': seed.positionX.clamp(0.0, 1.0),
              'y': seed.positionY.clamp(0.0, 1.0),
              'map_level': 1,
              'source_type': 'narrativeExtraction',
              'confidence': 'probable',
              'created_at': now,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
        await txn.insert(
            'adventure_map_node_states',
            {
              'adventure_id': adventureId,
              'node_id': id,
              'discovery_state': 'discovered',
              'availability_state': 'available',
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
        await txn.insert(
            'map_layouts',
            {
              'adventure_id': adventureId,
              'node_id': id,
              'map_level': 1,
              'parent_node_id': '',
              'position_x': seed.positionX.clamp(0.0, 1.0),
              'position_y': seed.positionY.clamp(0.0, 1.0),
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
        await txn.insert(
            'map_extraction_candidates',
            {
              'id': 'candidate_$id',
              'adventure_id': adventureId,
              'candidate_name': seed.name,
              'normalized_name': normalized,
              'event_type': 'discover',
              'confidence': .65,
              'status': 'accepted',
              'proposal_json': encodeMapJson({'nodeId': id, 'source': 'rule'}),
              'created_at': now,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
        existing.add(normalized);
        changed = true;
      }
    });
    if (changed) {
    }
  }

  @override
  Future<void> ensureNarrativeMapState(
      int adventureId, String currentName) async {
    final db = await _getDb();
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final nodes = await txn.query('map_nodes',
          where: 'adventure_id = ?', whereArgs: [adventureId], orderBy: 'id');
      if (nodes.isEmpty) return;
      String? currentNodeId;
      for (final node in nodes) {
        final id = node['id']! as String;
        final name = (node['display_name'] ?? node['name'] ?? '').toString();
        final isCurrent = currentName.isNotEmpty && name == currentName;
        if (isCurrent) currentNodeId = id;
        await txn.insert(
            'adventure_map_node_states',
            {
              'adventure_id': adventureId,
              'node_id': id,
              'discovery_state':
                  isCurrent || (node['explored'] as int? ?? 0) == 1
                      ? 'visited'
                      : 'discovered',
              'availability_state': 'available',
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
        await txn.insert(
            'map_layouts',
            {
              'adventure_id': adventureId,
              'node_id': id,
              'map_level': node['map_level'] as int? ?? 1,
              'parent_node_id': node['parent_node_id'] as String? ?? '',
              'position_x': (node['x'] as num?)?.toDouble() ?? .5,
              'position_y': (node['y'] as num?)?.toDouble() ?? .5,
              'position_locked': node['position_locked'] as int? ?? 0,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      currentNodeId ??= nodes.last['id']! as String;
      await txn.insert(
          'adventure_map_state',
          {
            'adventure_id': adventureId,
            'current_node_id': currentNodeId,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  @override
  Future<NarrativeMapNode?> findMapNodeByName(
      int adventureId, String name, String? parentNodeId) async {
    final normalized = _normalizeMapName(name);
    if (normalized.isEmpty) return null;
    final db = await _getDb();
    final rows = await db.rawQuery('''
      SELECT DISTINCT n.*, COALESCE(s.discovery_state, 'discovered') AS discovery_state,
             COALESCE(s.availability_state, 'available') AS availability_state
      FROM map_nodes n
      LEFT JOIN map_node_aliases a ON a.adventure_id = n.adventure_id AND a.node_id = n.id
      LEFT JOIN adventure_map_node_states s ON s.adventure_id = n.adventure_id AND s.node_id = n.id
      WHERE n.adventure_id = ?
        AND (? IS NULL OR n.parent_node_id = ?)
        AND (REPLACE(LOWER(n.canonical_name), ' ', '') = ?
          OR REPLACE(LOWER(n.display_name), ' ', '') = ? OR a.normalized_alias = ?)
      LIMIT 2
    ''', [
      adventureId,
      parentNodeId,
      parentNodeId,
      normalized,
      normalized,
      normalized
    ]);
    if (rows.length != 1) return null;
    return NarrativeMapNode.fromRow(rows.single);
  }

  @override
  Future<void> addMapNodeAlias(
      int adventureId, String nodeId, String alias, String sourceType) async {
    final normalized = _normalizeMapName(alias);
    if (normalized.isEmpty) return;
    final db = await _getDb();
    final now = DateTime.now().toIso8601String();
    await db.insert(
        'map_node_aliases',
        {
          'adventure_id': adventureId,
          'node_id': nodeId,
          'alias': alias.trim(),
          'normalized_alias': normalized,
          'source_type': sourceType,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static String _normalizeMapName(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s·・的]'), '')
      .replaceAll(RegExp(r'[【】「」“”"（）()<>《》\[\]]'), '');

  static String _canonicalLegacyNodeType(String value) => switch (value) {
        'town' => 'settlement',
        'wild' => 'wild',
        'dungeon' => 'dungeon',
        'portal' => 'portal',
        _ => MapNodeType.values.any((type) => type.name == value)
            ? value
            : 'unknown',
      };

  static String _stableMapNodeId(int adventureId, String normalizedName) {
    var hash = 0x811c9dc5;
    for (final unit in normalizedName.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return 'map_${adventureId}_${hash.toRadixString(16)}';
  }

  @override
  Future<MapMovementResult> applyMapMovement(
      {required int adventureId,
      required String targetNodeId,
      required String operationId,
      required MapRoute route,
      required GameState gameState}) async {
    final db = await _getDb();
    final result = await db.transaction<MapMovementResult>((txn) async {
      final prior = await txn.query('movement_operations',
          where: 'operation_id = ?', whereArgs: [operationId], limit: 1);
      if (prior.isNotEmpty) {
        return MapMovementResult(
            applied: prior.first['status'] == 'completed',
            duplicate: true,
            remainingEnergy: gameState.energy);
      }
      final targetRows = await txn.query('map_nodes',
          columns: ['display_name', 'name'],
          where: 'id = ? AND adventure_id = ?',
          whereArgs: [targetNodeId, adventureId],
          limit: 1);
      if (targetRows.isEmpty) {
        return MapMovementResult(
            applied: false,
            error: '目标地点不存在',
            remainingEnergy: gameState.energy);
      }
      final stateRows = await txn.query('adventure_map_state',
          where: 'adventure_id = ?', whereArgs: [adventureId], limit: 1);
      final fromNodeId = stateRows.isEmpty
          ? null
          : stateRows.first['current_node_id'] as String?;
      if (fromNodeId == null ||
          route.nodeIds.first != fromNodeId ||
          route.nodeIds.last != targetNodeId) {
        return MapMovementResult(
            applied: false,
            error: '移动路线已失效',
            remainingEnergy: gameState.energy);
      }
      for (var index = 0; index < route.nodeIds.length - 1; index++) {
        final from = route.nodeIds[index];
        final to = route.nodeIds[index + 1];
        final edges = await txn.rawQuery('''
          SELECT c.id, COALESCE(s.availability_state, c.availability_state, 'available') AS state
          FROM map_connections c
          LEFT JOIN adventure_map_connection_states s
            ON s.adventure_id = ? AND s.connection_id = c.id
          WHERE (c.adventure_id = ? OR c.adventure_id IS NULL)
            AND ((c.node_a_id = ? AND c.node_b_id = ?)
              OR (c.is_bidirectional = 1 AND c.node_a_id = ? AND c.node_b_id = ?))
          LIMIT 1
        ''', [adventureId, adventureId, from, to, to, from]);
        if (edges.isEmpty ||
            !{'available', 'dangerous'}.contains(edges.single['state'])) {
          return MapMovementResult(
              applied: false,
              error: '移动路线已失效',
              remainingEnergy: gameState.energy);
        }
      }
      if (gameState.energy < route.energyCost) {
        return MapMovementResult(
            applied: false, error: '能量不足', remainingEnergy: gameState.energy);
      }
      final now = DateTime.now().toIso8601String();
      final targetName =
          (targetRows.first['display_name'] ?? targetRows.first['name'])
              .toString();
      await txn.insert('movement_operations', {
        'operation_id': operationId,
        'adventure_id': adventureId,
        'target_node_id': targetNodeId,
        'status': 'pending',
        'created_at': now
      });
      await txn.update(
          'game_state',
          {
            'energy': gameState.energy - route.energyCost,
            'current_scene': targetName
          },
          where: 'adventure_id = ?',
          whereArgs: [adventureId]);
      await txn.update('adventure_map_state',
          {'current_node_id': targetNodeId, 'updated_at': now},
          where: 'adventure_id = ?', whereArgs: [adventureId]);
      await txn.insert(
          'adventure_map_node_states',
          {
            'adventure_id': adventureId,
            'node_id': targetNodeId,
            'discovery_state': 'visited',
            'availability_state': 'available',
            'updated_at': now
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('travel_events', {
        'id': 'travel_$operationId',
        'adventure_id': adventureId,
        'operation_id': operationId,
        'from_node_id': fromNodeId,
        'to_node_id': targetNodeId,
        'route_json': encodeMapJson(route.nodeIds),
        'energy_cost': route.energyCost,
        'travel_time': route.travelTime,
        'result': 'arrived',
        'created_at': now
      });
      await txn.update(
          'movement_operations',
          {
            'status': 'completed',
            'result_json': encodeMapJson({
              'remainingEnergy': gameState.energy - route.energyCost,
              'targetName': targetName
            }),
            'completed_at': now
          },
          where: 'operation_id = ?',
          whereArgs: [operationId]);
      return MapMovementResult(
          applied: true,
          targetName: targetName,
          remainingEnergy: gameState.energy - route.energyCost);
    });
    if (result.applied) {
    }
    return result;
  }

  @override
  Future<void> saveAiConnections(
      int adventureId, List<MapConnectionSeed> connections) async {
    if (connections.isEmpty) return;
    final db = await _getDb();
    await db.transaction((txn) async {
      final nodeRows = await txn.rawQuery(
          'SELECT id, canonical_name FROM map_nodes WHERE adventure_id = ?',
          [adventureId]);
      final nameToId = <String, String>{};
      for (final row in nodeRows) {
        final id = row['id']! as String;
        final name =
            _normalizeMapName((row['canonical_name'] ?? '').toString());
        if (name.isNotEmpty) nameToId[name] = id;
      }
      for (final conn in connections) {
        final fromId = nameToId[_normalizeMapName(conn.fromNodeName)];
        final toId = nameToId[_normalizeMapName(conn.toNodeName)];
        if (fromId == null || toId == null) continue;
        await txn.insert(
          'map_connections',
          {
            'adventure_id': adventureId,
            'node_a_id': fromId,
            'node_b_id': toId,
            'connection_type': conn.type.name,
            'is_bidirectional': conn.isBidirectional ? 1 : 0,
            'travel_time': conn.travelTime,
            'energy_cost': conn.energyCost,
            'risk_level': 0,
            'availability_state': 'available',
            'source_type': 'aiGenerated',
            'confidence': 'confirmed',
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }
}
