import 'package:flutter/material.dart';
import '../../l10n/generated/app_localizations.dart';

/// 全局统一确认对话框 [AppConfirmDialog]
///
/// 遵循 R02 弹窗收敛规范：
/// - 业务流程弹窗全面 Page 化，仅保留轻量危险确认/放弃保存弹窗
/// - 统一全仓删除确认、覆盖确认、放弃编辑等确认入口
/// - 深度适配 Material 3 设计系统、暗色/亮色模式以及小屏响应式约束
class AppConfirmDialog extends StatelessWidget {
  final String title;
  final String? message;
  final Widget? content;
  final String? confirmLabel;
  final String? cancelLabel;
  final bool isDanger;
  final IconData? icon;

  const AppConfirmDialog({
    super.key,
    required this.title,
    this.message,
    this.content,
    this.confirmLabel,
    this.cancelLabel,
    this.isDanger = false,
    this.icon,
  }) : assert(message != null || content != null,
            'Either message or content must be provided to AppConfirmDialog');

  /// 唤起确认对话框的静态便捷方法
  ///
  /// 返回 `true` 表示用户确认操作，返回 `false` 表示用户取消或点击外部关闭
  static Future<bool> show({
    required BuildContext context,
    required String title,
    String? message,
    Widget? content,
    String? confirmLabel,
    String? cancelLabel,
    bool isDanger = false,
    IconData? icon,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppConfirmDialog(
        title: title,
        message: message,
        content: content,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        isDanger: isDanger,
        icon: icon,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final Widget titleWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 22,
            color: isDanger ? colorScheme.error : colorScheme.primary,
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );

    final Widget effectiveContent = content ??
        Text(
          message!,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        );

    final l10n = AppLocalizations.of(context);
    final effectiveCancel = cancelLabel ?? l10n?.cancelAction ?? '取消';
    final effectiveConfirm = confirmLabel ?? l10n?.confirmAction ?? '确定';

    return AlertDialog(
      title: titleWidget,
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: effectiveContent,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(effectiveCancel),
        ),
        FilledButton(
          style: isDanger
              ? FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(effectiveConfirm),
        ),
      ],
    );
  }
}
