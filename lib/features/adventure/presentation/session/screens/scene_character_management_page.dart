import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../application/adventure/adventure_character_identity.dart';
import '../../state/runtime_state_hub_page.dart';
import '../../state/runtime_state_presentation.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../../models/adventure_config.dart';
import '../../../../../models/adventure_runtime_state.dart';
import '../../../../../models/character_card_entry.dart';
import '../../../../../models/scene_dialogue.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../wizard/screens/character_selection_page.dart';

/// User facing roster and scene presence editor for the current adventure.
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

  Future<void> _mutatePresence(
    BuildContext context,
    Future<ScenePresenceMutationResult?> Function() operation,
  ) async {
    final result = await operation();
    if (!context.mounted || result == null) return;
    if (result.status != SceneMutationStatus.applied &&
        result.status != SceneMutationStatus.duplicate &&
        result.status != SceneMutationStatus.alreadyAttached) {
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
    final customLabels = RuntimeStatePresentation.customAttributeLabels(
      config?.allTrackedCustomAttributes ?? const [],
    );
    final presentIds = provider.sceneParticipantIds.toSet();
    final characters = config?.selectedCharacters ?? const [];
    final present = <AdventureSelectedCharacter>[];
    final away = <AdventureSelectedCharacter>[];
    for (final character in characters) {
      if (character.isProtagonist) {
        present.add(character);
        continue;
      }
      final ids = AdventureCharacterIdentity.candidateIds(character);
      (ids.any(presentIds.contains) ? present : away).add(character);
    }
    final enterable = <AdventureSelectedCharacter>[];
    final blocked = <AdventureSelectedCharacter>[];
    for (final character in away) {
      (_canEnter(character, provider.runtimeEntities) ? enterable : blocked)
          .add(character);
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.characterManagementTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            FilledButton.icon(
              onPressed: () => _addCharacter(context, ref),
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(l10n.characterManagementAdd),
            ),
            const SizedBox(height: 20),
            _sectionTitle(context, l10n.characterManagementPresent),
            if (present.isEmpty)
              _empty(context, l10n.characterManagementNoData)
            else
              for (final character in present)
                _characterCard(
                  context,
                  ref,
                  character,
                  isInScene: true,
                  customLabels: customLabels,
                  canLeave: !character.isProtagonist,
                ),
            const SizedBox(height: 20),
            _sectionTitle(context, l10n.sceneCharactersAvailable),
            if (enterable.isEmpty)
              _empty(context, l10n.sceneCharactersEmpty)
            else
              for (final character in enterable)
                _characterCard(
                  context,
                  ref,
                  character,
                  isInScene: false,
                  customLabels: customLabels,
                  canEnter: true,
                ),
            const SizedBox(height: 20),
            _sectionTitle(context, l10n.characterManagementJoined),
            if (blocked.isEmpty)
              _empty(context, l10n.characterManagementNoData)
            else
              for (final character in blocked)
                _characterCard(
                  context,
                  ref,
                  character,
                  isInScene: false,
                  customLabels: customLabels,
                  canEnter: false,
                ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _empty(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );

  Widget _characterCard(
    BuildContext context,
    WidgetRef ref,
    AdventureSelectedCharacter character, {
    required bool isInScene,
    required Map<String, String> customLabels,
    bool canLeave = false,
    bool canEnter = false,
  }) {
    final l10n = _l10n(context);
    final provider = ref.read(chatProvider).adventureProvider;
    final entity = _runtimeEntity(character, provider.runtimeEntities);
    final lifeStatus = _lifeStatus(entity);
    final isDead = lifeStatus == 'dead';
    final isUnknown = lifeStatus == null;
    final statusText = switch (lifeStatus) {
      'alive' => l10n.characterManagementAlive,
      'dead' => l10n.characterManagementDead,
      _ => l10n.characterManagementUnknown,
    };
    final statusColor = isDead
        ? Theme.of(context).colorScheme.error
        : isUnknown
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : Theme.of(context).colorScheme.primary;
    final summary = _runtimeSummary(context, entity, customLabels);
    final action = isInScene
        ? (canLeave
            ? IconButton(
                tooltip: l10n.sceneCharactersLeave,
                icon: const Icon(Icons.logout_outlined),
                onPressed: () => _mutatePresence(
                  context,
                  () => provider.removeCharacterFromScene(
                      AdventureCharacterIdentity.effectiveId(character)),
                ),
              )
            : null)
        : (canEnter
            ? IconButton(
                tooltip: l10n.sceneCharactersEnter,
                icon: const Icon(Icons.login_outlined),
                onPressed: () => _mutatePresence(
                  context,
                  () => provider.addCharacterToScene(
                      AdventureCharacterIdentity.effectiveId(character)),
                ),
              )
            : IconButton(
                tooltip: isDead
                    ? l10n.characterManagementDead
                    : l10n.characterManagementUnknown,
                icon: const Icon(Icons.block_outlined),
                onPressed: null,
              ));

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const RuntimeStateHubPage(openCharacters: true),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      character.characterName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  if (action != null) action,
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    isInScene
                        ? l10n.characterManagementInScene
                        : l10n.characterManagementOutOfScene,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  Text(
                    statusText,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: statusColor),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                summary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.characterManagementViewStatus,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _canEnter(
    AdventureSelectedCharacter character,
    List<RuntimeEntityState> entities,
  ) {
    if (character.isProtagonist) return false;
    return _lifeStatus(_runtimeEntity(character, entities)) == 'alive';
  }

  RuntimeEntityState? _runtimeEntity(
    AdventureSelectedCharacter character,
    List<RuntimeEntityState> entities,
  ) {
    final ids = AdventureCharacterIdentity.candidateIds(character);
    for (final entity in entities) {
      if ((entity.entityType == RuntimeEntityType.character ||
              entity.entityType == RuntimeEntityType.npc) &&
          ids.contains(entity.entityId)) {
        return entity;
      }
    }
    return null;
  }

  String? _lifeStatus(RuntimeEntityState? entity) {
    final raw = entity?.overlay['life_status'] ?? entity?.lifecycleStatus;
    if (raw == null || raw.toString().trim().isEmpty) return null;
    return switch (raw.toString().trim().toLowerCase()) {
      'alive' || 'active' => 'alive',
      'dead' || 'destroyed' => 'dead',
      _ => null,
    };
  }

  String _runtimeSummary(
    BuildContext context,
    RuntimeEntityState? entity,
    Map<String, String> customLabels,
  ) {
    final l10n = _l10n(context);
    if (entity == null || entity.overlay.isEmpty) {
      return l10n.characterManagementNoData;
    }
    const preferred = [
      'hp',
      'mp',
      'gold',
      'relationship',
      'affinity',
      'energy',
      'level',
    ];
    final values = <String>[];
    for (final path in preferred) {
      final value = entity.overlay[path];
      if (value == null || value.toString().trim().isEmpty) continue;
      values.add(
        '${path == 'gold' ? l10n.characterManagementGold : RuntimeStatePresentation.fieldLabel(path, l10n)}: '
        '${RuntimeStatePresentation.valueLabel(path, value, l10n)}',
      );
    }
    for (final entry in entity.overlay.entries) {
      if (preferred.contains(entry.key) ||
          entry.value == null ||
          entry.value.toString().trim().isEmpty) {
        continue;
      }
      values.add(
        '${RuntimeStatePresentation.fieldLabelWithMetadata(entry.key, l10n, customAttributeLabels: customLabels)}: '
        '${RuntimeStatePresentation.valueLabel(entry.key, entry.value, l10n)}',
      );
    }
    return values.isEmpty ? l10n.characterManagementNoData : values.join(' · ');
  }
}
