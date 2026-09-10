import 'dart:convert';

enum SceneGoalStatus { active, resolved, cancelled, superseded }

/// A goal that can stop being authoritative as the story evolves.
final class SceneGoal {
  final String id;
  final String description;
  final SceneGoalStatus status;

  const SceneGoal({
    required this.id,
    required this.description,
    this.status = SceneGoalStatus.active,
  });

  SceneGoal copyWith({SceneGoalStatus? status}) => SceneGoal(
        id: id,
        description: description,
        status: status ?? this.status,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'description': description,
        'status': status.name,
      };

  factory SceneGoal.fromJson(Map<String, dynamic> json) => SceneGoal(
        id: json['id']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        status: SceneGoalStatus.values.firstWhere(
          (status) => status.name == json['status'],
          orElse: () => SceneGoalStatus.active,
        ),
      );
}

/// Branch-local state representing what is true now, not how play started.
final class SceneState {
  static const schemaVersion = 1;

  final String location;
  final String time;
  final List<String> presentCharacterIds;
  final Map<String, Map<String, dynamic>> characterStates;
  final List<String> unresolvedEvents;
  final List<SceneGoal> goals;
  final List<String> recentChanges;

  const SceneState({
    this.location = '',
    this.time = '',
    this.presentCharacterIds = const ['protagonist'],
    this.characterStates = const {},
    this.unresolvedEvents = const [],
    this.goals = const [],
    this.recentChanges = const [],
  });

  List<SceneGoal> get activeGoals => goals
      .where((goal) => goal.status == SceneGoalStatus.active)
      .toList(growable: false);

  SceneState copyWith({
    String? location,
    String? time,
    List<String>? presentCharacterIds,
    Map<String, Map<String, dynamic>>? characterStates,
    List<String>? unresolvedEvents,
    List<SceneGoal>? goals,
    List<String>? recentChanges,
  }) =>
      SceneState(
        location: location ?? this.location,
        time: time ?? this.time,
        presentCharacterIds: presentCharacterIds ?? this.presentCharacterIds,
        characterStates: characterStates ?? this.characterStates,
        unresolvedEvents: unresolvedEvents ?? this.unresolvedEvents,
        goals: goals ?? this.goals,
        recentChanges: recentChanges ?? this.recentChanges,
      );

  Map<String, Object?> toJson() => {
        'schema_version': schemaVersion,
        'location': location,
        'time': time,
        'present_character_ids': presentCharacterIds,
        'character_states': characterStates,
        'unresolved_events': unresolvedEvents,
        'goals': goals.map((goal) => goal.toJson()).toList(),
        'recent_changes': recentChanges,
      };

  String encode() => jsonEncode(toJson());

  factory SceneState.fromJson(Map<String, dynamic> json) {
    final rawCharacterStates = json['character_states'];
    final characterStates = <String, Map<String, dynamic>>{};
    if (rawCharacterStates is Map) {
      for (final entry in rawCharacterStates.entries) {
        if (entry.value is Map) {
          characterStates[entry.key.toString()] =
              Map<String, dynamic>.from(entry.value as Map);
        }
      }
    }
    return SceneState(
      location: json['location']?.toString() ?? '',
      time: json['time']?.toString() ?? '',
      presentCharacterIds:
          _stringList(json['present_character_ids'], const ['protagonist']),
      characterStates: characterStates,
      unresolvedEvents: _stringList(json['unresolved_events'], const []),
      goals: (json['goals'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((goal) => SceneGoal.fromJson(
                    Map<String, dynamic>.from(goal),
                  ))
              .toList(growable: false) ??
          const [],
      recentChanges: _stringList(json['recent_changes'], const []),
    );
  }

  /// Reads a persisted JSON list field tolerantly.
  ///
  /// Legacy/corrupt rows may store a scalar or object where a list is expected.
  /// Returning the fallback keeps the rest of the state usable instead of
  /// throwing a `TypeError` that would block the whole scene context.
  static List<String> _stringList(Object? raw, List<String> fallback) {
    if (raw is! List) return fallback;
    return raw.map((value) => value.toString()).toList(growable: false);
  }

  factory SceneState.decode(String encoded) => SceneState.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );

  /// 从持久化 JSON 解码，容忍历史/损坏行。
  ///
  /// 返回 null 表示该行不可用（非 JSON、非对象或字段结构损坏），调用方应按
  /// “无状态”处理，而不是让单个坏行阻断整个冒险。
  static SceneState? tryDecode(String encoded) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return null;
      return SceneState.fromJson(Map<String, dynamic>.from(decoded));
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}
