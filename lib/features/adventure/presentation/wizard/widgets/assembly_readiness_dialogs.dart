import 'package:flutter/material.dart';

import '../../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../../l10n/generated/app_localizations.dart';

/// Phase 10 readiness 反馈对话框。
///
/// - [showAssemblyReadinessBlockDialog]：准备中 / 准备失败 / 尚无可用版本时，
///   用可理解的中文说明阻止启动原因。
/// - [showStaleAssemblyChoiceDialog]：存在旧 ready revision 且资源已修改时，
///   让用户**明确选择**是否使用上一个已就绪版本，绝不静默降级。

/// 阻断类反馈（准备中 / 失败 / 尚无可用版本）。
Future<void> showAssemblyReadinessBlockDialog(
  BuildContext context,
  List<String> messages,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(AppLocalizations.of(context)!.readinessBlockedTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final message in messages)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(message),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(AppLocalizations.of(context)!.acknowledgeAction),
        ),
      ],
    ),
  );
}

/// 旧版本明确选择：返回 true 表示用户选择「使用上一个已就绪版本」。
Future<bool> showStaleAssemblyChoiceDialog(
  BuildContext context,
  List<String> messages,
) async {
  return AppConfirmDialog.show(
    context: context,
    title: AppLocalizations.of(context)!.staleResourceTitle,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(AppLocalizations.of(context)!.staleResourceMessage),
        ),
        for (final message in messages)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(message),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(AppLocalizations.of(context)!.usePreviousReady),
        ),
      ],
    ),
    confirmLabel: AppLocalizations.of(context)!.usePreviousReady,
    icon: Icons.history_rounded,
  );
}
