import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../application/adventure/adventure_character_identity.dart';
import '../../../../../application/adventure/adventure_tracked_state_registry.dart';
import '../../../../../core/feedback/app_feedback.dart';
import '../../../../../core/responsive/app_breakpoints.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
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
/// Layout: desktop uses a two-pane workbench (entity navigator | editor) with a
/// single sticky save bar; narrow screens use a dropdown selector above the
/// editor. Edits are kept per entity, so switching entities never discards
/// unsaved work, and one save persists every pending entity edit together.
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

  /// Unsaved definitions per entity. Absent means "unchanged from the frozen
  /// config"; present means the user edited that entity in this session.
  final Map<_RosterEntity, List<TrackedStateDefinition>> _drafts = {};
  bool _saving = false;

  /// Bumped after a save so the embedded editor reloads from persisted state.
  int _editorEpoch = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final provider = ref.watch(adventureProvider);
    final config = provider.adventureConfig;

    if (config == null) {
      return AppPageScaffold(
        title: l10n.trackedStateManageTitle,
        body: Center(child: Text(l10n.runtimeStateNoChanges)),
      );
    }

    final roster = _roster(config);
    final selected = _resolveSelection(roster);
    final registry = AdventureTrackedStateRegistry.fromConfig(config);
    final dirty = _isDirty(registry);

    return AppPageScaffold(
      title: l10n.trackedStateManageTitle,
      maxWidth: null,
      bottomBar: _buildSaveBar(context, l10n, dirty),
      body: LayoutBuilder(builder: (context, constraints) {
        final twoPane = constraints.maxWidth >= AppBreakpoints.expandedMin;
        final editor = _buildEditor(context, l10n, registry, selected);
        if (!twoPane) {
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              AppSelect<_RosterEntity>(
                value: selected,
                label: l10n.trackedStateEntityNavTitle,
                items: [
                  for (final entity in roster)
                    AppSelectItem(
                      value: entity,
                      label: _rosterLabel(entity, l10n),
                      subtitle: _typeLabel(entity.type, l10n),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) _select(value);
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              editor,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 260,
              child: _buildRoster(context, l10n, roster, registry),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: editor,
              ),
            ),
          ],
        );
      }),
    );
  }

  /// Resolves the current selection without mutating state during build.
  _RosterEntity _resolveSelection(List<_RosterEntity> roster) =>
      roster.firstWhere(
        (e) => e.type == _entityType && e.id == _entityId,
        orElse: () => roster.first,
      );

  void _select(_RosterEntity entity) {
    setState(() {
      _entityType = entity.type;
      _entityId = entity.id;
    });
  }

  void _onDraftChanged(
      _RosterEntity entity, List<TrackedStateDefinition> items) {
    setState(() => _drafts[entity] = items);
  }

  List<TrackedStateDefinition> _currentDefinitions(
    AdventureTrackedStateRegistry registry,
    _RosterEntity entity,
  ) =>
      registry
          .forEntity(entity.type, entity.id)
          .map((b) => b.definition)
          .toList();

  bool _isDirty(AdventureTrackedStateRegistry registry) =>
      _drafts.entries.any((entry) =>
          _signature(entry.value) !=
          _signature(_currentDefinitions(registry, entry.key)));

  /// Order-insensitive-per-field signature used to detect real edits. Comparing
  /// serialized shapes avoids relying on `Set == Set` identity semantics.
  String _signature(List<TrackedStateDefinition> definitions) =>
      definitions.where((d) => d.name.trim().isNotEmpty).map((d) {
        final enums = d.enumValues.toList()..sort();
        return [
          d.effectiveId,
          d.name.trim(),
          d.valueKind.name,
          d.description.trim(),
          d.importance.name,
          _numSig(d.minimum),
          _numSig(d.maximum),
          enums.join('|'),
          d.icon ?? '',
        ].join('\u0001');
      }).join('\u0002');

  static String _numSig(num? value) {
    if (value == null) return '';
    return value == value.truncate()
        ? value.truncate().toString()
        : value.toString();
  }

  // ─── Entity navigator ────────────────────────────────────────────────────

  Widget _buildRoster(
    BuildContext context,
    AppLocalizations l10n,
    List<_RosterEntity> roster,
    AdventureTrackedStateRegistry registry,
  ) {
    final children = <Widget>[];
    RuntimeEntityType? previousType;
    for (final entity in roster) {
      if (entity.type != previousType) {
        previousType = entity.type;
        // A single, un-named world entity would otherwise repeat its own label
        // right below the group caption.
        final group = roster.where((e) => e.type == entity.type).toList();
        final redundant = group.length == 1 &&
            _rosterLabel(group.first, l10n) == _typeLabel(entity.type, l10n);
        if (!redundant) {
          children.add(_groupCaption(context, l10n, entity.type));
        }
      }
      children.add(_rosterRow(context, l10n, registry, entity));
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: children,
    );
  }

  Widget _groupCaption(
    BuildContext context,
    AppLocalizations l10n,
    RuntimeEntityType type,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xs),
      child: Text(
        _typeLabel(type, l10n).toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _rosterRow(
    BuildContext context,
    AppLocalizations l10n,
    AdventureTrackedStateRegistry registry,
    _RosterEntity entity,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final selected = entity.type == _entityType && entity.id == _entityId;
    final count = _currentDefinitions(registry, entity).length;
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 1),
      child: Material(
        color: selected ? scheme.surfaceContainerHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          key: ValueKey('tracked-entity-${entity.type.name}-${entity.id}'),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () => _select(entity),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _rosterLabel(entity, l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Editor ──────────────────────────────────────────────────────────────

  Widget _buildEditor(
    BuildContext context,
    AppLocalizations l10n,
    AdventureTrackedStateRegistry registry,
    _RosterEntity selected,
  ) {
    final theme = Theme.of(context);
    final draft = _drafts[selected] ?? _currentDefinitions(registry, selected);
    final count = draft.where((d) => d.name.trim().isNotEmpty).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _rosterLabel(selected, l10n),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 2),
        Text(
          '${_typeLabel(selected.type, l10n)} · ${l10n.trackedStateEntityCount(count)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TrackedStateDefinitionEditorSection(
          key: ValueKey(
              'tracked-editor-${selected.type.name}-${selected.id}-$_editorEpoch'),
          framed: false,
          initialItems: draft,
          onChanged: (items) => _onDraftChanged(selected, items),
        ),
      ],
    );
  }

  // ─── Save bar ────────────────────────────────────────────────────────────

  Widget _buildSaveBar(
    BuildContext context,
    AppLocalizations l10n,
    bool dirty,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl, vertical: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              dirty ? l10n.trackedStateUnsavedHint : l10n.trackedStateSavedHint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: dirty ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          FilledButton(
            onPressed: (_saving || !dirty) ? null : () => _save(context),
            child: Text(l10n.saveAction),
          ),
        ],
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    final provider = ref.read(adventureProvider);
    final config = provider.adventureConfig;
    if (config == null) return;
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    setState(() => _saving = true);

    var updated = config;
    final removals = <RuntimeStateChangeProposal>[];
    for (final entry in _drafts.entries) {
      updated = _replaceEntityDefinitions(
        config: updated,
        entity: entry.key,
        definitions: entry.value,
      );
      removals.addAll(_runtimeRemovals(
        config: config,
        runtimeEntities: provider.runtimeEntities,
        entity: entry.key,
        definitions: entry.value,
      ));
    }

    final ok = await provider.applyTrackedStateEdit(
      updatedConfig: updated,
      runtimeRemovals: removals,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) {
        _drafts.clear();
        _editorEpoch++;
      }
    });
    if (!ok && context.mounted) {
      AppFeedback.error(context, l10n.characterCardSaveFailed(''));
    }
  }

  AdventureConfig _replaceEntityDefinitions({
    required AdventureConfig config,
    required _RosterEntity entity,
    required List<TrackedStateDefinition> definitions,
  }) {
    final kept = config.trackedStateDefinitions
        .where((binding) => !(binding.entityType == entity.type &&
            binding.entityId == entity.id))
        .toList();
    for (final definition in definitions) {
      if (definition.name.trim().isEmpty) continue;
      kept.add(AdventureTrackedStateDefinition(
        entityType: entity.type,
        entityId: entity.id,
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
    required _RosterEntity entity,
    required List<TrackedStateDefinition> definitions,
  }) {
    final registry = AdventureTrackedStateRegistry.fromConfig(config);
    final overlay = runtimeEntities
            .where(
                (e) => e.entityType == entity.type && e.entityId == entity.id)
            .firstOrNull
            ?.overlay ??
        const <String, Object?>{};
    final nextById = {
      for (final definition in definitions)
        if (definition.name.trim().isNotEmpty)
          definition.effectiveId: definition,
    };
    final removals = <RuntimeStateChangeProposal>[];
    for (final binding in registry.forEntity(entity.type, entity.id)) {
      final path = RuntimeStateChangeProposal.customAttributePath(
        binding.definitionId,
      );
      if (!overlay.containsKey(path)) continue;
      final next = nextById[binding.definitionId];
      final invalidated = next == null || !next.accepts(overlay[path]);
      if (!invalidated) continue;
      removals.add(RuntimeStateChangeProposal(
        entityType: entity.type,
        entityId: entity.id,
        changeKind: RuntimeChangeKind.primary,
        operation: RuntimeChangeOperation.remove,
        path: path,
        value: null,
        reason: 'Tracked state definition changed',
      ));
    }
    return removals;
  }

  // ─── Roster / labels ─────────────────────────────────────────────────────

  List<_RosterEntity> _roster(AdventureConfig config) {
    final result = <_RosterEntity>[
      _RosterEntity(
        RuntimeEntityType.world,
        AdventureRuntimeEntityIds.world,
        name: _worldName(config),
      ),
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

  String? _worldName(AdventureConfig config) {
    final fromSnapshot =
        config.worldviewSnapshot?['name']?.toString().trim() ?? '';
    if (fromSnapshot.isNotEmpty) return fromSnapshot;
    final worldview = config.worldview.trim();
    return worldview.isEmpty ? null : worldview;
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
