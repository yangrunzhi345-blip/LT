part of 'adventure_repository_impl.dart';

mixin _AdventureDiagnosticsStore on _AdventureRepositoryBase {
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
            } catch (error) {
              before = beforeRaw;
              exportWarnings
                  .add('Commit $commitId $entityType:$entityId: malformed '
                      'before_json (${error.runtimeType})');
            }
          }

          Object? after;
          final afterRaw = cr['after_json'];
          if (afterRaw is String && afterRaw.isNotEmpty) {
            try {
              after = jsonDecode(afterRaw);
            } catch (error) {
              after = afterRaw;
              exportWarnings
                  .add('Commit $commitId $entityType:$entityId: malformed '
                      'after_json (${error.runtimeType})');
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
}
