import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/adventure_tracked_state_definition_store.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/adventure_tracked_state.dart';
import 'package:lt_dialogue/models/tracked_state_definition.dart';
import 'package:lt_dialogue/models/typed_runtime_state.dart';

const _store = AdventureTrackedStateDefinitionStore();

AdventureConfig _configWith(
  List<AdventureTrackedStateDefinition> definitions,
) =>
    AdventureConfig(name: 'Alice', trackedStateDefinitions: definitions);

const _curse = AdventureTrackedStateDefinition(
  entityType: RuntimeEntityType.character,
  entityId: 'bob',
  definition: TrackedStateDefinition(
    id: 'curse',
    name: '诅咒侵蚀',
    valueKind: RuntimeStateValueKind.integer,
    minimum: 0,
    maximum: 100,
  ),
);

void main() {
  group('AdventureTrackedStateDefinitionStore', () {
    test('ADD: appends a definition with no current value', () {
      final config = _store.add(
        config: _configWith(const []),
        binding: _curse,
      );

      expect(config.trackedStateDefinitions, hasLength(1));
      expect(config.trackedStateDefinitions.single.definitionId, 'curse');
      expect(config.trackedStateDefinitions.single.definition.toJson(),
          isNot(contains('value')));
    });

    test('ADD: is idempotent for the same key', () {
      final once = _store.add(config: _configWith(const []), binding: _curse);
      final twice = _store.add(config: once, binding: _curse);

      expect(twice.trackedStateDefinitions, hasLength(1));
    });

    test('EDIT label/rule keeps the id and the runtime value', () {
      final update = _store.update(
        config: _configWith(const [_curse]),
        entityType: RuntimeEntityType.character,
        entityId: 'bob',
        definitionId: 'curse',
        definition: const TrackedStateDefinition(
          id: 'ignored',
          name: '诅咒侵蚀程度',
          description: '新的检测规则',
          valueKind: RuntimeStateValueKind.integer,
          minimum: 0,
          maximum: 100,
        ),
        currentValue: 37,
      );

      final edited = update.config.trackedStateDefinitions.single.definition;
      expect(edited.id, 'curse', reason: 'id must stay stable');
      expect(edited.name, '诅咒侵蚀程度');
      expect(update.clearRuntimeValue, isFalse);
    });

    test('EDIT incompatible type/invalidates the runtime value', () {
      final update = _store.update(
        config: _configWith(const [_curse]),
        entityType: RuntimeEntityType.character,
        entityId: 'bob',
        definitionId: 'curse',
        definition: const TrackedStateDefinition(
          id: 'curse',
          name: '诅咒侵蚀',
          valueKind: RuntimeStateValueKind.enumValue,
          enumValues: {'无', '轻度', '重度'},
        ),
        currentValue: 37,
      );

      expect(update.clearRuntimeValue, isTrue,
          reason: 'an integer 37 is no longer legal for an enum definition');
    });

    test('UPDATE a missing definition is a no-op', () {
      final update = _store.update(
        config: _configWith(const []),
        entityType: RuntimeEntityType.character,
        entityId: 'bob',
        definitionId: 'curse',
        definition: const TrackedStateDefinition(id: 'curse', name: '诅咒'),
        currentValue: 10,
      );

      expect(update.config.trackedStateDefinitions, isEmpty);
      expect(update.clearRuntimeValue, isFalse);
    });

    test('DELETE removes only the targeted definition', () {
      final config = _configWith(const [
        _curse,
        AdventureTrackedStateDefinition(
          entityType: RuntimeEntityType.character,
          entityId: 'bob',
          definition: TrackedStateDefinition(id: 'fear', name: '恐惧'),
        ),
      ]);

      final after = _store.remove(
        config: config,
        entityType: RuntimeEntityType.character,
        entityId: 'bob',
        definitionId: 'curse',
      );

      expect(
          after.trackedStateDefinitions.map((d) => d.definitionId), ['fear']);
    });

    test('DELETE with a stable key never touches a same-named sibling', () {
      final config = _configWith(const [
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
      ]);

      final after = _store.remove(
        config: config,
        entityType: RuntimeEntityType.character,
        entityId: 'alice-a',
        definitionId: 'trust',
      );

      expect(after.trackedStateDefinitions, hasLength(1));
      expect(after.trackedStateDefinitions.single.entityId, 'alice-b');
    });
  });
}
