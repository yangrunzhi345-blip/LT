import 'package:flutter/material.dart';

import '../../../../application/adventure/adventure_tracked_state_registry.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../models/adventure_config.dart';
import '../../../../models/adventure_runtime_state.dart';
import '../../../../models/adventure_tracked_state.dart';
import '../../../../models/tracked_state_definition.dart';

/// Read-only overview of every entity's monitored fields, driven by the single
/// [AdventureTrackedStateRegistry].
///
/// This is the runtime counterpart of the definition editor: characters, NPCs
/// and the world all render through one path, and a monitor with no runtime
/// value shows as "not triggered" instead of a fabricated zero.
class TrackedStateOverviewPanel extends StatelessWidget {
  final AdventureConfig? config;
  final List<RuntimeEntityState> entities;
  final Map<String, String> entityNames;
  final VoidCallback? onManage;

  const TrackedStateOverviewPanel({
    super.key,
    required this.config,
    required this.entities,
    this.entityNames = const {},
    this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final registry = AdventureTrackedStateRegistry.fromConfig(config);

    if (registry.isEmpty) {
      return Text(
        l10n?.trackedStateNoDefinitions ?? 'No monitored fields',
        style: theme.textTheme.bodySmall,
      );
    }

    final groups = <String, _EntityGroup>{};
    for (final binding in registry.all) {
      final key = '${binding.entityType.name}:${binding.entityId}';
      groups
          .putIfAbsent(key, () => _EntityGroup(binding.entityId))
          .bindings
          .add(binding);
    }

    final overlayByEntity = <String, Map<String, Object?>>{
      for (final entity in entities)
        '${entity.entityType.name}:${entity.entityId}': entity.overlay,
    };

    final keys = groups.keys.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final key in keys) ...[
          _entityBlock(context, l10n, groups[key]!, overlayByEntity[key]),
          const SizedBox(height: 12),
        ],
        if (onManage != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onManage,
              child: Text(l10n?.trackedStateManageTitle ?? 'Monitored fields'),
            ),
          ),
      ],
    );
  }

  Widget _entityBlock(
    BuildContext context,
    AppLocalizations? l10n,
    _EntityGroup group,
    Map<String, Object?>? overlay,
  ) {
    final theme = Theme.of(context);
    final name = entityNames[group.entityId] ?? group.entityId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final binding in group.bindings)
          _monitorRow(context, l10n, binding.definition, overlay ?? const {}),
      ],
    );
  }

  Widget _monitorRow(
    BuildContext context,
    AppLocalizations? l10n,
    TrackedStateDefinition definition,
    Map<String, Object?> overlay,
  ) {
    final theme = Theme.of(context);
    final path = RuntimeStateChangeProposal.customAttributePath(
      definition.effectiveId,
    );
    final value = overlay[path];
    final triggered = value != null;
    final display = !triggered
        ? (l10n?.trackedStateUntriggered ?? 'Not triggered')
        : value.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
              child: Text(definition.name, style: theme.textTheme.bodyMedium)),
          Text(
            display,
            style: theme.textTheme.bodySmall?.copyWith(
              color: triggered
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _EntityGroup {
  final String entityId;
  final List<AdventureTrackedStateDefinition> bindings = [];

  _EntityGroup(this.entityId);
}
