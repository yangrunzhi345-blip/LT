import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../state/tracked_state_presentation.dart';
import '../../state/tracked_state_summary_view.dart';

/// Compact scene and current-state summary; the full state has a named entry.
///
/// Besides location / HP / MP / gold it carries a very small summary of the
/// **currently selected character's** monitored fields, so a user can tell —
/// without leaving the conversation — whether tracking is configured, which
/// fields exist, which have not triggered yet and which already carry a value.
/// It stays flat and quiet; it is a summary, not a dashboard.
class StatusHudBar extends ConsumerWidget {
  const StatusHudBar({super.key, this.onTap, this.onTrackedTap});

  /// Scene / vitals tap. Keeps the existing "open the workbench state" entry.
  final VoidCallback? onTap;

  /// Opens the monitored-fields view for the current character. When null the
  /// summary is inert and [onTap] owns the whole bar.
  final VoidCallback? onTrackedTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final chat = ref.watch(chatProvider);
    final adventure = chat.adventureProvider;
    final state = adventure.gameState;
    final scene = adventure.sceneState;
    final config = adventure.adventureConfig;
    final location = scene.location.isNotEmpty
        ? scene.location
        : state.currentScene.isNotEmpty
            ? state.currentScene
            : adventure.currentTitle.isNotEmpty
                ? adventure.currentTitle
                : l10n.unknownRegion;

    final selected = TrackedStatePresentation.resolveSelectedCharacter(
      config: config,
      selectedCharacterIndex: chat.selectedCharacterIndex,
    );
    final summaries = TrackedStatePresentation.summaries(
      config: config,
      entities: adventure.runtimeEntities,
      entityType: selected.entityType,
      entityId: selected.entityId,
    );
    final hasDefinitions = TrackedStatePresentation.hasAnyDefinition(config);

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
            const SizedBox(height: AppSpacing.xs),
            _TrackedSummary(
              l10n: l10n,
              character: selected,
              summaries: summaries,
              hasDefinitions: hasDefinitions,
              onTap: onTrackedTap,
            ),
          ]),
        ),
      ),
    );
  }
}

/// The compact monitored-fields strip.
class _TrackedSummary extends StatelessWidget {
  const _TrackedSummary({
    required this.l10n,
    required this.character,
    required this.summaries,
    required this.hasDefinitions,
    required this.onTap,
  });

  final AppLocalizations l10n;
  final TrackedStateEntityRef character;
  final List<TrackedStateSummary> summaries;
  final bool hasDefinitions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(builder: (context, constraints) {
      // Phones keep one quiet line; wide workbenches get a short block.
      final narrow = constraints.maxWidth < 520;
      if (summaries.isEmpty) {
        // Distinguish "this adventure configures nothing" from "this character
        // has nothing" — both are explicit, neither is a blank bar.
        final copy = hasDefinitions
            ? '${character.name} · ${l10n.trackedStateNoDefinitions}'
            : '${l10n.trackedStateStatusTitle} · ${l10n.trackedStateNoDefinitions}';
        return Text(
          copy,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        );
      }
      return narrow ? _narrow(context, constraints.maxWidth) : _wide(context);
    });

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: content,
      ),
    );
  }

  /// One wrapped line: `角色 · 字段 值 · 字段 尚未触发`.
  ///
  /// Each item is individually width-bounded, so long names or long values
  /// ellipsize inside their own item instead of overflowing the bar; at least
  /// the leading character name and first field stay visible at 320 px.
  Widget _narrow(BuildContext context, double maxWidth) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Text(
            character.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium,
          ),
        ),
        for (final summary in summaries.take(2))
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Text(
              '· ${summary.name} '
              '${TrackedStatePresentation.valueText(summary.definition, summary.value, l10n)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  /// Name on its own line, then up to three aligned field / value rows.
  Widget _wide(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          character.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 2),
        TrackedStateSummaryList(
          summaries: summaries.take(3).toList(),
          dense: true,
        ),
      ],
    );
  }
}
