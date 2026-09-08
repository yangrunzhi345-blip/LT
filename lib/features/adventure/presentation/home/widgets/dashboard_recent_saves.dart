import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/feedback/app_feedback.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_action_button.dart';
import '../../../../../core/widgets/app_card.dart';
import '../../../../../providers/riverpod_providers.dart';

/// 最近未尽冒险记录流
class DashboardRecentSaves extends ConsumerWidget {
  const DashboardRecentSaves({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chat = ref.watch(chatProvider);
    final adventures = chat.adventureList;

    if (adventures.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.auto_stories_outlined,
              size: 36,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '尚未开始任何场景冒险',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '选择上方的「向导定制」开启属于你的首部传奇',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.history_edu_rounded,
              size: 20,
              color: scheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
              '继续未尽的冒险',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            )),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '${adventures.length}',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 720 ? 2 : 1;
          final cardWidth =
              (constraints.maxWidth - AppSpacing.md * (columns - 1)) / columns;
          return Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: List.generate(adventures.length, (index) {
              final item = adventures[index];
              final id = item['id'] as int?;
              final title = item['title']?.toString() ?? '未命名冒险';
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
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Tooltip(
                            message: '删除冒险记录',
                            child: IconButton(
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: scheme.error.withValues(alpha: 0.8),
                              ),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              onPressed: () =>
                                  _confirmDelete(context, chat, id, title),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (updatedAt.isNotEmpty)
                        Text(
                          '存档于 $updatedAt',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            '继续探索',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.play_arrow_rounded,
                            size: 16,
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
        }),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除冒险记录'),
        content: Text('确定要删除场景「$title」及其全部对话记录吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          AppActionButton.danger(
            label: '确认删除',
            icon: Icons.delete_outline_rounded,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await chat.deleteAdventure(id);
      if (context.mounted) {
        AppFeedback.success(context, '已删除场景「$title」');
      }
    }
  }
}
