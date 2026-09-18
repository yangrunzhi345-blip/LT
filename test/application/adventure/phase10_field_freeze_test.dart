import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/legacy_resource_mapper.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/character_card.dart';
import 'package:lt_dialogue/models/supporting_character.dart';

import '../../helpers/phase10_fixture.dart';

void main() {
  late Phase10Fixture fixture;
  const mapper = LegacyResourceMapper();

  Map<String, dynamic> data(String version) => {
        'name': 'name_$version',
        'gender': 'gender_$version',
        'age': version == 'A' ? '21' : '42',
        'profession': 'profession_$version',
        'description': 'background_$version',
        'personality': 'personality_$version',
        'first_mes': 'greeting_$version',
        'system_prompt': 'system_$version',
        'scenario': 'scenario_$version',
        'mes_example': 'dialogue_$version',
        'custom_attributes': [
          {'name': 'attribute', 'value': 'value_$version'},
        ],
        'relation': 'relation_$version',
        'role': 'role_$version',
        'height': 'height_$version',
        'hairColor': 'hair_$version',
        'affinity': version == 'A' ? 17 : 83,
        'isAlive': version == 'A',
      };

  Future<ResourceId> write(String id, String version,
      {bool npc = false, bool update = false}) async {
    final row = <String, Object?>{
      'id': id,
      'name': 'name_$version',
      'matching_worldview_id': 'world_$version',
      'json_data': jsonEncode(data(version)),
    };
    final draft = npc ? mapper.mapNpc(row) : mapper.mapCharacter(row);
    if (update) {
      await fixture.treeRepository.updateResourceTree(draft);
    } else {
      await fixture.treeRepository.createResourceTree(draft);
    }
    final idValue = draft.id;
    await fixture.revisionService.captureRevision(
      idValue,
      cause: RevisionCause.manualSave,
    );
    return idValue;
  }

  setUp(() async {
    fixture = Phase10Fixture();
    await fixture.setUp(prefix: 'lt_p10_fields_');
  });
  tearDown(() => fixture.tearDown());

  group('AdventureReadinessGate field freezing', () {
    for (final stale in [false, true]) {
      test('should freeze all runtime carriers from A (stale=$stale)',
          () async {
        final hero = await write('hero', 'A');
        final companion = await write('companion', 'A');
        final npc = await write('npc', 'A', npc: true);
        final ids = [hero, companion, npc];
        for (final id in ids) {
          await fixture.coordinator.prepare(id);
        }
        final ready = await fixture.gate.resolve(ids.map((id) => id.value));
        if (stale) {
          await write('hero', 'B', update: true);
          await write('companion', 'B', update: true);
          await write('npc', 'B', npc: true, update: true);
        }
        // Deliberately poison every input carrier, even in the ready case:
        // a ready assembly must also be authoritative over Wizard data.
        final legacy = SupportingCharacter(id: 'legacy', name: 'untouched');
        final config = AdventureConfig(
          name: 'name_B',
          gender: 'gender_B',
          age: '42',
          personality: 'personality_B',
          protagonistClass: 'profession_B',
          protagonistBackground: 'background_B',
          characterCard: CharacterCard.fromJson(data('B')),
          selectedCharacters: [
            AdventureSelectedCharacter(
              id: 'hero-selection',
              characterId: hero.value,
              characterName: 'name_B',
              characterAvatar: 'avatar_B',
              isProtagonist: true,
              characterCardJson: data('B'),
            ),
            AdventureSelectedCharacter(
              id: 'companion-selection',
              characterId: companion.value,
              characterName: 'name_B',
              narrativeRole: AdventureCharacterRole.mentor,
              characterCardJson: data('B'),
            ),
          ],
          supportingCharacters: [
            SupportingCharacter.fromJson({
              ...data('B'),
              'id': 'companion-selection',
              'relation': '用户指定关系',
            }),
            SupportingCharacter.fromJson({...data('B'), 'id': npc.value}),
            legacy,
          ],
          npcSnapshots: [
            AdventureNpcSnapshot(
              assetId: npc.value,
              name: 'name_B',
              originWorldviewId: 'world_B',
              npcJson: data('B'),
            ),
          ],
          resourceBindings: [
            if (stale)
              for (final entry in ready.entries)
                AdventureResourceBinding(
                  resourceId: entry.key,
                  revisionId: entry.value.assemblyRevisionId,
                  contentHash: entry.value.assemblyContentHash,
                  staleAllowed: true,
                ),
          ],
        );
        final inputBefore = jsonEncode(config.toJson());
        final frozen = await fixture.gate.enforceAndFreeze(config);
        expect(jsonEncode(config.toJson()), inputBefore);
        expect(frozen.characterCard!.name, 'name_A');
        expect(frozen.characterCard!.description, 'background_A');
        expect(frozen.characterCard!.personality, 'personality_A');
        expect(frozen.characterCard!.firstMessage, 'greeting_A');
        expect(frozen.characterCard!.systemPrompt, 'system_A');
        expect(frozen.characterCard!.scenario, 'scenario_A');
        expect(frozen.characterCard!.exampleDialogues, 'dialogue_A');
        expect(frozen.characterCard!.customAttributes.single.value, 'value_A');
        expect(frozen.name, 'name_A');
        expect(frozen.gender, 'gender_A');
        expect(frozen.age, '21');
        expect(frozen.personality, 'personality_A');
        expect(frozen.protagonistClass, 'profession_A');
        expect(frozen.protagonistBackground, 'background_A');
        for (final selected in frozen.selectedCharacters) {
          expect(selected.characterName, 'name_A');
          expect(selected.characterAvatar, isEmpty);
          expect(jsonEncode(selected.characterCardJson), isNot(contains('_B')));
        }
        expect(frozen.selectedCharacters.last.narrativeRole,
            AdventureCharacterRole.mentor);
        final support = frozen.supportingCharacters.first;
        expect(support.id, 'companion-selection');
        expect(support.name, 'name_A');
        expect(support.gender, 'gender_A');
        expect(support.personality, 'personality_A');
        expect(support.role, 'profession_A');
        expect(support.relation, '用户指定关系');
        expect(support.customAttributes.single.value, 'value_A');
        expect(jsonEncode(support.toJson()), isNot(contains('_B')));
        final frozenNpc = frozen.supportingCharacters[1];
        expect(frozenNpc.id, npc.value);
        expect(frozenNpc.name, 'name_A');
        expect(frozenNpc.gender, 'gender_A');
        expect(frozenNpc.personality, 'personality_A');
        expect(frozenNpc.role, 'role_A');
        expect(frozenNpc.relation, 'relation_A');
        expect(frozenNpc.height, 'height_A');
        expect(frozenNpc.hairColor, 'hair_A');
        expect(frozenNpc.affinity, 17);
        expect(frozenNpc.isAlive, isTrue);
        expect(frozenNpc.customAttributes.single.value, 'value_A');
        expect(frozen.supportingCharacters.last.toJson(), legacy.toJson());
        final snapshot = frozen.npcSnapshots.single;
        expect(snapshot.name, 'name_A');
        expect(snapshot.originWorldviewId, 'world_A');
        expect(jsonEncode(snapshot.npcJson), isNot(contains('_B')));
        expect(frozen.resourceBindings, hasLength(3));
        for (final binding in frozen.resourceBindings) {
          expect(binding.revisionId,
              ready[binding.resourceId]!.assemblyRevisionId);
          expect(binding.contentHash,
              ready[binding.resourceId]!.assemblyContentHash);
          expect(binding.staleAllowed, stale);
        }
        final frozenBefore = jsonEncode(frozen.toJson());
        await write('hero', 'C', update: true);
        await write('npc', 'C', npc: true, update: true);
        expect(jsonEncode(frozen.toJson()), frozenBefore);
        final reloaded = AdventureConfig.fromJson(jsonDecode(frozenBefore));
        expect(reloaded.characterCard!.systemPrompt, 'system_A');
        expect(reloaded.supportingCharacters[1].height, 'height_A');
      });
    }
  });
}
