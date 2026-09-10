import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/utils/json_value_reader.dart';
import '../../models/adventure_config.dart';
import '../../models/adventure_runtime_state.dart';
import '../../models/scene_dialogue.dart';
import '../../models/scene_dialogue_effects.dart';
import '../../models/scene_state.dart';
import '../../models/world_entry.dart';
import '../../models/game_state.dart';
import '../../models/message.dart';
import '../../models/narrative_map.dart';
import '../../models/quest.dart';
import '../runtime_state_validator.dart';
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
  Future<List<RuntimeEntityState>> getRuntimeEntities(
    int adventureId,
    int branchId, {
    int limit = 32,
  }) async {
    final db = await _getDb();
    final rows = await db.query('adventure_runtime_entities',
        where: 'adventure_id = ? AND branch_id = ?',
        whereArgs: [adventureId, branchId],
        orderBy: 'updated_at DESC',
        limit: limit.clamp(1, 64));
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

      final runtimeDraft = _mergeRuntimeDrafts(
        explicit: commit.runtimeStateDraft,
        legacy: _legacyRuntimeDraft(commit.effects, config),
      );
      await _applyRuntimeDraft(
        txn: txn,
        commit: commit,
        config: config,
        draft: runtimeDraft,
      );

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
      if (commit.sceneState case final sceneState?) {
        await txn.insert(
          'scene_runtime_state',
          {
            'adventure_id': commit.adventureId,
            'branch_id': commit.branchId,
            'state_json': sceneState.encode(),
            'schema_version': SceneState.schemaVersion,
            'updated_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
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
        sceneState: commit.sceneState,
      );
    });
    return result;
  }

  RuntimeStateCommitDraft? _mergeRuntimeDrafts({
    required RuntimeStateCommitDraft? explicit,
    required RuntimeStateCommitDraft? legacy,
  }) {
    if (explicit == null) return legacy;
    if (legacy == null) return explicit;
    return RuntimeStateCommitDraft(
      expectedRevision: explicit.expectedRevision,
      changes: List.unmodifiable([...explicit.changes, ...legacy.changes]),
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

  Future<void> _applyRuntimeDraft({
    required Transaction txn,
    required SceneDialogueCommit commit,
    required AdventureConfig? config,
    required RuntimeStateCommitDraft? draft,
  }) async {
    if (draft == null || draft.changes.isEmpty) return;
    final acceptedChanges = const RuntimeStateValidator().accept(draft.changes);
    if (acceptedChanges.isEmpty) return;
    final headRows = await txn.query('adventure_runtime_heads',
        where: 'adventure_id = ? AND branch_id = ?',
        whereArgs: [commit.adventureId, commit.branchId],
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
            commit.adventureId,
            commit.branchId,
            proposal.entityType.name,
            proposal.entityId
          ],
          limit: 1);
      final existsInRuntime = entityRows.isNotEmpty;
      if (!existsInRuntime &&
          proposal.entityType == RuntimeEntityType.character &&
          !knownCharacterIds.contains(proposal.entityId)) {
        continue;
      }
      if (!existsInRuntime &&
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
      final before = state[proposal.path] ?? baselineAffinity;
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
    if (valid.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    final revision = currentRevision + 1;
    final commitId = 'runtime-${commit.requestId}';
    final parentCommitId =
        headRows.isEmpty ? null : headRows.single['head_commit_id'] as String?;
    await txn.insert('adventure_state_commits', {
      'id': commitId,
      'adventure_id': commit.adventureId,
      'branch_id': commit.branchId,
      'request_id': commit.requestId,
      'parent_commit_id': parentCommitId,
      'revision': revision,
      'context_snapshot_id':
          draft.contextSnapshotId ?? commit.contextSnapshotId,
      'summary': draft.summary,
      'cause_ref': draft.sourceMessageId ?? commit.assistantMessage.id,
      'created_at': now,
    });
    for (var index = 0; index < valid.length; index++) {
      final (proposal, before, after) = valid[index];
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
        'provenance_json': jsonEncode({'request_id': commit.requestId}),
      });
    }
    for (final entry in states.entries) {
      final parts = entry.key.split(':');
      await txn.insert(
          'adventure_runtime_entities',
          {
            'adventure_id': commit.adventureId,
            'branch_id': commit.branchId,
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
          'adventure_id': commit.adventureId,
          'branch_id': commit.branchId,
          'revision': revision,
          'head_commit_id': commitId,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Object? _applyRuntimeOperation(
      Object? before, RuntimeStateChangeProposal change) {
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

  bool _runtimeEquals(Object? first, Object? second) =>
      jsonEncode(first) == jsonEncode(second);

  @override
  Future<ScenePresence?> getScenePresence(int adventureId, int branchId) async {
    final db = await _getDb();
    final rows = await db.query('scene_presence',
        where: 'adventure_id = ? AND branch_id = ?',
        whereArgs: [adventureId, branchId],
        limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    // scene_presence is persisted state: a single corrupt row must not block
    // the scene context. Malformed rows degrade to "no presence" so the
    // provider can bootstrap a fresh default instead of throwing.
    final actorId =
        row['actor_id'] is String ? (row['actor_id'] as String).trim() : null;
    final ids = _decodeParticipantIds(row['participant_ids_json']);
    if (actorId == null || actorId.isEmpty || ids == null) {
      debugPrint('[AdventureRepository] skipping malformed scene presence row '
          'adventure=$adventureId branch=$branchId');
      return null;
    }
    return ScenePresence(
        adventureId: adventureId,
        branchId: branchId,
        actorId: actorId,
        participantIds: ids);
  }

  static List<String>? _decodeParticipantIds(Object? raw) {
    final text = raw is String ? raw : JsonValueReader.stringScalar(raw);
    if (text == null) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) return null;
      return decoded.map((value) => value.toString()).toList(growable: false);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveScenePresence(ScenePresence presence) async {
    final db = await _getDb();
    await db.insert('scene_presence',
        {...presence.toRow(), 'updated_at': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace);
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
  Future<void> saveSceneState(
    int adventureId,
    int branchId,
    SceneState state,
  ) async {
    final db = await _getDb();
    await db.insert(
      'scene_runtime_state',
      {
        'adventure_id': adventureId,
        'branch_id': branchId,
        'state_json': state.encode(),
        'schema_version': SceneState.schemaVersion,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
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
    if (applied) {}
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
    if (entryId != null) {}
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
    if (changed) {}
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
    if (result.applied) {}
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
