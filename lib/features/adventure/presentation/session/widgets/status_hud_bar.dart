import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';

/// Compact session header: scene/location/time and the protagonist's vitals.
///
/// It deliberately owns **only** header information. Monitored / tracked state
/// does not belong here: the per-turn, post-settlement snapshot is rendered
/// inside each assistant message body (narrative → tracked state → options),
/// and the current/latest state lives in the Session Inspector and the Runtime
/// State Hub. Keeping this bar free of tracked state is what stops the header
/// from disagreeing with the historical message snapshots.
class StatusHudBar extends ConsumerWidget {
  const StatusHudBar({super.key, this.onTap});

  /// Scene / vitals tap. Keeps the existing "open the workbench state" entry.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final adventure = ref.watch(chatProvider).adventureProvider;
    final state = adventure.gameState;
    final scene = adventure.sceneState;
    final location = scene.location.isNotEmpty
        ? scene.location
        : state.currentScene.isNotEmpty
            ? state.currentScene
            : adventure.currentTitle.isNotEmpty
                ? adventure.currentTitle
                : l10n.unknownRegion;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(scene.time.isEmpty ? location : '$location · ${scene.time}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
            Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.xs, children: [
              Text('${l10n.runtimeStateFieldHp} ${state.hp}/${state.maxHp}',
                  style: Theme.of(context).textTheme.labelMedium),
              Text('${l10n.runtimeStateFieldMp} ${state.mp}/${state.maxMp}',
                  style: Theme.of(context).textTheme.labelMedium),
              Text('${l10n.workbenchGold} ${state.gold}',
                  style: Theme.of(context).textTheme.labelMedium),
            ]),
          ]),
        ),
      ),
    );
  }
}
