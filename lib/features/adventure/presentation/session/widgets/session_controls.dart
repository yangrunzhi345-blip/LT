import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_svg_icon.dart';
import '../../../../../features/prompt_settings/presentation/screens/context_weight_controls.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../../providers/riverpod_providers.dart';
import 'reply_length_control.dart';

/// High-frequency controls have explicit destinations instead of a mixed menu.
class SessionControls extends ConsumerWidget {
  const SessionControls(
      {super.key,
      required this.onContext,
      required this.onCharacters,
      required this.onState,
      required this.onModel,
      this.onMenu});
  final VoidCallback onContext;
  final VoidCallback onCharacters;
  final VoidCallback onState;
  final VoidCallback onModel;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preset = ref.watch(chatProvider
        .select((chat) => chat.settingsProvider.contextWeightProfile.presetId));
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    return Wrap(
      spacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (onMenu != null)
          IconButton(
              tooltip: l10n.historyAndSidebarAction,
              onPressed: onMenu,
              icon: const AppSvgIcon('panel')),
        const ReplyLengthControl(),
        TextButton(
            key: const Key('session-context'),
            onPressed: onContext,
            child: Text(
                '${l10n.workbenchContext}: ${contextPresetLabel(l10n, preset)}')),
        IconButton(
            key: const Key('session-characters'),
            tooltip: l10n.sceneCharactersTitle,
            onPressed: onCharacters,
            icon: const AppSvgIcon('characters')),
        IconButton(
            key: const Key('session-state'),
            tooltip: l10n.runtimeStateCurrent,
            onPressed: onState,
            icon: const AppSvgIcon('state')),
        IconButton(
            key: const Key('session-model'),
            tooltip: l10n.switchModelAction,
            onPressed: onModel,
            icon: const AppSvgIcon('generation')),
      ],
    );
  }
}
