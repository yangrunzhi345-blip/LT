import 'dart:convert';
import 'diagnostic_turn_export.dart';

class DiagnosticApplicationInfo {
  final String name;
  final String version;
  final String platform;

  const DiagnosticApplicationInfo({
    required this.name,
    required this.version,
    required this.platform,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'version': version,
        'platform': platform,
      };

  factory DiagnosticApplicationInfo.fromJson(Map<String, dynamic> json) =>
      DiagnosticApplicationInfo(
        name: json['name']?.toString() ?? '',
        version: json['version']?.toString() ?? '',
        platform: json['platform']?.toString() ?? '',
      );
}

class DiagnosticTurnRange {
  final String mode; // 'recent' or 'all'
  final int? requested;
  final int actual;

  const DiagnosticTurnRange({
    required this.mode,
    this.requested,
    required this.actual,
  });

  Map<String, dynamic> toJson() => {
        'mode': mode,
        if (requested != null) 'requested': requested,
        'actual': actual,
      };

  factory DiagnosticTurnRange.fromJson(Map<String, dynamic> json) =>
      DiagnosticTurnRange(
        mode: json['mode']?.toString() ?? 'recent',
        requested: json['requested'] as int?,
        actual: json['actual'] as int? ?? 0,
      );
}

class DiagnosticScope {
  final int adventureId;
  final String adventureTitle;
  final int branchId;
  final String branchName;
  final int headRevision;
  final DiagnosticTurnRange turnRange;

  const DiagnosticScope({
    required this.adventureId,
    required this.adventureTitle,
    required this.branchId,
    required this.branchName,
    required this.headRevision,
    required this.turnRange,
  });

  Map<String, dynamic> toJson() => {
        'adventure_id': adventureId,
        'adventure_title': adventureTitle,
        'branch_id': branchId,
        'branch_name': branchName,
        'head_revision': headRevision,
        'turn_range': turnRange.toJson(),
      };

  factory DiagnosticScope.fromJson(Map<String, dynamic> json) =>
      DiagnosticScope(
        adventureId: json['adventure_id'] as int? ?? 0,
        adventureTitle: json['adventure_title']?.toString() ?? '',
        branchId: json['branch_id'] as int? ?? 0,
        branchName: json['branch_name']?.toString() ?? '',
        headRevision: json['head_revision'] as int? ?? 0,
        turnRange: DiagnosticTurnRange.fromJson(
          json['turn_range'] as Map<String, dynamic>? ?? const {},
        ),
      );
}

class DiagnosticPrivacy {
  final bool containsConversationContent;
  final bool containsApiKeys;
  final bool containsAuthHeaders;

  const DiagnosticPrivacy({
    this.containsConversationContent = true,
    this.containsApiKeys = false,
    this.containsAuthHeaders = false,
  });

  Map<String, dynamic> toJson() => {
        'contains_conversation_content': containsConversationContent,
        'contains_api_keys': containsApiKeys,
        'contains_auth_headers': containsAuthHeaders,
      };

  factory DiagnosticPrivacy.fromJson(Map<String, dynamic> json) =>
      DiagnosticPrivacy(
        containsConversationContent:
            json['contains_conversation_content'] == true,
        containsApiKeys: json['contains_api_keys'] == true,
        containsAuthHeaders: json['contains_auth_headers'] == true,
      );
}

class DiagnosticEntitySnapshot {
  final String entityType;
  final String entityId;
  final String lifecycleStatus;
  final String? lastCommitId;
  final Map<String, dynamic> overlay;

  const DiagnosticEntitySnapshot({
    required this.entityType,
    required this.entityId,
    required this.lifecycleStatus,
    this.lastCommitId,
    this.overlay = const {},
  });

  Map<String, dynamic> toJson() => {
        'entity_type': entityType,
        'entity_id': entityId,
        'lifecycle_status': lifecycleStatus,
        if (lastCommitId != null) 'last_commit_id': lastCommitId,
        'overlay': overlay,
      };

  factory DiagnosticEntitySnapshot.fromJson(Map<String, dynamic> json) =>
      DiagnosticEntitySnapshot(
        entityType: json['entity_type']?.toString() ?? '',
        entityId: json['entity_id']?.toString() ?? '',
        lifecycleStatus: json['lifecycle_status']?.toString() ?? 'active',
        lastCommitId: json['last_commit_id']?.toString(),
        overlay: (json['overlay'] as Map<String, dynamic>?) ?? const {},
      );
}

class DiagnosticSceneStateSnapshot {
  final String location;
  final String time;
  final List<String> presentCharacterIds;
  final List<Map<String, dynamic>> activeGoals;

