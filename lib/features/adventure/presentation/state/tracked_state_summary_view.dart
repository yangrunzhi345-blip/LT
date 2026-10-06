import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../../models/adventure_config.dart';
import '../../../../models/adventure_runtime_state.dart';
import '../../../../models/typed_runtime_state.dart';
import 'tracked_state_presentation.dart';

/// Read-only list of monitored-field rows for one entity.
///
/// Rendered rows and value formatting come from the shared
/// [TrackedStatePresentation] projection, so the runtime hub, the overview
/// panel and the session Inspector can never show a different value for the
/// same definition. A definition with no runtime value renders as an
/// untriggered row — never a fabricated zero and never a missing line.
class TrackedStateSummaryList extends StatelessWidget {
  const TrackedStateSummaryList({
    super.key,
    required this.summaries,
    this.dense = false,
  });

  final List<TrackedStateSummary> summaries;

  /// Tighter vertical rhythm for the compact session surfaces.
  final bool dense;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final summary in summaries)
            Padding(
              padding: EdgeInsets.symmetric(vertical: dense ? 1 : 2),
              child: TrackedStateSummaryRow(summary: summary),
            ),
        ],
      );
}

/// One monitored-field row: definition name on the left, formatted value on the
/// right. Long names and long text values ellipsize instead of overflowing.
class TrackedStateSummaryRow extends StatelessWidget {
  const TrackedStateSummaryRow({super.key, required this.summary});

  final TrackedStateSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            summary.name,
            style: theme.textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        _value(context, summary),
      ],
    );
  }

  Widget _value(BuildContext context, TrackedStateSummary summary) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final definition = summary.definition;
    final value = summary.value;

    if (value == null) {
      return Text(
        TrackedStatePresentation.untriggeredText(l10n),
        style: muted,
      );
    }

    if (definition.valueKind == RuntimeStateValueKind.boolean) {
      return Text(
        TrackedStatePresentation.boolText(
          value == true || value.toString() == 'true',
          l10n,
        ),
        style: theme.textTheme.bodyMedium,
      );
    }

    if (definition.isNumeric && value is num) {
      final max = definition.maximum;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            TrackedStatePresentation.formatNumber(value),
            style: theme.textTheme.bodyMedium,
          ),
          if (max != null)
            Text(
              ' / ${TrackedStatePresentation.formatNumber(max)}',
              style: muted,
            ),
        ],
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200),
      child: Text(
        value.toString(),
        style: theme.textTheme.bodyMedium,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
      ),
    );
  }
}

/// Entity-scoped summary: resolves one entity's monitored fields from the
/// frozen registry + runtime overlays and renders them under its display name.
///
/// Used by the session Inspector so its state block reads the exact same
/// projection as the runtime hub, rather than maintaining a second mapping.
/// Returns an empty box when the entity has no monitored fields.
class TrackedStateEntitySummary extends StatelessWidget {
  const TrackedStateEntitySummary({
    super.key,
    required this.config,
    required this.entities,
    required this.entityType,
    required this.entityId,
    required this.displayName,
    this.limit,
    this.showTypeLabel = false,
    this.dense = false,
  });

  final AdventureConfig? config;
  final Iterable<RuntimeEntityState> entities;
  final RuntimeEntityType entityType;
  final String entityId;
  final String displayName;
  final int? limit;
  final bool showTypeLabel;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final summaries = TrackedStatePresentation.summaries(
      config: config,
      entities: entities,
      entityType: entityType,
      entityId: entityId,
      limit: limit,
    );
    if (summaries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                displayName,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (showTypeLabel) ...[
              const SizedBox(width: 8),
              Text(
                _typeLabel(entityType, l10n),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        TrackedStateSummaryList(summaries: summaries, dense: dense),
      ],
    );
  }

  static String _typeLabel(RuntimeEntityType type, AppLocalizations? l10n) =>
      switch (type) {
        RuntimeEntityType.character =>
          l10n?.trackedStateEntityTypeCharacter ?? 'Characters',
        RuntimeEntityType.npc => l10n?.trackedStateEntityTypeNpc ?? 'NPCs',
        RuntimeEntityType.world => l10n?.trackedStateEntityTypeWorld ?? 'World',
        _ => '',
      };
}
