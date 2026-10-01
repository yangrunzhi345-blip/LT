import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/feedback/app_feedback.dart';
import '../../../../../core/localization/dialogue_level_localization.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../../models/dialogue_level.dart';
import '../../../../../providers/riverpod_providers.dart';

/// Open once, then choose a length; no navigation or secondary expansion.
class ReplyLengthControl extends ConsumerWidget {
  const ReplyLengthControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(
        chatProvider.select((chat) => chat.settingsProvider.dialogueLevel));
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    return PopupMenuButton<DialogueLevel>(
      key: const Key('session-reply-length'),
      tooltip: l10n.replyLengthSetting,
      initialValue: current,
      onSelected: (level) async {
        try {
          await ref.read(chatProvider).settingsProvider.setDialogueLevel(level);
        } catch (_) {
          if (context.mounted) AppFeedback.error(context, l10n.chatSaveFailed);
        }
      },
      itemBuilder: (context) => [
        for (final level in DialogueLevel.values)
          PopupMenuItem(
              value: level,
              child: Text(
                  '${localizedDialogueLevelLabel(level, l10n)} · ${localizedDialogueLevelWordRange(level, l10n)}')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Text(
            '${l10n.workbenchLength}: ${localizedDialogueLevelLabel(current, l10n)}'),
      ),
    );
  }
}
