import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/feedback/app_feedback.dart';
import '../../../../../core/theme/app_dimensions.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_card.dart';
import '../../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../../providers/riverpod_providers.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// 最近未尽冒险记录流 (继续故事优先)
class DashboardRecentSaves extends ConsumerWidget {
  final VoidCallback? onOpenWizard;

  const DashboardRecentSaves({
    super.key,
    this.onOpenWizard,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chat = ref.watch(chatProvider);
    final adventures = chat.adventureList;

    if (adventures.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 420;

          if (isNarrow) {
            return AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Icon(
                          Icons.auto_stories_outlined,
                          size: 16,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          l10n.dashboardNoAdventuresTitle,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l10n.dashboardNoAdventuresDesc,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (onOpenWizard != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonal(
                        onPressed: onOpenWizard,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text(
                          l10n.dashboardWizardCardAction,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }

          return AppCard(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md,
              horizontal: AppSpacing.md,
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(
                    Icons.auto_stories_outlined,
                    size: 17,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.dashboardNoAdventuresTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.dashboardNoAdventuresDesc,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (onOpenWizard != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.tonal(
                    onPressed: onOpenWizard,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(
                      l10n.dashboardWizardCardAction,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.history_edu_rounded,
              size: 18,
              color: scheme.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                l10n.dashboardContinueAdventures,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '${adventures.length}',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 640;
            final columns = isDesktop ? 2 : 1;
            final cardWidth =
                (constraints.maxWidth - AppSpacing.md * (columns - 1)) /
                    columns;

            return Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              children: List.generate(adventures.length, (index) {
                final item = adventures[index];
                final id = item['id'] as int?;
                final title =
                    item['title']?.toString() ?? l10n.dashboardUnnamedAdventure;
                final updatedAt = item['updated_at']?.toString() ?? '';

                return SizedBox(
                  width: cardWidth,
                  child: AppCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    onTap: () {
                      if (id != null) chat.openAdventure(id);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.08),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Icon(
                                Icons.bookmark_outline_rounded,
                                size: 15,
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (updatedAt.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      l10n.dashboardSavedAt(updatedAt),
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Tooltip(
                              message: l10n.dashboardDeleteAdventureTooltip,
                              child: IconButton(
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 16,
                                  color: scheme.error.withValues(alpha: 0.75),
                                ),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: AppDimensions.controlHeightSm,
                                  minHeight: AppDimensions.controlHeightSm,
                                ),
                                onPressed: () =>
                                    _confirmDelete(context, chat, id, title),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Text(
                              l10n.dashboardContinueExploring,
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: scheme.primary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(
                              Icons.play_arrow_rounded,
                              size: 14,
                              color: scheme.primary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    dynamic chat,
    int? id,
    String title,
  ) async {
    if (id == null) return;
    final l10n = _l10n(context);
    final confirmed = await AppConfirmDialog.show(
      context: context,
      title: l10n.dashboardDeleteAdventureTitle,
      message: l10n.dashboardDeleteAdventureMessage(title),
      confirmLabel: l10n.deleteAction,
      isDanger: true,
      icon: Icons.delete_outline_rounded,
    );

    if (confirmed && context.mounted) {
      await chat.deleteAdventure(id);
      if (context.mounted) {
        AppFeedback.success(context, l10n.dashboardAdventureDeleted(title));
      }
    }
  }
}
