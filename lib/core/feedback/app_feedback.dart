import 'package:flutter/material.dart';

/// 非阻塞用户反馈的统一入口。
///
/// 相同文案在短时间内只显示一次，避免保存、刷新等高频操作堆叠通知。
enum AppFeedbackType { success, error, warning, info }

class AppFeedback {
  AppFeedback._();

  static String? _lastKey;
  static DateTime? _lastShownAt;
  static const _dedupeWindow = Duration(seconds: 2);

  static void success(BuildContext context, String message,
          {String? actionLabel, VoidCallback? onAction}) =>
      show(context, message,
          type: AppFeedbackType.success,
          actionLabel: actionLabel,
          onAction: onAction);

  static void error(BuildContext context, String message,
          {String? actionLabel, VoidCallback? onAction}) =>
      show(context, message,
          type: AppFeedbackType.error,
          actionLabel: actionLabel,
          onAction: onAction);

  static void warning(BuildContext context, String message,
          {String? actionLabel, VoidCallback? onAction}) =>
      show(context, message,
          type: AppFeedbackType.warning,
          actionLabel: actionLabel,
          onAction: onAction);

  static void info(BuildContext context, String message,
          {String? actionLabel, VoidCallback? onAction}) =>
      show(context, message,
          type: AppFeedbackType.info,
          actionLabel: actionLabel,
          onAction: onAction);

  static void show(
    BuildContext context,
    String message, {
    AppFeedbackType type = AppFeedbackType.info,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final now = DateTime.now();
    final key = '${type.name}:$message';
    if (_lastKey == key &&
        _lastShownAt != null &&
        now.difference(_lastShownAt!) < _dedupeWindow) {
      return;
    }
    _lastKey = key;
    _lastShownAt = now;

    final scheme = Theme.of(context).colorScheme;
    final spec = switch (type) {
      AppFeedbackType.success => (
          icon: Icons.check_circle_outline_rounded,
          color: scheme.primary,
          label: '成功'
        ),
      AppFeedbackType.error => (
          icon: Icons.error_outline_rounded,
          color: scheme.error,
          label: '错误'
        ),
      AppFeedbackType.warning => (
          icon: Icons.warning_amber_rounded,
          color: scheme.tertiary,
          label: '提醒'
        ),
      AppFeedbackType.info => (
          icon: Icons.info_outline_rounded,
          color: scheme.secondary,
          label: '提示'
        ),
    };

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: spec.color,
        content: Semantics(
          liveRegion: true,
          label: '${spec.label}：$message',
          child: Row(
            children: [
              Icon(spec.icon, color: scheme.onPrimary, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
        ),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(label: actionLabel, onPressed: onAction)
            : null,
      ),
    );
  }
}
