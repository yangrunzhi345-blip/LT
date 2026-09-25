import 'dart:convert';

import 'adventure_runtime_state.dart';

/// Stable, locale-neutral identifiers for controlled runtime fields.
enum RuntimeStateValueKind { integer, number, boolean, text, enumValue }

enum RuntimeEventImportance { minor, normal, major, critical }

enum RuntimeEventVisibility { internal, user, public }

final class RuntimeStatePathDefinition {
  final String id;
  final Set<RuntimeEntityType> entities;
  final RuntimeStateValueKind valueKind;
  final Set<String> enumValues;
  final num? minimum;
  final num? maximum;

  const RuntimeStatePathDefinition({
    required this.id,
    required this.entities,
    required this.valueKind,
    this.enumValues = const {},
    this.minimum,
    this.maximum,
  });

  bool accepts(RuntimeEntityType entityType, Object? value) {
    if (!entities.contains(entityType)) return false;
    if (value == null) return true;
    final valid = switch (valueKind) {
      RuntimeStateValueKind.integer => value is int,
      RuntimeStateValueKind.number => value is num && value.isFinite,
      RuntimeStateValueKind.boolean => value is bool,
      RuntimeStateValueKind.text => value is String && value.length <= 1000,
      RuntimeStateValueKind.enumValue =>
        value is String && enumValues.contains(value),
    };
    if (!valid) return false;
    if (value is num &&
        ((minimum != null && value < minimum!) ||
            (maximum != null && value > maximum!))) {
      return false;
    }
    return true;
  }
}

/// The single registry for controlled paths. Custom attributes are validated
/// by the existing AdventureConfig-specific validator.
final class RuntimeStateSchemaRegistry {
  static const definitions = <RuntimeStatePathDefinition>[
    RuntimeStatePathDefinition(
        id: 'hp',
        entities: {RuntimeEntityType.character, RuntimeEntityType.npc},
        valueKind: RuntimeStateValueKind.integer,
        minimum: 0),
    RuntimeStatePathDefinition(
        id: 'mp',
        entities: {RuntimeEntityType.character, RuntimeEntityType.npc},
        valueKind: RuntimeStateValueKind.integer,
        minimum: 0),
    RuntimeStatePathDefinition(
        id: 'energy',
        entities: {RuntimeEntityType.character, RuntimeEntityType.npc},
        valueKind: RuntimeStateValueKind.integer,
        minimum: 0),
    RuntimeStatePathDefinition(
        id: 'experience',
        entities: {RuntimeEntityType.character, RuntimeEntityType.npc},
        valueKind: RuntimeStateValueKind.integer,
        minimum: 0),
    RuntimeStatePathDefinition(
        id: 'level',
        entities: {RuntimeEntityType.character, RuntimeEntityType.npc},
        valueKind: RuntimeStateValueKind.integer,
        minimum: 1),
    RuntimeStatePathDefinition(
        id: 'base_atk',
        entities: {RuntimeEntityType.character, RuntimeEntityType.npc},
        valueKind: RuntimeStateValueKind.integer,
        minimum: 0),
    RuntimeStatePathDefinition(
        id: 'base_def',
        entities: {RuntimeEntityType.character, RuntimeEntityType.npc},
        valueKind: RuntimeStateValueKind.integer,
        minimum: 0),
    RuntimeStatePathDefinition(
        id: 'base_speed',
        entities: {RuntimeEntityType.character, RuntimeEntityType.npc},
        valueKind: RuntimeStateValueKind.integer,
        minimum: 0),
    RuntimeStatePathDefinition(
        id: 'affinity',
        entities: {RuntimeEntityType.character, RuntimeEntityType.npc},
        valueKind: RuntimeStateValueKind.number,
        minimum: -100,
        maximum: 100),
    RuntimeStatePathDefinition(
        id: 'life_status',
        entities: {RuntimeEntityType.character, RuntimeEntityType.npc},
        valueKind: RuntimeStateValueKind.enumValue,
        enumValues: {'alive', 'dead'}),
    RuntimeStatePathDefinition(
        id: 'lifecycle_status',
        entities: {
          RuntimeEntityType.character,
          RuntimeEntityType.npc,
          RuntimeEntityType.faction,
          RuntimeEntityType.location,
          RuntimeEntityType.relationship,
          RuntimeEntityType.world
        },
        valueKind: RuntimeStateValueKind.enumValue,
        enumValues: {'active', 'dead', 'destroyed', 'inactive'}),
    RuntimeStatePathDefinition(
        id: 'relationship',
        entities: {
          RuntimeEntityType.character,
          RuntimeEntityType.npc,
          RuntimeEntityType.relationship
        },
        valueKind: RuntimeStateValueKind.text),
    RuntimeStatePathDefinition(
        id: 'faction_id',
        entities: {RuntimeEntityType.character, RuntimeEntityType.npc},
        valueKind: RuntimeStateValueKind.text),
    RuntimeStatePathDefinition(
        id: 'former_faction_id',
        entities: {RuntimeEntityType.character, RuntimeEntityType.npc},
        valueKind: RuntimeStateValueKind.text),
    RuntimeStatePathDefinition(
        id: 'goal',
        entities: {RuntimeEntityType.character, RuntimeEntityType.npc},
        valueKind: RuntimeStateValueKind.text),
    RuntimeStatePathDefinition(
        id: 'controller_id',
        entities: {
          RuntimeEntityType.character,
          RuntimeEntityType.npc,
          RuntimeEntityType.location,
          RuntimeEntityType.faction
        },
        valueKind: RuntimeStateValueKind.text),
    RuntimeStatePathDefinition(
        id: 'status',
        entities: {
          RuntimeEntityType.character,
          RuntimeEntityType.npc,
          RuntimeEntityType.faction,
          RuntimeEntityType.location,
          RuntimeEntityType.relationship,
          RuntimeEntityType.world
        },
        valueKind: RuntimeStateValueKind.text),
    RuntimeStatePathDefinition(
        id: 'control',
        entities: {
          RuntimeEntityType.location,
          RuntimeEntityType.faction,
          RuntimeEntityType.world
        },
        valueKind: RuntimeStateValueKind.text),
    RuntimeStatePathDefinition(
        id: 'environment',
        entities: {RuntimeEntityType.location, RuntimeEntityType.world},
        valueKind: RuntimeStateValueKind.text),
    RuntimeStatePathDefinition(
        id: 'condition',
        entities: {RuntimeEntityType.location, RuntimeEntityType.world},
        valueKind: RuntimeStateValueKind.text),
    RuntimeStatePathDefinition(
        id: 'influence',
        entities: {RuntimeEntityType.faction},
        valueKind: RuntimeStateValueKind.number),
    RuntimeStatePathDefinition(
        id: 'time',
        entities: {RuntimeEntityType.world},
        valueKind: RuntimeStateValueKind.text),
    RuntimeStatePathDefinition(
        id: 'global_flag',
        entities: {RuntimeEntityType.world},
        valueKind: RuntimeStateValueKind.boolean),
  ];

