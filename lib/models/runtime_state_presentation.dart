import 'adventure_runtime_state.dart';

enum RuntimeStateFieldCategory {
  body,
  emotion,
  position,
  goal,
  affiliation,
  relationship,
  world,
  custom,
}

enum RuntimeStateFieldVisibility { userVisible, debugOnly, hidden }

/// Presentation metadata for controlled runtime paths. Values remain stable
/// IDs; localization and formatting belong to the presentation layer.
final class RuntimeStateFieldPresentationDefinition {
  final String path;
  final Set<RuntimeEntityType> entityTypes;
  final RuntimeStateFieldCategory category;
  final RuntimeStateFieldVisibility visibility;
  final int priority;

  const RuntimeStateFieldPresentationDefinition({
    required this.path,
    required this.entityTypes,
    required this.category,
    this.visibility = RuntimeStateFieldVisibility.userVisible,
    this.priority = 100,
  });
}

final class RuntimeStatePresentationRegistry {
  static const definitions = <RuntimeStateFieldPresentationDefinition>[
    RuntimeStateFieldPresentationDefinition(
      path: 'hp',
      entityTypes: {RuntimeEntityType.character, RuntimeEntityType.npc},
      category: RuntimeStateFieldCategory.body,
      priority: 10,
    ),
    RuntimeStateFieldPresentationDefinition(
      path: 'life_status',
      entityTypes: {RuntimeEntityType.character, RuntimeEntityType.npc},
      category: RuntimeStateFieldCategory.body,
      priority: 20,
    ),
    RuntimeStateFieldPresentationDefinition(
      path: 'faction_id',
      entityTypes: {RuntimeEntityType.character, RuntimeEntityType.npc},
      category: RuntimeStateFieldCategory.affiliation,
    ),
    RuntimeStateFieldPresentationDefinition(
      path: 'relationship',
      entityTypes: {
        RuntimeEntityType.character,
        RuntimeEntityType.npc,
        RuntimeEntityType.relationship,
      },
      category: RuntimeStateFieldCategory.relationship,
    ),
    RuntimeStateFieldPresentationDefinition(
      path: 'goal',
      entityTypes: {RuntimeEntityType.character, RuntimeEntityType.npc},
      category: RuntimeStateFieldCategory.goal,
    ),
    RuntimeStateFieldPresentationDefinition(
      path: 'controller_id',
      entityTypes: {
        RuntimeEntityType.location,
        RuntimeEntityType.faction,
        RuntimeEntityType.world,
      },
      category: RuntimeStateFieldCategory.affiliation,
    ),
    RuntimeStateFieldPresentationDefinition(
      path: 'status',
      entityTypes: {
        RuntimeEntityType.location,
        RuntimeEntityType.faction,
        RuntimeEntityType.relationship,
        RuntimeEntityType.world,
      },
      category: RuntimeStateFieldCategory.world,
    ),
    RuntimeStateFieldPresentationDefinition(
      path: 'environment',
      entityTypes: {RuntimeEntityType.location, RuntimeEntityType.world},
      category: RuntimeStateFieldCategory.world,
    ),
  ];

  static RuntimeStateFieldPresentationDefinition? find(
    RuntimeEntityType type,
    String path,
  ) {
    for (final definition in definitions) {
      if (definition.path == path && definition.entityTypes.contains(type)) {
        return definition;
      }
    }
    return null;
  }
}
