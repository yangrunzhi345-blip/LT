import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/tracked_state_snapshot.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_response.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/adventure_tracked_state.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/models/tracked_state_definition.dart';
import 'package:lt_dialogue/models/typed_runtime_state.dart';
import 'package:lt_dialogue/services/runtime_state_validator.dart';

/// The per-turn `custom_status` presentation snapshot must be projected from the
/// unified tracked-state authority (frozen definitions + runtime overlay), never
/// from the legacy `customAttributes`, so the narrative body shows real values.
void main() {
  const curse = TrackedStateDefinition(
    id: 'curse_corruption',
    name: '精神污染',
    valueKind: RuntimeStateValueKind.integer,
    minimum: 0,
    maximum: 100,
  );
  const trust = TrackedStateDefinition(
    id: 'trust',
    name: '信任度',
    valueKind: RuntimeStateValueKind.integer,
  );
  const wounded = TrackedStateDefinition(
    id: 'wounded',
    name: '受伤状态',
    valueKind: RuntimeStateValueKind.boolean,
  );
  const stance = TrackedStateDefinition(
    id: 'war_stance',
    name: '战争立场',
    valueKind: RuntimeStateValueKind.enumValue,
    enumValues: {'和平', '中立', '敌对'},
  );
  const fear = TrackedStateDefinition(
    id: 'fear',
    name: '恐惧',
    valueKind: RuntimeStateValueKind.integer,
    minimum: 0,
    maximum: 100,
  );

  AdventureConfig buildConfig() => AdventureConfig(
        name: '李维',
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: 'lc',
            characterId: 'lc',
            characterName: '林澈',
            isProtagonist: true,
          ),
          AdventureSelectedCharacter(
            id: 'alice',
            characterId: 'alice',
            characterName: 'Alice',
          ),
          AdventureSelectedCharacter(
            id: 'bob',
            characterId: 'bob',
            characterName: 'Bob',
          ),
        ],
        supportingCharacters: [
          SupportingCharacter(id: 'alice', name: 'Alice'),
          SupportingCharacter(id: 'bob', name: 'Bob'),
        ],
        trackedStateDefinitions: const [
          AdventureTrackedStateDefinition(
            entityType: RuntimeEntityType.character,
            entityId: 'lc',
            definition: curse,
          ),
          AdventureTrackedStateDefinition(
            entityType: RuntimeEntityType.character,
            entityId: 'lc',
            definition: trust,
          ),
          AdventureTrackedStateDefinition(
            entityType: RuntimeEntityType.character,
            entityId: 'lc',
            definition: wounded,
          ),
          AdventureTrackedStateDefinition(
            entityType: RuntimeEntityType.character,
            entityId: 'lc',
            definition: stance,
          ),
          AdventureTrackedStateDefinition(
            entityType: RuntimeEntityType.character,
            entityId: 'alice',
            definition: fear,
          ),
          AdventureTrackedStateDefinition(
            entityType: RuntimeEntityType.character,
            entityId: 'bob',
            definition: fear,
          ),
          AdventureTrackedStateDefinition(
            entityType: RuntimeEntityType.world,
            entityId: AdventureRuntimeEntityIds.world,
            definition: TrackedStateDefinition(id: 'war', name: '战争阶段'),
          ),
        ],
      );

  const builder = TrackedStateSnapshotBuilder();

  Map<String, dynamic> itemFor(List<Map<String, dynamic>> items, String id) =>
      items.firstWhere((item) => item['id'] == id);

  test('Case A: definition with a value carries id, name and value', () {
    final items = builder.build(
      config: buildConfig(),
      runtimeEntities: [
        RuntimeEntityState(
          entityType: RuntimeEntityType.character,
          entityId: 'lc',
          overlay: const {'custom_attributes.curse_corruption': 18},
        ),
      ],
    );
    final curseItem = itemFor(items, 'curse_corruption');
    expect(curseItem['name'], '精神污染');
    expect(curseItem['characterName'], '林澈');
    expect(curseItem['value'], '18/100');
    expect(curseItem['currentValue'], 18);
    expect(curseItem['maxValue'], 100);
    expect(curseItem['untriggered'], isNot(true));
  });

  test('Case B: definition without a value is untriggered, never zero', () {
    final items =
        builder.build(config: buildConfig(), runtimeEntities: const []);
    final trustItem = itemFor(items, 'trust');
    expect(trustItem['untriggered'], isTrue);
    expect(trustItem['value'], '');
    expect(trustItem['currentValue'], isNull);
    // Every character definition is still present even without values.
    expect(items.map((item) => item['id']), contains('curse_corruption'));
    expect(items.map((item) => item['id']), contains('wounded'));
  });

  test('numeric without a maximum renders a bare value', () {
    final items = builder.build(
      config: buildConfig(),
      runtimeEntities: [
        RuntimeEntityState(
          entityType: RuntimeEntityType.character,
          entityId: 'lc',
          overlay: const {'custom_attributes.trust': 36},
        ),
      ],
    );
    final trustItem = itemFor(items, 'trust');
    expect(trustItem['value'], '36');
    expect(trustItem['currentValue'], isNull);
  });

  test('boolean and enum carry an explicit value kind', () {
    final items = builder.build(
      config: buildConfig(),
      runtimeEntities: [
        RuntimeEntityState(
          entityType: RuntimeEntityType.character,
          entityId: 'lc',
          overlay: const {
            'custom_attributes.wounded': true,
            'custom_attributes.war_stance': '敌对',
          },
        ),
      ],
    );
    expect(itemFor(items, 'wounded')['value_kind'], 'boolean');
    expect(itemFor(items, 'wounded')['value'], 'true');
    expect(itemFor(items, 'war_stance')['value'], '敌对');
  });

  test('Case C: two same-id definitions on different entities do not bleed',
      () {
    final items = builder.build(
      config: buildConfig(),
      runtimeEntities: [
        RuntimeEntityState(
          entityType: RuntimeEntityType.character,
          entityId: 'alice',
          overlay: const {'custom_attributes.fear': 20},
        ),
        RuntimeEntityState(
          entityType: RuntimeEntityType.character,
          entityId: 'bob',
          overlay: const {'custom_attributes.fear': 70},
        ),
      ],
    );
    final fearItems = items.where((item) => item['id'] == 'fear').toList();
    expect(fearItems, hasLength(2));
    final alice = fearItems.firstWhere((i) => i['characterName'] == 'Alice');
    final bob = fearItems.firstWhere((i) => i['characterName'] == 'Bob');
    expect(alice['value'], '20/100');
    expect(bob['value'], '70/100');
  });

  test('Case D: value is clamped to the frozen definition range', () {
    // An increment that would exceed the maximum is settled at the maximum,
    // matching what the store persists.
    final accepted = const RuntimeStateValidator().accept(
      const [
        RuntimeStateChangeProposal(
          entityType: RuntimeEntityType.character,
          entityId: 'lc',
          changeKind: RuntimeChangeKind.primary,
          operation: RuntimeChangeOperation.increment,
          path: 'custom_attributes.curse_corruption',
          value: 20,
          reason: '剧情压力',
        ),
      ],
      config: buildConfig(),
    );
    final items = builder.build(
      config: buildConfig(),
      runtimeEntities: [
        RuntimeEntityState(
          entityType: RuntimeEntityType.character,
          entityId: 'lc',
          overlay: const {'custom_attributes.curse_corruption': 95},
        ),
      ],
      acceptedChanges: accepted,
    );
    expect(itemFor(items, 'curse_corruption')['value'], '100/100');
  });

  test('Case D: an out-of-range set is rejected and never shown', () {
    final accepted = const RuntimeStateValidator().accept(
      const [
        RuntimeStateChangeProposal(
          entityType: RuntimeEntityType.character,
          entityId: 'lc',
          changeKind: RuntimeChangeKind.primary,
          operation: RuntimeChangeOperation.set,
          path: 'custom_attributes.curse_corruption',
          value: 120,
          reason: '模型越界',
        ),
      ],
      config: buildConfig(),
    );
    expect(accepted, isEmpty, reason: 'validator drops > maximum set');
    final items = builder.build(
      config: buildConfig(),
      runtimeEntities: const [],
      acceptedChanges: accepted,
    );
    final curseItem = itemFor(items, 'curse_corruption');
    // Neither 120 nor a fabricated value appears; it stays untriggered.
    expect(curseItem['untriggered'], isTrue);
    expect(curseItem['value'], isNot(contains('120')));
  });

  test('world definitions stay out of the inline body snapshot', () {
    final items =
        builder.build(config: buildConfig(), runtimeEntities: const []);
    expect(items.any((item) => item['id'] == 'war'), isFalse);
  });

  test('adventure without definitions produces an empty snapshot', () {
    final items = builder.build(
      config: AdventureConfig(name: '空'),
      runtimeEntities: const [],
    );
    expect(items, isEmpty);
  });

  test('legacy adventure reads its custom_attributes as the baseline', () {
    final legacy = AdventureConfig(
      name: '旧冒险',
      customAttributes: const [
        CustomAttributeItem(
          id: 'san',
          name: 'SAN值',
          value: '60/100',
          currentValue: 60,
          maxValue: 100,
        ),
      ],
    );
    final items = builder.build(config: legacy, runtimeEntities: const []);
    expect(items, hasLength(1));
    expect(items.single['name'], 'SAN值');
    expect(items.single['value'], '60/100');
    expect(items.single['untriggered'], isNot(true));
  });

  test('Case H: the snapshot is stripped from the LLM history projection', () {
    final items = builder.build(
      config: buildConfig(),
      runtimeEntities: [
        RuntimeEntityState(
          entityType: RuntimeEntityType.character,
          entityId: 'lc',
          overlay: const {'custom_attributes.curse_corruption': 18},
        ),
      ],
    );
    final content = '她停下脚步。\n---JSON---\n${jsonEncode({
          'options': ['继续', '等待'],
          'custom_status': items,
          'runtime_state_changes': const [],
        })}';

    final projected = AdventureResponse.llmHistoryProjection(content);
    expect(projected, '她停下脚步。');
    expect(projected, isNot(contains('custom_status')));
    expect(projected, isNot(contains('untriggered')));
    expect(projected, isNot(contains('精神污染')));
    expect(projected, isNot(contains('options')));
  });
}
