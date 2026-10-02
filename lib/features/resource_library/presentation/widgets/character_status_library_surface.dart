import 'package:flutter/material.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/custom_attribute_importance_visuals.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_error_view.dart';
import '../../../../core/widgets/app_loading_view.dart';
import '../../../../core/widgets/app_svg_icon.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../models/tracked_state_definition.dart';
import '../../../../models/typed_runtime_state.dart';
import '../../domain/models/character_status_library_view_state.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// Read-only「角色状态」surface for the Resource Library.
///
/// Shows, per owner resource (character / NPC), the monitoring **definitions**
/// it declares. Definitions only — it never renders an adventure's current
/// value, because a resource does not store one.
final class CharacterStatusLibrarySurface extends StatelessWidget {
  const CharacterStatusLibrarySurface({
    super.key,
    required this.state,
    required this.onOpenOwner,
    required this.onEditOwner,
    required this.onAddStatus,
    required this.onRetry,
    required this.onPreviousPage,
    required this.onNextPage,
  });

  final CharacterStatusLibraryViewState state;
  final ValueChanged<CharacterStatusLibraryEntry> onOpenOwner;
  final ValueChanged<CharacterStatusLibraryEntry> onEditOwner;
  final VoidCallback onAddStatus;
  final VoidCallback onRetry;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    switch (state.status) {
      case CharacterStatusLibraryStatus.loading:
        return const AppLoadingView();
      case CharacterStatusLibraryStatus.error:
        return AppErrorView(
          title: l10n.resourceLoadFailedRetry,
          retryLabel: l10n.resourceRetryLoad,
          onRetry: onRetry,
        );
      case CharacterStatusLibraryStatus.ready:
        break;
    }

    final entries = state.pagedEntries;
    if (entries.isEmpty) {
      final noMatch = state.query.trim().isNotEmpty ||
          state.ownerFilter != CharacterStatusOwnerFilter.all;
      if (noMatch) {
        return AppEmptyState(icon: 'search', title: l10n.resourceNoMatches);
      }
      return AppEmptyState(
        icon: 'state',
        title: l10n.resourceCharacterStatusEmptyTitle,
        description: l10n.resourceCharacterStatusEmptyDescription,
        actionLabel: l10n.resourceCharacterStatusAdd,
        onAction: onAddStatus,
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const Key('character-status-list'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              for (final entry in entries)
                _OwnerGroup(
                  entry: entry,
                  onOpen: () => onOpenOwner(entry),
                  onEdit: () => onEditOwner(entry),
                ),
            ],
          ),
        ),
        if (state.totalPages > 1) _pagination(context, l10n),
      ],
    );
  }

  Widget _pagination(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            key: const Key('character-status-page-prev'),
            tooltip: l10n.resourcePaginationPrev,
            icon: const AppSvgIcon('back'),
            onPressed: state.currentPage > 1 ? onPreviousPage : null,
          ),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                l10n.resourcePaginationPageInfo(
                  state.currentPage,
                  state.totalPages,
                  state.totalOwners,
                ),
                key: const Key('character-status-page-info'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
          IconButton(
            key: const Key('character-status-page-next'),
            tooltip: l10n.resourcePaginationNext,
            icon: const AppSvgIcon('forward'),
            onPressed: state.currentPage < state.totalPages ? onNextPage : null,
          ),
        ],
      ),
    );
  }
}

final class _OwnerGroup extends StatelessWidget {
  const _OwnerGroup({
    required this.entry,
    required this.onOpen,
    required this.onEdit,
  });

  final CharacterStatusLibraryEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = _l10n(context);
    final ownerName = entry.ownerName.trim().isEmpty
        ? l10n.resourceUnnamed
        : entry.ownerName.trim();
    final typeLabel = switch (entry.ownerType) {
      ResourceType.character => l10n.trackedStateEntityTypeCharacter,
      ResourceType.npc => l10n.trackedStateEntityTypeNpc,
      ResourceType.worldview => l10n.resourceTypeWorldview,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: InkWell(
                key: ValueKey('character-status-owner-${entry.resourceId}'),
                onTap: onOpen,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ownerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$typeLabel · '
                        '${l10n.resourceCharacterStatusCount(entry.definitions.length)}',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              key: ValueKey('character-status-edit-${entry.resourceId}'),
              onPressed: onEdit,
              child: Text(l10n.resourceCharacterStatusEditOwner),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final definition in entry.definitions)
          _DefinitionRow(definition: definition),
        const SizedBox(height: AppSpacing.sm),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

final class _DefinitionRow extends StatelessWidget {
  const _DefinitionRow({required this.definition});

  final TrackedStateDefinition definition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = _l10n(context);
    final metadata = <String>[
      _kindLabel(definition.valueKind, l10n),
      if (_rangeLabel(definition) case final range?) range,
      definition.importance.localizedLabel(l10n),
    ];
    final rule = definition.description.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            definition.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            metadata.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (rule.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              rule,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  String _kindLabel(RuntimeStateValueKind kind, AppLocalizations l10n) =>
      switch (kind) {
        RuntimeStateValueKind.number => l10n.trackedStateKindNumber,
        RuntimeStateValueKind.integer => l10n.trackedStateKindInteger,
        RuntimeStateValueKind.text => l10n.trackedStateKindText,
        RuntimeStateValueKind.boolean => l10n.trackedStateKindBoolean,
        RuntimeStateValueKind.enumValue => l10n.trackedStateKindEnum,
      };

  String? _rangeLabel(TrackedStateDefinition definition) {
    if (!definition.isNumeric) return null;
    final minimum = definition.minimum;
    final maximum = definition.maximum;
    if (minimum == null && maximum == null) return null;
    return '${_num(minimum) ?? '-∞'}–${_num(maximum) ?? '∞'}';
  }

  static String? _num(num? value) {
    if (value == null) return null;
    return value == value.truncate()
        ? value.truncate().toString()
        : value.toString();
  }
}
