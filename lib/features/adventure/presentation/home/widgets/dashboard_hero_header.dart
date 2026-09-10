import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../widgets/app_dialogs.dart';

/// 冒险工坊顶部氛围横幅与状态指示器
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
    final modelName = chat.modelName.isNotEmpty
        ? chat.modelName
        : chat.providerType.defaultModel;

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl, vertical: AppSpacing.lg + 4),
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
          final isWide = constraints.maxWidth >= 720;
          return Row(
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
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      scheme.primary,
                      scheme.tertiary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.28),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '灵境 · 探索与叙事工坊',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '自主意识 AI 互动叙事与无限传奇世界演变引擎',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isWide) ...[
                const SizedBox(width: AppSpacing.md),
                InkWell(
                  onTap: onOpenSettings ?? () => showApiSettings(context),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                        color: isConfigured
                            ? scheme.primary.withValues(alpha: 0.3)
                            : scheme.error.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isConfigured
                                ? Colors.green
                                : Colors.amber.shade700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isConfigured
                              ? '${chat.providerType.displayName} · $modelName'
                              : '未配置 API 密钥',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color:
                                isConfigured ? scheme.onSurface : scheme.error,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.tune_rounded,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.tonalIcon(
                  onPressed: onOpenSettings ?? () => showApiSettings(context),
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: const Text('系统设置'),
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ] else ...[
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: '系统设置',
                  onPressed: onOpenSettings ?? () => showApiSettings(context),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
