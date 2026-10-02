import '../../domain/tts/speech_plan.dart';
import '../../models/adventure_config.dart';
import 'adventure_character_identity.dart';

/// Projects the structured Adventure roster into the pure-data speaker context
/// consumed by the read-aloud speech planner.
///
/// This is a read-only projection: it never mutates the config, never touches
/// SQLite and never calls an LLM. Stable resource ids come from
/// [AdventureCharacterIdentity.effectiveId] and [AdventureNpcSnapshot.assetId];
/// names are only used for matching, never as voice-binding authority.
NarrativeSpeakerContext buildAdventureSpeakerContext(AdventureConfig? config) {
  if (config == null) return const NarrativeSpeakerContext.empty();
  final speakers = <NarrativeSpeakerRef>[];

  for (final selected in config.selectedCharacters) {
    final resourceId = AdventureCharacterIdentity.effectiveId(selected);
    if (resourceId.isEmpty) continue;
    final name = selected.characterName.trim();
    if (name.isEmpty) continue;
    speakers.add(
      NarrativeSpeakerRef(
        resourceId: resourceId,
        displayName: name,
        resourceType: 'character',
      ),
    );
  }

  for (final npc in config.npcSnapshots) {
    final resourceId = npc.assetId.trim();
    final name = npc.name.trim();
    if (resourceId.isEmpty || name.isEmpty) continue;
    speakers.add(
      NarrativeSpeakerRef(
        resourceId: resourceId,
        displayName: name,
        resourceType: 'npc',
      ),
    );
  }

  for (final supporting in config.supportingCharacters) {
    final resourceId = supporting.id.trim();
    final name = supporting.name.trim();
    if (resourceId.isEmpty || name.isEmpty) continue;
    speakers.add(
      NarrativeSpeakerRef(
        resourceId: resourceId,
        displayName: name,
        resourceType: 'character',
      ),
    );
  }

  if (speakers.isEmpty) return const NarrativeSpeakerContext.empty();
  return NarrativeSpeakerContext(speakers: speakers);
}
