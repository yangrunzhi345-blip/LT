import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resource_library/edit_drafts.dart';
import 'package:lt_dialogue/models/character_card.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/models/tracked_state_definition.dart';
import 'package:lt_dialogue/models/typed_runtime_state.dart';
import 'package:lt_dialogue/models/worldview_details.dart';

const _curse = TrackedStateDefinition(
  id: 'curse_corruption',
  name: '诅咒侵蚀',
  valueKind: RuntimeStateValueKind.integer,
  description: '接触深渊力量或禁术时提高，净化时降低',
  importance: CustomAttributeImportance.critical,
  minimum: 0,
  maximum: 100,
);

void main() {
  group('CharacterCard tracked state definitions', () {
    test('round-trips through toJson/fromJson without a current value', () {
      final card = CharacterCard(
        name: '艾莉丝',
        trackedStateDefinitions: const [_curse],
      );

      final restored = CharacterCard.fromJson(card.toJson());

      expect(restored.trackedStateDefinitions, hasLength(1));
      expect(restored.trackedStateDefinitions.single, _curse);
      expect(
        card.toJson()['data']['tracked_state_definitions'],
        isA<List<dynamic>>(),
      );
    });

    test('drops a generated definition that carries current_value', () {
      final card = CharacterCard.fromJson({
        'name': '被诅咒者',
        'tracked_state_definitions': [
          {
            'id': 'curse_corruption',
            'name': '诅咒侵蚀',
            'value_kind': 'integer',
            'current_value': 37,
          },
        ],
      });

      expect(card.trackedStateDefinitions, isEmpty);
    });
  });

  group('SupportingCharacter tracked state definitions', () {
    test('round-trips through toJson/fromJson', () {
      final character = SupportingCharacter(
        id: 'bob',
        name: 'Bob',
        trackedStateDefinitions: const [_curse],
      );

      final restored = SupportingCharacter.fromJson(character.toJson());

      expect(restored.trackedStateDefinitions, hasLength(1));
      expect(restored.trackedStateDefinitions.single.id, 'curse_corruption');
    });
  });

  group('WorldviewDetails tracked state definitions', () {
    test('stores definitions as typed metadata, not as a module', () {
      const details = WorldviewDetails(
        trackedStateDefinitions: [
          TrackedStateDefinition(id: 'war_tension', name: '战争紧张度'),
        ],
      );

      final json = details.toJson();
      expect(json['tracked_state_definitions'], isA<List<dynamic>>());

      final restored = WorldviewDetails.fromJson(json);
      expect(restored.trackedStateDefinitions, hasLength(1));
      expect(restored.trackedStateDefinitions.single.id, 'war_tension');
      // The definition must not leak into the world-content sections.
      expect(restored.modules.containsKey('world_state'), isFalse);
      expect(restored.modules.containsKey('world_rules'), isFalse);
    });
  });

  group('resource edit drafts preserve definitions', () {
    test('character card draft reads and writes tracked_state_definitions', () {
      final draft = CharacterCardEditDraft.fromExisting({
        'id': 'c1',
        'name': '艾莉丝',
        'json_data':
            '{"name":"艾莉丝","tracked_state_definitions":[{"id":"curse_corruption","name":"诅咒侵蚀","value_kind":"integer","minimum":0,"maximum":100}]}',
      });

      expect(draft.trackedStateDefinitions, hasLength(1));
      final stored = draft.toStoredJson();
      expect(stored, contains('tracked_state_definitions'));
      expect(stored, contains('curse_corruption'));
    });

    test('npc draft reads and writes tracked_state_definitions', () {
      final draft = NpcEditDraft.fromExisting({
        'id': 'n1',
        'name': '守门人',
        'json_data':
            '{"name":"守门人","tracked_state_definitions":[{"id":"alertness","name":"警戒程度","value_kind":"integer","minimum":0,"maximum":100}]}',
      });

      expect(draft.trackedStateDefinitions, hasLength(1));
      final stored = draft.toStoredJson();
      expect(stored, contains('alertness'));
      // NPC uses the same model; no second structure is introduced.
      expect(stored, contains('tracked_state_definitions'));
    });

    test('worldview draft reads and writes tracked_state_definitions', () {
      final draft = WorldviewEditDraft.fromExisting({
        'id': 'w1',
        'name': '艾尔德兰',
        'description': '一个战乱中的世界',
        'detail_json': const WorldviewDetails(
          trackedStateDefinitions: [
            TrackedStateDefinition(id: 'war_tension', name: '战争紧张度'),
          ],
        ).encode(),
      });

      expect(draft.trackedStateDefinitions, hasLength(1));
      expect(draft.toDetails().trackedStateDefinitions, hasLength(1));
    });
  });

  group('AI generation rejects current values', () {
    test('CharacterCardGenerationDraft keeps valid definitions only', () {
      final draft = CharacterCardGenerationDraft.fromGenerated({
        'name': '双面间谍',
        'tracked_state_definitions': [
          {
            'id': 'exposure_risk',
            'name': '身份暴露风险',
            'value_kind': 'integer',
            'minimum': 0,
            'maximum': 100,
            'description': '身份线索被敌对人物发现时增加',
          },
          {
            'id': 'guessed',
            'name': '猜出来的值',
            'value_kind': 'integer',
            'current_value': 50,
          },
        ],
      });

      expect(draft.trackedStateDefinitions, hasLength(1));
      expect(draft.trackedStateDefinitions.single.id, 'exposure_risk');
    });
  });
}
