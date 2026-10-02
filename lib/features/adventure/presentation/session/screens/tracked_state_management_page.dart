import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../application/adventure/adventure_character_identity.dart';
import '../../../../../application/adventure/adventure_tracked_state_registry.dart';
import '../../../../../core/feedback/app_feedback.dart';
import '../../../../../core/widgets/app_page_scaffold.dart';
import '../../../../../core/widgets/tracked_state_definition_editor_section.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../../models/adventure_config.dart';
import '../../../../../models/adventure_runtime_state.dart';
import '../../../../../models/adventure_tracked_state.dart';
import '../../../../../models/tracked_state_definition.dart';
import '../../../../../providers/riverpod_providers.dart';

/// Standalone management surface for the current adventure's monitored fields.
///
/// Every entity a narrative can touch appears here — protagonist, companions,
/// selected-only companions, NPCs and the world — because the roster is built
/// from the frozen config, not from a protagonist-first shortcut.
class TrackedStateManagementPage extends ConsumerStatefulWidget {
  const TrackedStateManagementPage({super.key});

  @override
  ConsumerState<TrackedStateManagementPage> createState() =>
      _TrackedStateManagementPageState();
}

class _TrackedStateManagementPageState
    extends ConsumerState<TrackedStateManagementPage> {
  RuntimeEntityType _entityType = RuntimeEntityType.world;
  String _entityId = AdventureRuntimeEntityIds.world;
  List<TrackedStateDefinition> _draft = const [];
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final config = ref.watch(adventureProvider).adventureConfig;
    final entities = ref.watch(adventureProvider).runtimeEntities;

    if (config == null) {
      return AppPageScaffold(
        title: l10n.trackedStateManageTitle,
        body: Center(child: Text(l10n.runtimeStateNoChanges)),
      );
    }

    final roster = _roster(config);
    if (!roster.any((e) => e.type == _entityType && e.id == _entityId)) {
      final first = roster.first;
      _entityType = first.type;
      _entityId = first.id;
    }
    final registry = AdventureTrackedStateRegistry.fromConfig(config);
    final current = registry.forEntity(_entityType, _entityId);
    // Keep the editor in sync with the selected entity until the user edits.
    if (_draft.isEmpty && current.isNotEmpty) {
      _draft = current.map((b) => b.definition).toList();
    }

    return AppPageScaffold(
      title: l10n.trackedStateManageTitle,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entity in roster)
                ChoiceChip(
                  label: Text(_rosterLabel(entity, l10n)),
                  selected:
                      entity.type == _entityType && entity.id == _entityId,
                  onSelected: (_) => setState(() {
                    _entityType = entity.type;
                    _entityId = entity.id;
                    _draft = registry
                        .forEntity(entity.type, entity.id)
                        .map((b) => b.definition)
                        .toList();
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TrackedStateDefinitionEditorSection(
            key: ValueKey('${_entityType.name}:$_entityId'),
            initialItems: current.map((b) => b.definition).toList(),
            onChanged: (items) => _draft = items,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed:
                  _saving ? null : () => _save(context, config, entities),
              child: Text(l10n.saveAction),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save(
    BuildContext context,
    AdventureConfig config,
    List<RuntimeEntityState> runtimeEntities,
  ) async {
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final updated = _replaceEntityDefinitions(
      config: config,
      entityType: _entityType,
      entityId: _entityId,
      definitions: _draft,
    );
    final removals = _runtimeRemovals(
      config: config,
      runtimeEntities: runtimeEntities,
      entityType: _entityType,
      entityId: _entityId,
      definitions: _draft,
    );
    final ok = await ref.read(adventureProvider).applyTrackedStateEdit(
          updatedConfig: updated,
          runtimeRemovals: removals,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok && context.mounted) {
      AppFeedback.error(context, l10n.characterCardSaveFailed(''));
    }
  }

  AdventureConfig _replaceEntityDefinitions({
    required AdventureConfig config,
    required RuntimeEntityType entityType,
    required String entityId,
    required List<TrackedStateDefinition> definitions,
  }) {
    final kept = config.trackedStateDefinitions
        .where((binding) =>
            !(binding.entityType == entityType && binding.entityId == entityId))
        .toList();
    for (final definition in definitions) {
      if (definition.name.trim().isEmpty) continue;
      kept.add(AdventureTrackedStateDefinition(
        entityType: entityType,
        entityId: entityId,
        definition: definition,
      ));
    }
    return config.copyWith(trackedStateDefinitions: kept);
  }

  /// Removes runtime values whose definition was deleted or whose new shape no
  /// longer accepts the current value. History is never touched.
  List<RuntimeStateChangeProposal> _runtimeRemovals({
    required AdventureConfig config,
    required List<RuntimeEntityState> runtimeEntities,
    required RuntimeEntityType entityType,
    required String entityId,
    required List<TrackedStateDefinition> definitions,
  }) {
    final registry = AdventureTrackedStateRegistry.fromConfig(config);
    final overlay = runtimeEntities
            .where((e) => e.entityType == entityType && e.entityId == entityId)
            .firstOrNull
            ?.overlay ??
        const <String, Object?>{};
    final nextById = {
      for (final definition in definitions)
        if (definition.name.trim().isNotEmpty)
          definition.effectiveId: definition,
    };
    final removals = <RuntimeStateChangeProposal>[];
    for (final binding in registry.forEntity(entityType, entityId)) {
      final path = RuntimeStateChangeProposal.customAttributePath(
        binding.definitionId,
      );
      if (!overlay.containsKey(path)) continue;
      final next = nextById[binding.definitionId];
      final invalidated = next == null || !next.accepts(overlay[path]);
      if (!invalidated) continue;
      removals.add(RuntimeStateChangeProposal(
        entityType: entityType,
        entityId: entityId,
        changeKind: RuntimeChangeKind.primary,
        operation: RuntimeChangeOperation.remove,
        path: path,
        value: null,
        reason: 'Tracked state definition changed',
      ));
    }
    return removals;
  }

  List<_RosterEntity> _roster(AdventureConfig config) {
    final result = <_RosterEntity>[
      const _RosterEntity(
          RuntimeEntityType.world, AdventureRuntimeEntityIds.world),
    ];
    final seen = <String>{};
    for (final selected in config.selectedCharacters) {
      final id = AdventureCharacterIdentity.effectiveId(selected);
      if (id.isEmpty || !seen.add(id)) continue;
      result.add(_RosterEntity(
        RuntimeEntityType.character,
        id,
        name: selected.characterName,
      ));
    }
    for (final character in config.supportingCharacters) {
      final id = character.id.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      result.add(_RosterEntity(
        RuntimeEntityType.character,
        id,
        name: character.name,
      ));
    }
    for (final npc in config.npcSnapshots) {
      final id = npc.assetId.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      result.add(_RosterEntity(RuntimeEntityType.npc, id, name: npc.name));
    }
    return result;
  }

  String _rosterLabel(_RosterEntity entity, AppLocalizations l10n) {
    final name = entity.name?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return entity.type == RuntimeEntityType.world
        ? l10n.worldviewModuleState
        : entity.id;
  }
}

class _RosterEntity {
  final RuntimeEntityType type;
  final String id;
  final String? name;

  const _RosterEntity(this.type, this.id, {this.name});
}
