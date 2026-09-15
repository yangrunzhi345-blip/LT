/// Diagnostic turn export models representing a single turn's causal chain.
///
/// A turn is bounded by a single committed `scene_dialogue_turns` row,
/// and encapsulates the deterministic user input, the visible assistant narrative,
/// any runtime state commit & changes, and model diagnostics.
class DiagnosticMessage {
  final String messageId;
  final String content;
  final String timestamp;
  final bool isUser;
  final List<String>? options;
  final String? errorType;

  const DiagnosticMessage({
    required this.messageId,
    required this.content,
    required this.timestamp,
    required this.isUser,
    this.options,
    this.errorType,
  });

  Map<String, dynamic> toJson() {
    return {
      'message_id': messageId,
      'content': content,
      'timestamp': timestamp,
      if (!isUser && options != null) 'options': options,
      if (!isUser) 'error_type': errorType,
    };
  }

  factory DiagnosticMessage.fromJson(Map<String, dynamic> json,
      {required bool isUser}) {
    return DiagnosticMessage(
      messageId: json['message_id']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      timestamp: json['timestamp']?.toString() ?? '',
      isUser: isUser,
      options: (json['options'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      errorType: json['error_type']?.toString(),
    );
  }
}

/// A single atomic state change inside a turn commit.
class DiagnosticRuntimeChange {
  final String entityType;
  final String entityId;
  final String changeKind;
  final String operation;
  final String path;
  final Object? before;
  final Object? after;
  final String reason;

  const DiagnosticRuntimeChange({
    required this.entityType,
    required this.entityId,
    required this.changeKind,
    required this.operation,
    required this.path,
    required this.before,
    required this.after,
    required this.reason,
  });

  Map<String, dynamic> toJson() {
    return {
      'entity_type': entityType,
      'entity_id': entityId,
      'change_kind': changeKind,
      'operation': operation,
      'path': path,
      'before': before,
      'after': after,
      'reason': reason,
    };
  }

  factory DiagnosticRuntimeChange.fromJson(Map<String, dynamic> json) {
    return DiagnosticRuntimeChange(
      entityType: json['entity_type']?.toString() ?? '',
      entityId: json['entity_id']?.toString() ?? '',
      changeKind: json['change_kind']?.toString() ?? '',
      operation: json['operation']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      before: json['before'],
      after: json['after'],
      reason: json['reason']?.toString() ?? '',
    );
  }
}

/// Runtime commit metadata associated with a turn.
class DiagnosticTurnRuntime {
  final bool committed;
  final String? commitId;
  final int? revisionBefore;
  final int? revisionAfter;
  final String? summary;
  final List<DiagnosticRuntimeChange> changes;

  const DiagnosticTurnRuntime({
    required this.committed,
    this.commitId,
    this.revisionBefore,
    this.revisionAfter,
    this.summary,
    this.changes = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'committed': committed,
      'commit_id': commitId,
      'revision_before': revisionBefore,
      'revision_after': revisionAfter,
      'summary': summary,
      'changes': changes.map((c) => c.toJson()).toList(),
    };
  }

  factory DiagnosticTurnRuntime.fromJson(Map<String, dynamic> json) {
    final rawChanges = json['changes'] as List<dynamic>? ?? const [];
    return DiagnosticTurnRuntime(
      committed: json['committed'] == true,
      commitId: json['commit_id']?.toString(),
      revisionBefore: json['revision_before'] as int?,
      revisionAfter: json['revision_after'] as int?,
      summary: json['summary']?.toString(),
      changes: rawChanges
          .whereType<Map<String, dynamic>>()
          .map(DiagnosticRuntimeChange.fromJson)
          .toList(),
    );
  }
}

/// Complete diagnostic export representation of one narrative turn.
class DiagnosticTurnExport {
  /// 1-based sequential index of the turn within this adventure and branch.
  final int turnIndex;
  final String requestId;
  final String createdAt;
  final DiagnosticMessage? user;
  final DiagnosticMessage assistant;
  final DiagnosticTurnRuntime runtime;
  final Map<String, dynamic> diagnostics;

  const DiagnosticTurnExport({
    required this.turnIndex,
    required this.requestId,
    required this.createdAt,
    this.user,
    required this.assistant,
    required this.runtime,
    this.diagnostics = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'turn_index': turnIndex,
      'request_id': requestId,
      'created_at': createdAt,
      'user': user?.toJson(),
      'assistant': assistant.toJson(),
      'runtime': runtime.toJson(),
      'diagnostics': diagnostics,
    };
  }

  factory DiagnosticTurnExport.fromJson(Map<String, dynamic> json) {
    return DiagnosticTurnExport(
      turnIndex: json['turn_index'] as int? ?? 0,
      requestId: json['request_id']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      user: json['user'] is Map<String, dynamic>
          ? DiagnosticMessage.fromJson(json['user'] as Map<String, dynamic>,
              isUser: true)
          : null,
      assistant: DiagnosticMessage.fromJson(
        json['assistant'] as Map<String, dynamic>? ?? const {},
        isUser: false,
      ),
      runtime: DiagnosticTurnRuntime.fromJson(
        json['runtime'] as Map<String, dynamic>? ?? const {},
      ),
      diagnostics: (json['diagnostics'] as Map<String, dynamic>?) ?? const {},
    );
  }
}
