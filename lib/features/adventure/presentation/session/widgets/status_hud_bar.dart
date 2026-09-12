import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../providers/riverpod_providers.dart';

/// 角色 RPG 实时状态栏 (HUD Bar)
/// 独立组件，采用单行极简沉浸式布局，在窄屏下保持紧凑不增加纵向高度
class StatusHudBar extends ConsumerWidget {
  final VoidCallback? onTap;

  const StatusHudBar({
    super.key,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chat = ref.watch(chatProvider);
    final adventure = chat.adventureProvider;

    final gameState = adventure.gameState;
    final hp = gameState.hp;
    final maxHp = gameState.maxHp;
    final mp = gameState.mp;
    final maxMp = gameState.maxMp;
    final gold = gameState.gold;
    final location = gameState.currentScene.isNotEmpty
        ? gameState.currentScene
        : (adventure.currentTitle.isNotEmpty ? adventure.currentTitle : '未知地域');

    return Material(
      color: colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isVeryNarrow = constraints.maxWidth < 360;
              final isNarrow = constraints.maxWidth < 460;

              return Row(
                children: [
                  // 地点标识
                  Icon(
                    Icons.place_outlined,
                    size: 13,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      location,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                        fontSize: 11.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),

                  // 生命值 (HP)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.favorite_rounded,
                        size: 12,
                        color: colorScheme.error,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$hp/$maxHp',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),

                  // 魔法/精神力 (MP)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bolt_rounded,
                        size: 13,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '$mp/$maxMp',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),

                  // 金币 (在非极窄屏下显示)
                  if (!isVeryNarrow) ...[
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.monetization_on_outlined,
                          size: 12,
                          color: Color(0xFFD97706),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '$gold',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],

                  if (onTap != null && !isNarrow) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 14,
                      color:
                          colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
