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
      presentCharacterIds: (json['present_character_ids'] as List<dynamic>?)
              ?.map((id) => id.toString())
              .toList(growable: false) ??
          const ['protagonist'],
      characterStates: characterStates,
      unresolvedEvents: (json['unresolved_events'] as List<dynamic>?)
              ?.map((event) => event.toString())
              .toList(growable: false) ??
          const [],
      goals: (json['goals'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((goal) => SceneGoal.fromJson(
                    Map<String, dynamic>.from(goal),
                  ))
              .toList(growable: false) ??
          const [],
      recentChanges: (json['recent_changes'] as List<dynamic>?)
              ?.map((change) => change.toString())
              .toList(growable: false) ??
          const [],
    );
  }

  factory SceneState.decode(String encoded) => SceneState.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
}
