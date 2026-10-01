import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'app_empty_state.dart';

export 'app_empty_state.dart';

/// 全局统一空状态组件 [AppEmptyView]
///
/// 复用 [AppEmptyState] 的视觉规范（小 SVG + 标题 + 说明 + 可选操作），
/// 额外支持自定义操作组件与内边距。
class AppEmptyView extends StatelessWidget {
  final String icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? actionWidget;
  final double iconSize;
  final EdgeInsetsGeometry? padding;

  const AppEmptyView({
    super.key,
    this.icon = 'inbox',
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.actionWidget,
    this.iconSize = 28,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: AppEmptyState(
              icon: icon,
              title: title,
              description: description,
              iconSize: iconSize,
              actionLabel: actionWidget == null ? actionLabel : null,
              onAction: actionWidget == null ? onAction : null,
            ),
          ),
          if (actionWidget != null) ...[
            const SizedBox(height: AppSpacing.sm),
            actionWidget!,
          ],
        ],
      ),
    );
  }
}
