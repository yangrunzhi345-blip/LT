import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/feedback/app_feedback.dart';
import '../../../../../core/localization/dialogue_level_localization.dart';
import '../../../../../core/widgets/app_select.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../../models/dialogue_level.dart';
import '../../../../../providers/riverpod_providers.dart';

/// Open once, then choose a length; no navigation or secondary expansion.
///
/// This is a value select, so it uses the shared [AppSelect] toolbar
/// presentation. The word range lives on each item's subtitle so the trigger
/// label does not drift in width as the value changes.
class ReplyLengthControl extends ConsumerWidget {
  const ReplyLengthControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(
        chatProvider.select((chat) => chat.settingsProvider.dialogueLevel));
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    return AppSelect<DialogueLevel>.toolbar(
      key: const Key('session-reply-length'),
      value: current,
      label: l10n.workbenchLength,
      tooltip: l10n.replyLengthSetting,
      semanticLabel:
          '${l10n.workbenchLength}: ${localizedDialogueLevelLabel(current, l10n)}',
      items: [
        for (final level in DialogueLevel.values)
          AppSelectItem(
            value: level,
            label: localizedDialogueLevelLabel(level, l10n),
            subtitle: localizedDialogueLevelWordRange(level, l10n),
          ),
      ],
      onChanged: (level) async {
        if (level == null) return;
        try {
          await ref.read(chatProvider).settingsProvider.setDialogueLevel(level);
        } catch (_) {
          if (context.mounted) AppFeedback.error(context, l10n.chatSaveFailed);
        }
      },
    );
  }
}