  static RuntimeStatePathDefinition? find(String path) {
    for (final definition in definitions) {
      if (definition.id == path) return definition;
    }
    return null;
  }
}

final class RuntimeStateDiff {
  final String entityId;
  final RuntimeEntityType entityType;
  final String path;
  final Object? before;
  final Object? after;
  final String commitId;
  final int revision;
  final RuntimeEventSource source;

  const RuntimeStateDiff(
      {required this.entityId,
      required this.entityType,
      required this.path,
      required this.before,
      required this.after,
      required this.commitId,
      required this.revision,
      required this.source});
}

final class RuntimeStateEvent {
  static const schemaVersion = 1;
  final String eventId;
  final String eventTypeId;
  final int adventureId;
  final int branchId;
  final String commitId;
  final int revision;
  final DateTime occurredAt;
  final RuntimeEventSource source;
  final RuntimeEventImportance importance;
  final RuntimeEventVisibility visibility;
  final String? sourceMessageId;
  final Map<String, Object?> parameters;

  const RuntimeStateEvent(
      {required this.eventId,
      required this.eventTypeId,
      required this.adventureId,
      required this.branchId,
      required this.commitId,
      required this.revision,
      required this.occurredAt,
      required this.source,
      required this.importance,
      required this.visibility,
      this.sourceMessageId,
      this.parameters = const {}});

  Map<String, Object?> toJson() => {
        'schema_version': schemaVersion,
        'event_id': eventId,
        'event_type_id': eventTypeId,
        'adventure_id': adventureId,
        'branch_id': branchId,
        'commit_id': commitId,
        'revision': revision,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'source': source.name,
        'importance': importance.name,
        'visibility': visibility.name,
        if (sourceMessageId != null) 'source_message_id': sourceMessageId,
        'parameters': parameters,
      };

  String encode() => jsonEncode(toJson());
}

final class RuntimeStateSnapshot {
  static const schemaVersion = 1;
  final int adventureId;
  final int branchId;
  final int revision;
  final Map<String, RuntimeEntityState> entities;

  RuntimeStateSnapshot({
    required this.adventureId,
    required this.branchId,
    required this.revision,
    Map<String, RuntimeEntityState> entities = const {},
  }) : entities = Map.unmodifiable(entities);
}

final class RuntimeTimelineEntry {
  final String commitId;
  final int adventureId;
  final int branchId;
  final int revision;
  final DateTime occurredAt;
  final String summary;
  final String? sourceMessageId;
  final List<RuntimeStateEvent> events;
  final List<RuntimeStateDiff> diffs;
  final bool isLegacy;

  const RuntimeTimelineEntry({
    required this.commitId,
    required this.adventureId,
    required this.branchId,
    required this.revision,
    required this.occurredAt,
    required this.summary,
    required this.sourceMessageId,
    required this.events,
    required this.diffs,
    required this.isLegacy,
  });
}

String runtimeEventTypeFor(RuntimeEntityType entityType, String path) {
  if (path == 'affinity' || path == 'relationship') {
    return 'relationship_changed';
  }
  if (entityType == RuntimeEntityType.character ||
      entityType == RuntimeEntityType.npc) {
    if (path == 'life_status' ||
        path == 'lifecycle_status' ||
        path == 'status') {
      return 'character_status_changed';
    }
    return 'character_attribute_changed';
  }
  if (entityType == RuntimeEntityType.location) return 'location_state_changed';
  if (entityType == RuntimeEntityType.faction) return 'faction_state_changed';
  return 'world_fact_changed';
}
