import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';

/// 角色 RPG 实时状态栏 (HUD Bar)
/// 极简沉浸式场景与状态微条，支持点击进入 RuntimeStateHubPage 查看完整状态
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
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();

    final gameState = adventure.gameState;
    final hp = gameState.hp;
    final maxHp = gameState.maxHp;
    final mp = gameState.mp;
    final maxMp = gameState.maxMp;
    final gold = gameState.gold;

    final sceneState = adventure.sceneState;
    final rawLocation = gameState.currentScene.isNotEmpty
        ? gameState.currentScene
        : (adventure.currentTitle.isNotEmpty
            ? adventure.currentTitle
            : (sceneState.location.isNotEmpty
                ? sceneState.location
                : l10n.unknownRegion));
    final sceneTime = sceneState.time.trim();
    final location =
        sceneTime.isNotEmpty ? '$rawLocation · $sceneTime' : rawLocation;

    return Material(
      color: colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.25),
              ),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stats = Wrap(
                spacing: AppSpacing.sm + 2,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // 生命值 (HP)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.favorite_rounded,
                        size: 14,
                        color: colorScheme.error,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$hp/$maxHp',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),

                  // 魔法/精神力 (MP)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bolt_rounded,
                        size: 14,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$mp/$maxMp',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),

                  // 金币 (Gold)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.monetization_on_rounded,
                        size: 14,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$gold',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ],
              );

              // 当前所处地点徽章
              final locationBadge = Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.place_rounded,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        location,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (onTap != null) ...[
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 14,
                        color:
                            colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ],
                  ],
                ),
              );

              final textScale = MediaQuery.textScalerOf(context).scale(1.0);
              final isVeryConstrained =
                  constraints.maxWidth < 460 || textScale > 1.25;

              if (isVeryConstrained) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    locationBadge,
                    const SizedBox(height: 3),
                    stats,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: locationBadge,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  stats,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
