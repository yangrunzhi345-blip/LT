import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/adventure_tracked_state_registry.dart';
import 'package:lt_dialogue/application/adventure/tracked_state_candidate_planner.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/adventure_tracked_state.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/tracked_state_definition.dart';

TrackedStateDefinition _monitor(
  String id, {
  CustomAttributeImportance importance = CustomAttributeImportance.reference,
}) =>
    TrackedStateDefinition(
      id: id,
      name: id,
      importance: importance,
      minimum: 0,
      maximum: 100,
    );

AdventureTrackedStateDefinition _bind(
  RuntimeEntityType type,
  String entityId,
  TrackedStateDefinition definition,
) =>
    AdventureTrackedStateDefinition(
      entityType: type,
      entityId: entityId,
      definition: definition,
    );

void main() {
  const planner = TrackedStateCandidatePlanner();

  test('companion is never starved by a protagonist with many monitors', () {
    final definitions = <AdventureTrackedStateDefinition>[
      for (var i = 0; i < 40; i++)
        _bind(RuntimeEntityType.character, 'hero', _monitor('hero_$i')),
      _bind(
        RuntimeEntityType.character,
        'bob',
        _monitor('life_link', importance: CustomAttributeImportance.critical),
      ),
    ];
    final registry = AdventureTrackedStateRegistry(definitions);
    final diagnostics = <String>[];

    final candidates = planner.plan(
      registry: registry,
      runtimeEntities: const [],
      presentEntityIds: const {'hero', 'bob'},
      maximumCandidates: 10,
      diagnostics: diagnostics,
    );

    expect(candidates, hasLength(10));
    expect(
      candidates.where((c) => c.entityId == 'bob').map((c) => c.definitionId),
      contains('life_link'),
      reason:
          'round-robin must represent the single critical companion monitor',
    );
    expect(diagnostics.single, startsWith('monitor_candidates_truncated:'));
  });

  test('sorts definitions within an entity by importance', () {
    final registry = AdventureTrackedStateRegistry([
      _bind(RuntimeEntityType.character, 'hero', _monitor('low')),
      _bind(
        RuntimeEntityType.character,
        'hero',
        _monitor('critical', importance: CustomAttributeImportance.critical),
      ),
      _bind(
        RuntimeEntityType.character,
        'hero',
        _monitor('important', importance: CustomAttributeImportance.important),
      ),
    ]);

    final candidates = planner.plan(
      registry: registry,
      runtimeEntities: const [],
      presentEntityIds: const {'hero'},
    );

    expect(
      candidates.map((c) => c.definitionId).toList(),
      ['critical', 'important', 'low'],
    );
  });

  test('the world entity enters the candidate set', () {
    final registry = AdventureTrackedStateRegistry([
      _bind(
        RuntimeEntityType.world,
        AdventureRuntimeEntityIds.world,
        _monitor('war_tension'),
      ),
    ]);

    final candidates = planner.plan(
      registry: registry,
      runtimeEntities: const [],
      presentEntityIds: const {},
    );

    expect(candidates, hasLength(1));
    expect(candidates.single.entityType, RuntimeEntityType.world);
  });

  test('irrelevant, unmentioned entities stay out of the candidate set', () {
    final registry = AdventureTrackedStateRegistry([
      _bind(RuntimeEntityType.character, 'hero', _monitor('curse')),
      _bind(RuntimeEntityType.character, 'bob', _monitor('fear')),
    ]);

    final candidates = planner.plan(
      registry: registry,
      runtimeEntities: const [],
      presentEntityIds: const {'hero'},
    );

    expect(candidates.map((c) => c.entityId).toSet(), {'hero'});
  });

  test('runtime overlay value marks a monitor as triggered', () {
    final registry = AdventureTrackedStateRegistry([
      _bind(RuntimeEntityType.character, 'hero', _monitor('curse')),
    ]);

    final candidates = planner.plan(
      registry: registry,
      runtimeEntities: [
        RuntimeEntityState(
          entityType: RuntimeEntityType.character,
          entityId: 'hero',
          overlay: const {'custom_attributes.curse': 18},
        ),
      ],
      presentEntityIds: const {'hero'},
    );

    expect(candidates.single.isTriggered, isTrue);
    expect(candidates.single.currentValue, 18);
    expect(candidates.single.promptLine, contains('当前=18/100'));
  });

  test('untriggered monitor renders absence, never a default zero', () {
    final registry = AdventureTrackedStateRegistry([
      _bind(RuntimeEntityType.character, 'hero', _monitor('curse')),
    ]);

    final candidates = planner.plan(
      registry: registry,
      runtimeEntities: const [],
      presentEntityIds: const {'hero'},
    );

    expect(candidates.single.isTriggered, isFalse);
    expect(candidates.single.promptLine, contains('当前=无'));
    expect(candidates.single.promptLine, isNot(contains('当前=0')));
  });

  test('legacy baseline value is used when the overlay has none', () {
    final registry = AdventureTrackedStateRegistry([
      _bind(RuntimeEntityType.character, 'hero', _monitor('stamina')),
    ]);

    final candidates = planner.plan(
      registry: registry,
      runtimeEntities: const [],
      presentEntityIds: const {'hero'},
      baselineValues: const {'character:hero:stamina': 100},
    );

    expect(candidates.single.currentValue, 100);
  });

  test('prompt line carries new identity and legacy aliases', () {
    final registry = AdventureTrackedStateRegistry([
      _bind(RuntimeEntityType.character, 'alice', _monitor('stamina')),
    ]);

    final candidates = planner.plan(
      registry: registry,
      runtimeEntities: const [],
      presentEntityIds: const {'alice'},
      entityNames: const {'alice': '艾莉丝'},
    );

    final line = candidates.single.promptLine;
    expect(line, contains('entity_type=character'));
    expect(line, contains('entity_id=alice'));
    expect(line, contains('monitor_id=stamina'));
    expect(line, contains('character_id=alice'));
    expect(line, contains('attribute_id=stamina'));
    expect(line, contains('角色=艾莉丝'));
  });
}
