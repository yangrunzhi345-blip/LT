import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../widgets/app_dialogs.dart';

/// 冒险工坊顶部氛围横幅与状态指示器
/// 遵循 Editorial 版式风格，消除夸张发光渐变与 AI 营销口号，保持安静克制的文学质感
class DashboardHeroHeader extends ConsumerWidget {
  final VoidCallback? onMenuPressed;
  final VoidCallback? onOpenSettings;

  const DashboardHeroHeader({
    super.key,
    this.onMenuPressed,
    this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chat = ref.watch(chatProvider);
    final isConfigured = chat.isKeyConfigured;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 400;
          final isWide = constraints.maxWidth >= 720;
          final horizontalPad = isNarrow ? AppSpacing.md : AppSpacing.xl;

          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPad,
              vertical: AppSpacing.md + 2,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (onMenuPressed != null) ...[
                  IconButton(
                    icon: const Icon(Icons.menu_rounded),
                    tooltip: '切换导航栏',
                    onPressed: onMenuPressed,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Icon(
                    Icons.auto_stories_rounded,
                    color: scheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '灵境 · 探索与叙事工坊',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '交互小说与沉浸式 RPG 叙事空间',
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
                const SizedBox(width: AppSpacing.sm),
                if (!isConfigured) ...[
                  InkWell(
                    onTap: onOpenSettings ?? () => showApiSettings(context),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(
                          color: scheme.error.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.vpn_key_outlined,
                            size: 13,
                            color: scheme.error,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '配置密钥',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.error,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else if (isWide) ...[
                  FilledButton.tonalIcon(
                    onPressed: onOpenSettings ?? () => showApiSettings(context),
                    icon: const Icon(Icons.settings_outlined, size: 15),
                    label: const Text('系统设置'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ] else ...[
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    tooltip: '系统设置',
                    visualDensity: VisualDensity.compact,
                    onPressed: onOpenSettings ?? () => showApiSettings(context),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