  const DiagnosticSceneStateSnapshot({
    required this.location,
    required this.time,
    this.presentCharacterIds = const [],
    this.activeGoals = const [],
  });

  Map<String, dynamic> toJson() => {
        'location': location,
        'time': time,
        'present_character_ids': presentCharacterIds,
        'active_goals': activeGoals,
      };

  factory DiagnosticSceneStateSnapshot.fromJson(Map<String, dynamic> json) =>
      DiagnosticSceneStateSnapshot(
        location: json['location']?.toString() ?? '',
        time: json['time']?.toString() ?? '',
        presentCharacterIds: (json['present_character_ids'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        activeGoals: (json['active_goals'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .toList() ??
            const [],
      );
}

class DiagnosticRuntimeSnapshot {
  final int headRevision;
  final String? headCommitId;
  final DiagnosticSceneStateSnapshot? sceneState;
  final List<DiagnosticEntitySnapshot> entities;

  const DiagnosticRuntimeSnapshot({
    required this.headRevision,
    this.headCommitId,
    this.sceneState,
    this.entities = const [],
  });

  Map<String, dynamic> toJson() => {
        'head_revision': headRevision,
        if (headCommitId != null) 'head_commit_id': headCommitId,
        if (sceneState != null) 'scene_state': sceneState!.toJson(),
        'entities': entities.map((e) => e.toJson()).toList(),
      };

  factory DiagnosticRuntimeSnapshot.fromJson(Map<String, dynamic> json) {
    final rawEntities = json['entities'] as List<dynamic>? ?? const [];
    return DiagnosticRuntimeSnapshot(
      headRevision: json['head_revision'] as int? ?? 0,
      headCommitId: json['head_commit_id']?.toString(),
      sceneState: json['scene_state'] is Map<String, dynamic>
          ? DiagnosticSceneStateSnapshot.fromJson(
              json['scene_state'] as Map<String, dynamic>)
          : null,
      entities: rawEntities
          .whereType<Map<String, dynamic>>()
          .map(DiagnosticEntitySnapshot.fromJson)
          .toList(),
    );
  }
}

/// Root data contract for Diagnostic Session Export (v1).
class DiagnosticSessionExport {
  static const String currentSchema = 'lt.diagnostic_session';
  static const int currentSchemaVersion = 1;

  final String schema;
  final int schemaVersion;
  final String exportedAt;
  final DiagnosticApplicationInfo application;
  final DiagnosticScope scope;
  final DiagnosticPrivacy privacy;
  final DiagnosticRuntimeSnapshot runtimeSnapshot;
  final List<DiagnosticTurnExport> turns;
  final List<String> exportWarnings;

  const DiagnosticSessionExport({
    this.schema = currentSchema,
    this.schemaVersion = currentSchemaVersion,
    required this.exportedAt,
    required this.application,
    required this.scope,
    this.privacy = const DiagnosticPrivacy(),
    required this.runtimeSnapshot,
    required this.turns,
    this.exportWarnings = const [],
  });

  Map<String, dynamic> toJson() => {
        'schema': schema,
        'schema_version': schemaVersion,
        'exported_at': exportedAt,
        'application': application.toJson(),
        'scope': scope.toJson(),
        'privacy': privacy.toJson(),
        'runtime_snapshot': runtimeSnapshot.toJson(),
        'turns': turns.map((t) => t.toJson()).toList(),
        'export_warnings': exportWarnings,
      };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory DiagnosticSessionExport.fromJson(Map<String, dynamic> json) {
    final rawTurns = json['turns'] as List<dynamic>? ?? const [];
    final rawWarnings = json['export_warnings'] as List<dynamic>? ?? const [];
    return DiagnosticSessionExport(
      schema: json['schema']?.toString() ?? currentSchema,
      schemaVersion: json['schema_version'] as int? ?? currentSchemaVersion,
      exportedAt: json['exported_at']?.toString() ?? '',
      application: DiagnosticApplicationInfo.fromJson(
        json['application'] as Map<String, dynamic>? ?? const {},
      ),
      scope: DiagnosticScope.fromJson(
        json['scope'] as Map<String, dynamic>? ?? const {},
      ),
      privacy: DiagnosticPrivacy.fromJson(
        json['privacy'] as Map<String, dynamic>? ?? const {},
      ),
      runtimeSnapshot: DiagnosticRuntimeSnapshot.fromJson(
        json['runtime_snapshot'] as Map<String, dynamic>? ?? const {},
      ),
      turns: rawTurns
          .whereType<Map<String, dynamic>>()
          .map(DiagnosticTurnExport.fromJson)
          .toList(),
      exportWarnings: rawWarnings.map((e) => e.toString()).toList(),
    );
  }
}
