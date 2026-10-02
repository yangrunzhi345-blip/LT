import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../application/adventure/adventure_character_identity.dart';
import '../../../../../application/adventure/adventure_tracked_state_registry.dart';
import '../../../../../core/feedback/app_feedback.dart';
import '../../../../../core/responsive/app_breakpoints.dart';
import '../../../../../core/widgets/app_page_scaffold.dart';
import '../../../../../core/widgets/app_select.dart';
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
/// from the frozen config, not from a protagonist-first shortcut. All entities
/// share one editor and one feature set; there is no protagonist-only path.
///
/// Desktop uses a two-pane (entity list | editor) layout; narrow screens use a
/// single dropdown selector above the editor.
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
  String? _draftKey;
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
    final key = '${_entityType.name}:$_entityId';
    if (_draftKey != key) {
      _draft = current.map((b) => b.definition).toList();
      _draftKey = key;
    }
    final selected = roster.firstWhere(
      (e) => e.type == _entityType && e.id == _entityId,
      orElse: () => roster.first,
    );

    return AppPageScaffold(
      title: l10n.trackedStateManageTitle,
      maxWidth: null,
      body: LayoutBuilder(builder: (context, constraints) {
        final twoPane = constraints.maxWidth >= AppBreakpoints.expandedMin;
        final editor = _buildEditor(context, l10n, config, entities, selected);
        if (!twoPane) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppSelect<_RosterEntity>(
                value: selected,
                label: l10n.trackedStateManageTitle,
                items: [
                  for (final entity in roster)
                    AppSelectItem(
                      value: entity,
                      label: _rosterLabel(entity, l10n),
                      subtitle: _typeLabel(entity.type, l10n),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) _select(registry, value);
                },
              ),
              const SizedBox(height: 16),
              editor,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 240,
              child: _buildRosterList(context, l10n, roster),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: editor,
              ),
            ),
          ],
        );
      }),
    );
  }

  void _select(AdventureTrackedStateRegistry registry, _RosterEntity entity) {
    setState(() {
      _entityType = entity.type;
      _entityId = entity.id;
      _draft = registry
          .forEntity(entity.type, entity.id)
          .map((b) => b.definition)
          .toList();
      _draftKey = '${entity.type.name}:${entity.id}';
    });
  }

  Widget _buildRosterList(
    BuildContext context,
    AppLocalizations l10n,
    List<_RosterEntity> roster,
  ) {
    final theme = Theme.of(context);
    final children = <Widget>[];
    RuntimeEntityType? previousType;
    for (final entity in roster) {
      if (entity.type != previousType) {
        previousType = entity.type;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            _typeLabel(entity.type, l10n),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ));
      }
      final selected = entity.type == _entityType && entity.id == _entityId;
      children.add(ListTile(
        key: ValueKey('tracked-entity-${entity.type.name}-${entity.id}'),
        dense: true,
        selected: selected,
        title: Text(
          _rosterLabel(entity, l10n),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => _select(
          AdventureTrackedStateRegistry.fromConfig(
              ref.read(adventureProvider).adventureConfig),
          entity,
        ),
      ));
    }
    return ListView(
        padding: const EdgeInsets.symmetric(vertical: 8), children: children);
  }

  Widget _buildEditor(
    BuildContext context,
    AppLocalizations l10n,
    AdventureConfig config,
    List<RuntimeEntityState> entities,
    _RosterEntity selected,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${l10n.trackedStateManageTitle} · ${_rosterLabel(selected, l10n)}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        TrackedStateDefinitionEditorSection(
          key: ValueKey('tracked-editor-${_entityType.name}-$_entityId'),
          initialItems: AdventureTrackedStateRegistry.fromConfig(config)
              .forEntity(_entityType, _entityId)
              .map((b) => b.definition)
              .toList(),
          onChanged: (items) => _draft = items,
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _saving ? null : () => _save(context, config, entities),
            child: Text(l10n.saveAction),
          ),
        ),
      ],
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
    return _typeLabel(entity.type, l10n);
  }

  String _typeLabel(RuntimeEntityType type, AppLocalizations l10n) =>
      switch (type) {
        RuntimeEntityType.character => l10n.trackedStateEntityTypeCharacter,
        RuntimeEntityType.npc => l10n.trackedStateEntityTypeNpc,
        RuntimeEntityType.world => l10n.trackedStateEntityTypeWorld,
        _ => l10n.trackedStateEntityTypeCharacter,
      };
}

class _RosterEntity {
  final RuntimeEntityType type;
  final String id;
  final String? name;

  const _RosterEntity(this.type, this.id, {this.name});

  @override
  bool operator ==(Object other) =>
      other is _RosterEntity && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);
}
