import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/adventure_tracked_state_freezer.dart';
import 'package:lt_dialogue/application/adventure/adventure_tracked_state_registry.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/adventure_tracked_state.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/models/tracked_state_definition.dart';
import 'package:lt_dialogue/models/worldview_details.dart';

AdventureSelectedCharacter _selected(
  String id,
  String name, {
  bool protagonist = false,
  List<Map<String, dynamic>>? tracked,
  List<Map<String, dynamic>>? custom,
}) =>
    AdventureSelectedCharacter(
      id: id,
      characterId: id,
      characterName: name,
      isProtagonist: protagonist,
      characterCardJson: tracked == null && custom == null
          ? null
          : {
              'name': name,
              if (tracked != null) 'tracked_state_definitions': tracked,
              if (custom != null) 'custom_attributes': custom,
            },
    );

void main() {
  const freezer = AdventureTrackedStateFreezer();

  group('AdventureTrackedStateFreezer', () {
    test(
        'collects protagonist + all selected characters (no protagonist-first)',
        () {
      final config = AdventureConfig(
        name: 'Alice',
        selectedCharacters: [
          _selected('alice', 'Alice', protagonist: true, tracked: const [
            {'id': 'curse', 'name': '诅咒侵蚀', 'value_kind': 'integer'},
          ]),
          _selected('bob', 'Bob', tracked: const [
            {'id': 'fear', 'name': '恐惧程度', 'value_kind': 'integer'},
          ]),
        ],
      );

      final frozen = freezer.freeze(config);

      expect(frozen.map((d) => d.entityId).toSet(), {'alice', 'bob'});
      expect(frozen.every((d) => d.entityType == RuntimeEntityType.character),
          isTrue);
    });

    test('selected-only companion is monitored even without supporting list',
        () {
      final config = AdventureConfig(
        name: 'Alice',
        selectedCharacters: [
          _selected('alice', 'Alice', protagonist: true),
          _selected('bob', 'Bob', tracked: const [
            {'id': 'life_link', 'name': '生命链接', 'value_kind': 'integer'},
          ]),
        ],
        supportingCharacters: const [],
      );

      final frozen = freezer.freeze(config);

      expect(
        frozen.where((d) => d.entityId == 'bob').map((d) => d.definitionId),
        ['life_link'],
      );
    });

    test('NPC snapshots become npc-typed bindings', () {
      final config = AdventureConfig(
        name: 'Alice',
        selectedCharacters: [
          _selected('alice', 'Alice', protagonist: true),
        ],
        npcSnapshots: [
          AdventureNpcSnapshot(
            assetId: 'guard',
            name: '守门人',
            npcJson: const {
              'name': '守门人',
              'tracked_state_definitions': [
                {'id': 'alertness', 'name': '警戒程度', 'value_kind': 'integer'},
              ],
            },
          ),
        ],
      );

      final frozen = freezer.freeze(config);
      final npc = frozen.singleWhere((d) => d.entityId == 'guard');

      expect(npc.entityType, RuntimeEntityType.npc);
      expect(npc.definitionId, 'alertness');
    });

    test('world snapshot definitions bind to the world entity', () {
      final config = AdventureConfig(
        name: 'Alice',
        selectedCharacters: [
          _selected('alice', 'Alice', protagonist: true),
        ],
        worldviewSnapshot: {
          'source_id': 'w1',
          'detail_json': const WorldviewDetails(
            trackedStateDefinitions: [
              TrackedStateDefinition(id: 'war_tension', name: '战争紧张度'),
            ],
          ).toJson(),
        },
      );

      final frozen = freezer.freeze(config);
      final world =
          frozen.singleWhere((d) => d.entityType == RuntimeEntityType.world);

      expect(world.entityId, AdventureRuntimeEntityIds.world);
      expect(world.definitionId, 'war_tension');
    });

    test('legacy custom_attributes are projected only when no explicit defs',
        () {
      final config = AdventureConfig(
        name: 'Alice',
        selectedCharacters: [
          _selected('alice', 'Alice', protagonist: true),
        ],
        supportingCharacters: [_legacySupporting('bob', 'Bob')],
      );

      final frozen = freezer.freeze(config);

      // Companion snapshot: legacy customAttributes -> projected.
      final bob = frozen.where((d) => d.entityId == 'bob').toList();
      expect(bob.map((d) => d.definitionId), contains('affinity'));
      expect(bob.every((d) => d.entityType == RuntimeEntityType.character),
          isTrue);
      // A legacy numeric attribute becomes a bounded numeric definition and
      // never carries its legacy current value.
      expect(bob.first.definition.maximum, 100);
    });

    test('an entity with explicit definitions does not also project legacy',
        () {
      final config = AdventureConfig(
        name: 'Alice',
        selectedCharacters: [
          _selected(
            'alice',
            'Alice',
            protagonist: true,
            tracked: const [
              {'id': 'curse', 'name': '诅咒侵蚀', 'value_kind': 'integer'},
            ],
            custom: const [
              {'id': 'hp', 'name': '体力', 'value': '100'},
            ],
          ),
        ],
      );

      final frozen = freezer.freeze(config);

      expect(frozen.map((d) => d.definitionId), ['curse']);
    });

    test('freeze is idempotent once definitions exist', () {
      final config = AdventureConfig(
        name: 'Alice',
        trackedStateDefinitions: const [
          AdventureTrackedStateDefinition(
            entityType: RuntimeEntityType.character,
            entityId: 'alice',
            definition: TrackedStateDefinition(id: 'curse', name: '诅咒'),
          ),
        ],
      );

      expect(freezer.freeze(config), config.trackedStateDefinitions);
    });
  });

  group('AdventureTrackedStateRegistry', () {
    test('reads frozen definitions as the single authority', () {
      final config = AdventureConfig(
        name: 'Alice',
        trackedStateDefinitions: const [
          AdventureTrackedStateDefinition(
            entityType: RuntimeEntityType.character,
            entityId: 'alice',
            definition: TrackedStateDefinition(id: 'curse', name: '诅咒'),
          ),
          AdventureTrackedStateDefinition(
            entityType: RuntimeEntityType.character,
            entityId: 'bob',
            definition: TrackedStateDefinition(id: 'fear', name: '恐惧'),
          ),
        ],
      );

      final registry = AdventureTrackedStateRegistry.fromConfig(config);

      expect(registry.all, hasLength(2));
      expect(
        registry
            .forEntity(RuntimeEntityType.character, 'alice')
            .single
            .definitionId,
        'curse',
      );
      expect(
        registry.hasDefinition(RuntimeEntityType.character, 'bob', 'fear'),
        isTrue,
      );
      expect(
        registry.hasDefinition(RuntimeEntityType.character, 'alice', 'fear'),
        isFalse,
      );
    });

    test('same-name characters never share state (stable ids)', () {
      final config = AdventureConfig(
        name: '艾莉丝',
        trackedStateDefinitions: const [
          AdventureTrackedStateDefinition(
            entityType: RuntimeEntityType.character,
            entityId: 'alice-a',
            definition: TrackedStateDefinition(id: 'trust', name: '信任值'),
          ),
          AdventureTrackedStateDefinition(
            entityType: RuntimeEntityType.character,
            entityId: 'alice-b',
            definition: TrackedStateDefinition(id: 'trust', name: '信任值'),
          ),
        ],
      );

      final registry = AdventureTrackedStateRegistry.fromConfig(config);

      expect(
        registry
            .forEntity(RuntimeEntityType.character, 'alice-a')
            .single
            .entityId,
        'alice-a',
      );
      expect(
        registry
            .forEntity(RuntimeEntityType.character, 'alice-b')
            .single
            .entityId,
        'alice-b',
      );
    });

    test('falls back to legacy projection for pre-definition adventures', () {
      final config = AdventureConfig(
        name: '主角',
        customAttributes: const [
          CustomAttributeItem(
            id: 'san',
            name: '理智',
            value: '50/100',
            currentValue: 50,
            maxValue: 100,
          ),
        ],
      );

      final registry = AdventureTrackedStateRegistry.fromConfig(config);

      expect(registry.all, hasLength(1));
      expect(registry.all.single.definitionId, 'san');
      // The legacy current value must not leak into the definition.
      expect(registry.all.single.definition.maximum, 100);
    });
  });
}

/// Legacy companion snapshot: only `custom_attributes`, no explicit defs.
SupportingCharacter _legacySupporting(String id, String name) =>
    SupportingCharacter(
      id: id,
      name: name,
      customAttributes: const [
        CustomAttributeItem(
          id: 'affinity',
          name: '好感度',
          value: '50/100',
          currentValue: 50,
          maxValue: 100,
        ),
      ],
    );
