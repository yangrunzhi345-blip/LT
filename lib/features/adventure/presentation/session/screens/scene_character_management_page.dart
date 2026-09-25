import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../../application/adventure/adventure_character_identity.dart';
import '../../../../../models/adventure_config.dart';
import '../../../../../models/adventure_runtime_state.dart';
import '../../../../../models/character_card_entry.dart';
import '../../../../../models/scene_dialogue.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../wizard/screens/character_selection_page.dart';

/// Manages branch-local scene presence without changing the startup roster.
class SceneCharacterManagementPage extends ConsumerWidget {
  const SceneCharacterManagementPage({super.key});

  AppLocalizations _l10n(BuildContext context) =>
      AppLocalizations.of(context) ?? AppLocalizationsZh();

  Future<void> _addCharacter(BuildContext context, WidgetRef ref) async {
    final provider = ref.read(chatProvider).adventureProvider;
    final excludedIds = {
      for (final character in provider.adventureConfig?.selectedCharacters ??
          const <AdventureSelectedCharacter>[])
        ...AdventureCharacterIdentity.candidateIds(character),
    };
    final selected = await Navigator.of(context).push<List<CharacterCardEntry>>(
      MaterialPageRoute(
        builder: (_) => CharacterSelectionPage(
          isMultiSelect: false,
          excludedIds: excludedIds,
        ),
      ),
    );
    final card = selected?.firstOrNull;
    if (card == null || !context.mounted) return;
    final character = AdventureSelectedCharacter(
      id: 'dynamic-${card.id}',
      characterId: card.id,
      characterName: card.name,
      characterCardJson: Map<String, dynamic>.from(card.rawData),
    );
    final result = await provider.attachCharacterToAdventure(character);
    if (!context.mounted || result == null) return;
    if (result.status != SceneMutationStatus.applied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_l10n(context).sceneCharactersConflict)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ref.watch(chatProvider).adventureProvider;
    final l10n = _l10n(context);
    final config = provider.adventureConfig;
    final present = provider.sceneParticipantIds.toSet();
    final characters = config?.selectedCharacters ?? const [];
    final deadIds = {
      for (final entity in provider.runtimeEntities)
        if (entity.entityType == RuntimeEntityType.character &&
            (entity.lifecycleStatus == 'dead' ||
                entity.overlay['life_status'] == 'dead'))
          entity.entityId,
    };
    final available = characters.where((character) {
      final id = AdventureCharacterIdentity.effectiveId(character);
      return !present.contains(id) && !character.isProtagonist;
    }).toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sceneCharactersTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l10n.sceneCharactersPresent,
                style: Theme.of(context).textTheme.titleMedium),
            for (final id in provider.sceneParticipantIds)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(_displayName(config, id)),
                trailing: id == 'protagonist'
                    ? null
                    : IconButton(
                        tooltip: l10n.sceneCharactersLeave,
                        icon: const Icon(Icons.logout_outlined),
                        onPressed: () => provider.removeCharacterFromScene(id),
                      ),
              ),
            const SizedBox(height: 20),
            Text(l10n.sceneCharactersAvailable,
                style: Theme.of(context).textTheme.titleMedium),
            if (available.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(l10n.sceneCharactersEmpty),
              ),
            for (final character in available)
              ListTile(
                title: Text(character.characterName),
                trailing: IconButton(
                  tooltip: l10n.sceneCharactersEnter,
                  icon: const Icon(Icons.login_outlined),
                  onPressed: deadIds.contains(
                          AdventureCharacterIdentity.effectiveId(character))
                      ? null
                      : () => provider.addCharacterToScene(
                            AdventureCharacterIdentity.effectiveId(character),
                          ),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _addCharacter(context, ref),
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(l10n.sceneCharactersAdd),
            ),
          ],
        ),
      ),
    );
  }

  String _displayName(AdventureConfig? config, String id) {
    if (id == 'protagonist') return config?.name ?? id;
    for (final character in config?.selectedCharacters ?? const []) {
      if (character.characterId == id || character.id == id) {
        return character.characterName;
      }
    }
    return id;
  }
}
