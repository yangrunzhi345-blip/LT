import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../providers/riverpod_providers.dart';

/// 角色 RPG 实时状态栏 (HUD Bar)
/// 独立组件，仅在数值变动时重绘，避免上层对话列表全量 Rebuild
class StatusHudBar extends ConsumerWidget {
  const StatusHudBar({super.key});

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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: [
          // 生命值 (HP)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_rounded, size: 16, color: colorScheme.error),
              const SizedBox(width: 4),
              Text(
                '$hp/$maxHp',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),

          // 魔法/精神力 (MP)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt_rounded, size: 16, color: colorScheme.primary),
              const SizedBox(width: 4),
              Text(
                '$mp/$maxMp',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),

          // 金币 (Gold)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.monetization_on_rounded, size: 16, color: Colors.amber),
              const SizedBox(width: 4),
              Text(
                '$gold',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const Spacer(),

          // 当前所处地点徽章
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.place_rounded, size: 14, color: colorScheme.primary),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    location,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
