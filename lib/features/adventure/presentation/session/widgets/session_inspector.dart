import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../application/adventure/adventure_character_identity.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/workbench_section.dart';
import '../../../../prompt_settings/presentation/screens/context_weight_controls.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../screens/chat/widgets/character_switcher.dart';
import 'reply_length_control.dart';

enum SessionInspectorSection { scene, characters, state, context, generation }

/// The live, independently scrollable body for one Inspector section.
///
/// All panel/modal chrome (title, close button, section tabs) lives on
/// [SessionInspectorPage]; this widget owns only the content, so it can be
/// mounted on a real page without any popup-specific close affordance.
class SessionInspectorContent extends ConsumerWidget {
  const SessionInspectorContent(
      {super.key,
      required this.section,
      required this.onCharacters,
      required this.onState,
      required this.onInventory,
      required this.onModel});

  final SessionInspectorSection section;
  final VoidCallback onCharacters;
  final VoidCallback onState;
  final VoidCallback onInventory;
  final VoidCallback onModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final chat = ref.watch(chatProvider);
    final adventure = chat.adventureProvider;
    final scene = adventure.sceneState;
    final characters =
        adventure.adventureConfig?.selectedCharacters ?? const [];
    final present = characters
        .where((character) => scene.presentCharacterIds
            .contains(AdventureCharacterIdentity.effectiveId(character)))
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      // Reading-width discipline: do not stretch the controls across an
      // ultra-wide page, but let them use the full width on small screens.
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: switch (section) {
            SessionInspectorSection.context => const ContextWeightControls(),
            SessionInspectorSection.generation => WorkbenchSection(
                title: l10n.workbenchGeneration,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextButton(
                          onPressed: onModel,
                          child: Text(
                              '${l10n.switchModelAction}: ${chat.modelName.isEmpty ? chat.providerType.defaultModel : chat.modelName}')),
                      const ReplyLengthControl(),
                    ])),
            SessionInspectorSection.characters => WorkbenchSection(
                title: l10n.sceneCharactersTitle,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(l10n.sceneCharactersPresent,
                          style: Theme.of(context).textTheme.titleSmall),
                      for (final character in present)
                        Text(character.characterName),
                      if (present.isEmpty) Text(l10n.characterManagementNoData),
                      const SizedBox(height: 12),
                      Text(l10n.characterManagementOutOfScene,
                          style: Theme.of(context).textTheme.titleSmall),
                      for (final character in characters
                          .where((item) => !present.contains(item)))
                        Text(character.characterName),
                      TextButton(
                          onPressed: onCharacters,
                          child: Text(l10n.sceneCharactersTitle)),
                      if (adventure.adventureConfig != null)
                        CharacterSwitcher(
                            isDark:
                                Theme.of(context).brightness == Brightness.dark,
                            config: adventure.adventureConfig,
                            gameState:
                                adventure.inGame ? adventure.gameState : null,
                            selectedCharacterIndex: chat.selectedCharacterIndex,
                            autoAdvanceCharacter: chat.autoAdvanceCharacter,
                            sceneParticipantIds: chat.sceneParticipantIds,
                            onSelectCharacter: chat.selectCharacter,
                            onToggleAutoAdvance: chat.toggleAutoAdvance,
                            onTapCharacter: (_, __, ___, ____, _____) =>
                                onState()),
                    ])),
            SessionInspectorSection.scene => WorkbenchSection(
                title: l10n.workbenchScene,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(scene.location.isEmpty
                          ? (adventure.gameState.currentScene.isEmpty
                              ? l10n.unknownRegion
                              : adventure.gameState.currentScene)
                          : scene.location),
                      if (scene.time.isNotEmpty) Text(scene.time),
                      const SizedBox(height: 12),
                      Text(l10n.sceneCharactersPresent,
                          style: Theme.of(context).textTheme.titleSmall),
                      for (final character in present)
                        Text(character.characterName),
                      for (final goal in scene.goals) Text(goal.description),
                      for (final event in scene.unresolvedEvents) Text(event),
                      TextButton(
                          onPressed: onCharacters,
                          child: Text(l10n.sceneCharactersTitle)),
                    ])),
            SessionInspectorSection.state => WorkbenchSection(
                title: l10n.runtimeStateCurrent,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                          '${l10n.runtimeStateFieldHp}: ${adventure.gameState.hp}/${adventure.gameState.maxHp}'),
                      Text(
                          '${l10n.runtimeStateFieldMp}: ${adventure.gameState.mp}/${adventure.gameState.maxMp}'),
                      for (final change in scene.recentChanges) Text(change),
                      TextButton(
                          onPressed: onState,
                          child: Text(l10n.runtimeStateHistoricalChange)),
                      TextButton(
                          onPressed: onInventory,
                          child: Text(l10n.inventoryTitle)),
                    ])),
          },
        ),
      ),
    );
  }
}
