import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/adventure_speaker_context.dart';
import 'package:lt_dialogue/domain/tts/speech_plan.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/services/tts/speech_planner.dart';

import '../helpers/tts_casting_fixture.dart';

void main() {
  group('Adventure speaker projection', () {
    test('should include protagonist, NPC and dynamic supporting stable ids',
        () {
      final config = AdventureConfig(selectedCharacters: [
        AdventureSelectedCharacter(
            id: 'selection',
            characterId: 'lin',
            characterName: '林雪',
            isProtagonist: true),
      ], npcSnapshots: [
        AdventureNpcSnapshot(assetId: 'npc-resource', name: '店主', npcJson: {}),
      ], supportingCharacters: [
        SupportingCharacter(id: 'dynamic', name: '陈默')
      ]);
      final context = buildAdventureSpeakerContext(config);
      expect(context.speakers.map((s) => s.resourceId).toSet(),
          {'lin', 'npc-resource', 'dynamic'});
      expect(
          const SpeechPlanner().plan('店主说：“欢迎。”', context).speakerResourceIds,
          ['npc-resource']);
    });

    test(
        'should preserve a renamed resource binding without reusing an orphan by name',
        () async {
      final fixture = TtsCastingFixture();
      addTearDown(fixture.dispose);
      await fixture.bindings.setAutoAssignVoices(false);
      final selected = AdventureSelectedCharacter(
          id: 'selection', characterId: 'lin', characterName: '林雪');
      final config = AdventureConfig(selectedCharacters: [selected]);
      final original = buildAdventureSpeakerContext(config).speakers.single;
      selected.characterName = '新名字';
      final renamed = buildAdventureSpeakerContext(config).speakers.single;
      expect(renamed.resourceId, original.resourceId);
      expect(
          fixture.resolver
              .resolve(
                  role: SpeechRole.dialogue,
                  speakerResourceId: renamed.resourceId)
              .target
              ?.speakerId,
          3);
      config.selectedCharacters.clear();
      config.selectedCharacters.add(AdventureSelectedCharacter(
          id: 'other-selection',
          characterId: 'other-resource',
          characterName: '新名字'));
      final replacement = buildAdventureSpeakerContext(config).speakers.single;
      expect(fixture.bindings.preferences.bindingFor('lin'), 'kokoro-v1_1:s3');
      expect(
          fixture.resolver
              .resolve(
                  role: SpeechRole.dialogue,
                  speakerResourceId: replacement.resourceId)
              .target
              ?.speakerId,
          0);
    });
  });
}
