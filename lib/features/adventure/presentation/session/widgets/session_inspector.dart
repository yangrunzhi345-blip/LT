import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../application/adventure/adventure_character_identity.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_svg_icon.dart';
import '../../../../../core/widgets/workbench_section.dart';
import '../../../../prompt_settings/presentation/screens/context_weight_controls.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../screens/chat/widgets/character_switcher.dart';
import 'reply_length_control.dart';

enum SessionInspectorSection { scene, characters, state, context, generation }

/// Contextual controls and live state share a compact, independently scrollable pane.
class SessionInspector extends ConsumerWidget {
  const SessionInspector(
      {super.key,
      required this.section,
      required this.onSelect,
      required this.onClose,
      required this.onCharacters,
      required this.onState,
      required this.onInventory,
      required this.onModel});
  final SessionInspectorSection section;
  final ValueChanged<SessionInspectorSection> onSelect;
  final VoidCallback onClose;
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
    final labels = {
      SessionInspectorSection.scene: l10n.workbenchScene,
      SessionInspectorSection.characters: l10n.charactersTab,
      SessionInspectorSection.state: l10n.runtimeStateCurrent,
      SessionInspectorSection.context: l10n.workbenchContext,
      SessionInspectorSection.generation: l10n.workbenchGeneration,
    };
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Column(children: [
        Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(children: [
              Expanded(
                  child: Text(l10n.workbenchInspector,
                      style: Theme.of(context).textTheme.titleSmall)),
              IconButton(
                  tooltip: l10n.closeAction,
                  onPressed: onClose,
                  icon: const AppSvgIcon('close')),
            ])),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(spacing: 4, runSpacing: 4, children: [
              for (final entry in labels.entries)
                ChoiceChip(
                    key: ValueKey('inspector-${entry.key.name}'),
                    showCheckmark: false,
                    selected: section == entry.key,
                    label: Text(entry.value),
                    onSelected: (_) => onSelect(entry.key)),
            ])),
        const Divider(height: 16),
        Expanded(
            child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
              switch (section) {
                SessionInspectorSection.context =>
                  const ContextWeightControls(),
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
                          if (present.isEmpty)
                            Text(l10n.characterManagementNoData),
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
                                isDark: Theme.of(context).brightness ==
                                    Brightness.dark,
                                config: adventure.adventureConfig,
                                gameState: adventure.inGame
                                    ? adventure.gameState
                                    : null,
                                selectedCharacterIndex:
                                    chat.selectedCharacterIndex,
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
                          for (final goal in scene.goals)
                            Text(goal.description),
                          for (final event in scene.unresolvedEvents)
                            Text(event),
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
                          for (final change in scene.recentChanges)
                            Text(change),
                          TextButton(
                              onPressed: onState,
                              child: Text(l10n.runtimeStateHistoricalChange)),
                          TextButton(
                              onPressed: onInventory,
                              child: Text(l10n.inventoryTitle)),
                        ])),
              },
            ])),
      ]),
    );
  }
}
