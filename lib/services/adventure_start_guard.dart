import 'dart:convert';

import '../models/adventure_config.dart';

class DuplicateStartIgnoredException implements Exception {
  const DuplicateStartIgnoredException();

  @override
  String toString() => 'DuplicateStartIgnoredException';
}

class AdventureStartGuard {
  static const Duration cooldown = Duration(seconds: 2);

  final Map<String, Future<int>> _inFlight = {};
  final Map<String, DateTime> _lastStartedAt = {};

  static String keyForConfig(AdventureConfig config) {
    final card = config.characterCard;
    final selectedCharacters = config.selectedCharacters.isNotEmpty
        ? config.selectedCharacters
        : (card != null || config.name.isNotEmpty)
            ? [
                AdventureSelectedCharacter(
                  id: 'legacy_protagonist',
                  characterId: 'legacy_protagonist',
                  characterName:
                      config.name.isNotEmpty ? config.name : card?.name ?? '',
                  isProtagonist: true,
                  narrativeRole: AdventureCharacterRole.protagonist,
                  sortOrder: 0,
                  characterCardJson: card?.toJson(),
                ),
              ]
            : const <AdventureSelectedCharacter>[];
    return jsonEncode({
      'worldview': config.worldview,
      // Freeze assigns a new observation timestamp each time. It must not
      // turn one resource/version selection into different start identities.
      'worldviewSnapshot': config.worldviewSnapshot == null
          ? null
          : {
              for (final entry in config.worldviewSnapshot!.entries)
                if (entry.key != 'created_at') entry.key: entry.value,
            },
      'name': config.name,
      'gender': config.gender,
      'age': config.age,
      'protagonistClass': config.protagonistClass,
      'protagonistBackground': config.protagonistBackground,
      'supportingCharacters': config.supportingCharacters
          .map((c) => {
                'name': c.name,
                'relation': c.relation,
                'personality': c.personality,
                'role': c.role,
                'gender': c.gender,
                'height': c.height,
                'skinTone': c.skinTone,
                'facialFeatures': c.facialFeatures,
                'hairStyle': c.hairStyle,
                'hairColor': c.hairColor,
                'chest': c.chest,
                'waist': c.waist,
                'hips': c.hips,
                'legLength': c.legLength,
              })
          .toList(),
      'height': config.height,
      'skinTone': config.skinTone,
      'facialFeatures': config.facialFeatures,
      'hairStyle': config.hairStyle,
      'hairColor': config.hairColor,
      'neckLength': config.neckLength,
      'shoulders': config.shoulders,
      'chest': config.chest,
      'waist': config.waist,
      'hips': config.hips,
      'legLength': config.legLength,
      'feet': config.feet,
      'customBodyDescription': config.customBodyDescription,
      'personality': config.personality,
      'narrativePerson': config.narrativePerson,
      'styleEnhancement': config.styleEnhancement,
      'openingScene': config.openingScene,
      'customOpeningScene': config.customOpeningScene,
      'openingOptions': List<String>.from(config.openingOptions),
      'selectedCharacters': selectedCharacters
          .map((character) => {
                'characterId': character.characterId,
                'characterName': character.characterName,
                'characterAvatar': character.characterAvatar,
                'isProtagonist': character.isProtagonist,
                'narrativeRole': character.narrativeRole,
                'customRoleName': character.customRoleName,
                'sortOrder': character.sortOrder,
                'characterCardJson': character.characterCardJson,
              })
          .toList(),
      'characterRelationships': config.characterRelationships
          .map((relationship) => {
                'sourceCharacterId': relationship.sourceCharacterId,
                'targetCharacterId': relationship.targetCharacterId,
                'relationType': relationship.relationType,
                'customRelationName': relationship.customRelationName,
                'description': relationship.description,
              })
          .toList(),
      if (card != null)
        'characterCard': {
          'name': card.name,
          'description': card.description,
          'personality': card.personality,
          'scenario': card.scenario,
          'firstMessage': card.firstMessage,
          'exampleDialogues': card.exampleDialogues,
          'creatorNotes': card.creatorNotes,
          'systemPrompt': card.systemPrompt,
          'postHistoryInstructions': card.postHistoryInstructions,
          'alternateGreetings': List<String>.from(card.alternateGreetings),
          'characterVersion': card.characterVersion,
          'tags': List<String>.from(card.tags),
          'creator': card.creator,
          'appearance': card.appearance,
          'ability': card.ability,
          'weakness': card.weakness,
          'equipment': card.equipment,
        },
    });
  }

  Future<int> run({
    required String presetKey,
    required Future<int> Function() create,
  }) {
    final existing = _inFlight[presetKey];
    if (existing != null) return existing;

    final now = DateTime.now();
    final lastStartedAt = _lastStartedAt[presetKey];
    if (lastStartedAt != null && now.difference(lastStartedAt) < cooldown) {
      throw const DuplicateStartIgnoredException();
    }

    _lastStartedAt[presetKey] = now;
    final future = Future<int>.sync(create);
    _inFlight[presetKey] = future;
    void cleanup() {
      if (identical(_inFlight[presetKey], future)) _inFlight.remove(presetKey);
    }

    // Observe the derived future too; a failed start must neither create an
    // unhandled duplicate error nor prevent an immediate corrected retry.
    future.then((_) => cleanup(), onError: (Object _, StackTrace __) {
      cleanup();
      _lastStartedAt.remove(presetKey);
    });
    return future;
  }
}
