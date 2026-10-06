import 'package:flutter/material.dart';

import '../../../../application/adventure/adventure_tracked_state_registry.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_svg_icon.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../models/adventure_config.dart';
import '../../../../models/adventure_runtime_state.dart';
import '../../../../models/adventure_tracked_state.dart';
import 'tracked_state_presentation.dart';
import 'tracked_state_summary_view.dart';

/// Entity-type filter for the monitored-fields panel.
enum TrackedStateCategory { all, character, npc, world }

/// Read-only overview of every entity's monitored fields, driven by the single
/// [AdventureTrackedStateRegistry].
///
/// This is the runtime counterpart of the definition editor: characters, NPCs
/// and the world all render through one path, and a monitor with no runtime
/// value shows as "not triggered" instead of a fabricated zero.
///
/// The management action is **always** rendered when [onManage] is provided —
/// including when there are no monitored fields at all — so an adventure with
/// zero definitions can still reach the management surface and add its first
/// one. Never let the empty state short-circuit the call to action.
class TrackedStateOverviewPanel extends StatelessWidget {
  final AdventureConfig? config;
  final List<RuntimeEntityState> entities;
  final Map<String, String> entityNames;
  final VoidCallback? onManage;
  final TrackedStateCategory category;

  /// Compact mode collapses to a short summary (used on the dashboard).
  final bool compact;
  final int maximumEntities;

  const TrackedStateOverviewPanel({
    super.key,
    required this.config,
    required this.entities,
    this.entityNames = const {},
    this.onManage,
    this.category = TrackedStateCategory.all,
    this.compact = false,
    this.maximumEntities = 4,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final registry = AdventureTrackedStateRegistry.fromConfig(config);

    final groups = _groups(registry);

    if (groups.isEmpty) {
      // The empty state owns the call to action, so the management entry stays
      // reachable even when the adventure has no monitored fields yet.
      return AppEmptyState(
        icon: 'tune',
        title: l10n?.trackedStateNoDefinitions ?? 'No monitored fields',
        description: l10n?.trackedStateNoDefinitionsHint,
        actionLabel: onManage == null ? null : l10n?.trackedStateAddFirstAction,
        onAction: onManage,
      );
    }

    final manageAction = _managementAction(context, l10n, isEmpty: false);

    final overlayByEntity = <String, Map<String, Object?>>{
      for (final entity in entities)
        '${entity.entityType.name}:${entity.entityId}': entity.overlay,
    };

    final visible = compact ? groups.take(maximumEntities).toList() : groups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in visible) ...[
          _entityBlock(context, l10n, group, overlayByEntity[group.key]),
          const SizedBox(height: 12),
        ],
        if (compact && groups.length > visible.length)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '…',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (manageAction != null) manageAction,
      ],
    );
  }

  Widget? _managementAction(
    BuildContext context,
    AppLocalizations? l10n, {
    required bool isEmpty,
  }) {
    if (onManage == null) return null;
    final label = isEmpty
        ? (l10n?.trackedStateAddFirstAction ?? 'Add monitored field')
        : (l10n?.trackedStateManageAction ?? 'Manage monitored fields');
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onManage,
        icon: const AppSvgIcon('tune', size: 16),
        label: Text(label),
      ),
    );
  }

  List<_EntityGroup> _groups(AdventureTrackedStateRegistry registry) {
    final byKey = <String, _EntityGroup>{};
    for (final binding in registry.all) {
      if (!_matches(binding.entityType)) continue;
      final key = '${binding.entityType.name}:${binding.entityId}';
      byKey
          .putIfAbsent(
              key, () => _EntityGroup(binding.entityType, binding.entityId))
          .bindings
          .add(binding);
    }
    final groups = byKey.values.toList()
      ..sort((a, b) {
        final byType = a.entityType.index.compareTo(b.entityType.index);
        return byType != 0 ? byType : a.entityId.compareTo(b.entityId);
      });
    return groups;
  }

  bool _matches(RuntimeEntityType type) => switch (category) {
        TrackedStateCategory.all => true,
        TrackedStateCategory.character => type == RuntimeEntityType.character,
        TrackedStateCategory.npc => type == RuntimeEntityType.npc,
        TrackedStateCategory.world => type == RuntimeEntityType.world,
      };

  Widget _entityBlock(
    BuildContext context,
    AppLocalizations? l10n,
    _EntityGroup group,
    Map<String, Object?>? overlay,
  ) {
    final theme = Theme.of(context);
    final name = entityNames[group.entityId]?.trim();
    final displayName = (name != null && name.isNotEmpty)
        ? name
        : _typeLabel(group.entityType, l10n);
    final values = overlay ?? const {};
    final bindings = compact ? group.bindings.take(3).toList() : group.bindings;
    // Project through the shared presentation layer so this panel, the session
    // HUD and the Inspector can never disagree about a value.
    final summaries = <TrackedStateSummary>[
      for (final binding in bindings)
        TrackedStateSummary(
          definition: binding.definition,
          value: TrackedStatePresentation.rawValue(binding.definition, values),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                displayName,
                style: theme.textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _typeLabel(group.entityType, l10n),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TrackedStateSummaryList(summaries: summaries),
      ],
    );
  }

  String _typeLabel(RuntimeEntityType type, AppLocalizations? l10n) =>
      switch (type) {
        RuntimeEntityType.character =>
          l10n?.trackedStateEntityTypeCharacter ?? 'Characters',
        RuntimeEntityType.npc => l10n?.trackedStateEntityTypeNpc ?? 'NPCs',
        RuntimeEntityType.world => l10n?.trackedStateEntityTypeWorld ?? 'World',
        _ => '',
      };
}

class _EntityGroup {
  final RuntimeEntityType entityType;
  final String entityId;
  final List<AdventureTrackedStateDefinition> bindings = [];

  _EntityGroup(this.entityType, this.entityId);

  String get key => '${entityType.name}:$entityId';
}
