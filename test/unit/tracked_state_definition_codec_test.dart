import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/adventure_tracked_state.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/tracked_state_definition.dart';
import 'package:lt_dialogue/models/typed_runtime_state.dart';

void main() {
  group('TrackedStateDefinition codec', () {
    test('round-trips all supported fields', () {
      const definition = TrackedStateDefinition(
        id: 'curse_corruption',
        name: '诅咒侵蚀',
        valueKind: RuntimeStateValueKind.integer,
        description: '接触深渊力量或禁术时提高，净化时降低',
        importance: CustomAttributeImportance.critical,
        minimum: 0,
        maximum: 100,
        icon: 'corruption',
      );

      final restored = TrackedStateDefinition.fromJson(definition.toJson());

      expect(restored, definition);
      expect(restored.valueKind, RuntimeStateValueKind.integer);
      expect(restored.importance, CustomAttributeImportance.critical);
    });

    test('serializes enumValues and reads the snake_case alias', () {
      final definition = TrackedStateDefinition.fromJson({
        'id': 'tide',
        'name': '魔力潮汐',
        'value_kind': 'enumValue',
        'enum_values': ['低潮', '中潮', '高潮'],
      });

      expect(definition.valueKind, RuntimeStateValueKind.enumValue);
      expect(definition.enumValues, {'低潮', '中潮', '高潮'});
      expect(definition.toJson()['enum_values'], isA<List<dynamic>>());
    });

    test('never serializes a current value', () {
      const definition = TrackedStateDefinition(
        id: 'war_tension',
        name: '战争紧张度',
        valueKind: RuntimeStateValueKind.integer,
        minimum: 0,
        maximum: 100,
      );

      final json = definition.toJson();
      for (final banned in TrackedStateDefinition.bannedCurrentStateKeys) {
        expect(json.containsKey(banned), isFalse, reason: banned);
      }
    });

    test('fromResourceJson rejects an embedded current value', () {
      final diagnostics = <String>[];
      final definition = TrackedStateDefinition.fromResourceJson(
        {
          'id': 'curse',
          'name': '诅咒',
          'value_kind': 'integer',
          'current_value': 37,
        },
        diagnostics: diagnostics,
        source: 'character:alice',
      );

      expect(definition, isNull);
      expect(
        diagnostics,
        contains(
            'tracked_state_definition:banned_key:current_value:character:alice'),
      );
    });

    test('acceptsValue enforces kind and bounds', () {
      const numeric = TrackedStateDefinition(
        id: 'tension',
        name: '紧张度',
        valueKind: RuntimeStateValueKind.integer,
        minimum: 0,
        maximum: 100,
      );
      expect(numeric.accepts(65), isTrue);
      expect(numeric.accepts(101), isFalse);
      expect(numeric.accepts(-1), isFalse);
      expect(numeric.accepts('65'), isFalse);
      expect(numeric.accepts(65.5), isFalse);

      const enumDef = TrackedStateDefinition(
        id: 'tide',
        name: '潮汐',
        valueKind: RuntimeStateValueKind.enumValue,
        enumValues: {'低', '高'},
      );
      expect(enumDef.accepts('低'), isTrue);
      expect(enumDef.accepts('中'), isFalse);
    });

    test('slugify is deterministic and locale-neutral', () {
      expect(TrackedStateDefinition.slugify('Curse Corruption'),
          'curse_corruption');
      expect(TrackedStateDefinition.slugify('战争紧张度'),
          TrackedStateDefinition.slugify('战争紧张度'));
      expect(TrackedStateDefinition.slugify('战争紧张度'), startsWith('monitor_'));
    });

    test('validate reports structural problems', () {
      expect(
        const TrackedStateDefinition(id: '', name: '').validate(),
        contains('name'),
      );
      expect(
        const TrackedStateDefinition(id: 'bad id!', name: 'X').validate(),
        contains('id_charset'),
      );
      expect(
        const TrackedStateDefinition(
          id: 'r',
          name: 'R',
          valueKind: RuntimeStateValueKind.integer,
          minimum: 100,
          maximum: 0,
        ).validate(),
        contains('range'),
      );
      expect(
        const TrackedStateDefinition(
          id: 'e',
          name: 'E',
          valueKind: RuntimeStateValueKind.enumValue,
        ).validate(),
        contains('enum_empty'),
      );
    });

    test('parseList caps, de-dupes and drops banned entries', () {
      final diagnostics = <String>[];
      final parsed = TrackedStateDefinition.parseList(
        [
          {'id': 'a', 'name': 'A'},
          {'id': 'a', 'name': 'A duplicate'},
          {'id': 'b', 'name': 'B', 'value': 10},
          {'id': 'c', 'name': 'C'},
        ],
        diagnostics: diagnostics,
        fromResource: true,
      );

      expect(parsed.map((d) => d.id), ['a', 'c']);
      expect(diagnostics,
          contains('tracked_state_definition:duplicate:resource:a'));
      expect(diagnostics,
          contains('tracked_state_definition:banned_key:value:resource'));
    });
  });

  group('AdventureTrackedStateDefinition binding', () {
    test('same-name characters keep independent keys via stable ids', () {
      const definition = TrackedStateDefinition(id: 'trust', name: '信任值');
      const aliceA = AdventureTrackedStateDefinition(
        entityType: RuntimeEntityType.character,
        entityId: 'alice-a',
        definition: definition,
      );
      const aliceB = AdventureTrackedStateDefinition(
        entityType: RuntimeEntityType.character,
        entityId: 'alice-b',
        definition: definition,
      );

      expect(aliceA.key, isNot(aliceB.key));
      expect(aliceA.key, 'character:alice-a:trust');
    });

    test('round-trips through JSON and de-duplicates on parse', () {
      const binding = AdventureTrackedStateDefinition(
        entityType: RuntimeEntityType.world,
        entityId: AdventureRuntimeEntityIds.world,
        definition: TrackedStateDefinition(id: 'war_tension', name: '战争紧张度'),
      );

      final restored =
          AdventureTrackedStateDefinition.fromJson(binding.toJson());
      expect(restored, binding);
      expect(restored.entityType, RuntimeEntityType.world);

      final list = AdventureTrackedStateDefinition.parseList(
        [binding.toJson(), binding.toJson()],
      );
      expect(list, hasLength(1));
    });
  });
}
