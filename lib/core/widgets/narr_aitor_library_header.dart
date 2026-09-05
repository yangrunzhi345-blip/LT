import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 资料库页面共用头部。
/// 各资料库只注入自己的操作按钮、说明、搜索框和标签，保持功能差异，统一视觉结构。
class NarrAItorLibraryHeader extends StatelessWidget {
  const NarrAItorLibraryHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.onBackPressed,
    this.onMenuPressed,
    this.leadingAction,
    this.actions = const [],
    this.onSwitchMode,
    this.secondary,
    this.search,
    this.tabs,
  });

  final String title;
  final String? eyebrow;
  final VoidCallback? onBackPressed;
  final VoidCallback? onMenuPressed;
  final Widget? leadingAction;
  final List<Widget> actions;
  final VoidCallback? onSwitchMode;
  final Widget? secondary;
  final Widget? search;
  final PreferredSizeWidget? tabs;

  /// 顶部工具行的实际布局高度。带图标和文字的 TabBar 会自行报告 72px，
  /// 调用方应使用此方法计算 AppBar 约束，避免写死高度导致溢出。
  static const double toolbarHeight = 60;

  static Size preferredSizeFor({PreferredSizeWidget? tabs}) => Size.fromHeight(
        toolbarHeight + (tabs?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final dark = Theme.of(context).brightness == Brightness.dark;
        final accent = Theme.of(context).colorScheme.primary;
        final softAccent = accent.withValues(alpha: dark ? .18 : .10);
        return Material(
          color: dark ? AppColors.darkSurface : AppColors.surfaceElevated,
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 4 : 12,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      if (onBackPressed != null) ...[
                        if (compact)
                          IconButton(
                            onPressed: onBackPressed,
                            tooltip: '返回大厅',
                            icon: const Icon(Icons.arrow_back_rounded),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: FilledButton.tonalIcon(
                              onPressed: onBackPressed,
                              icon: const Icon(Icons.arrow_back_rounded, size: 16),
                              label: const Text('返回大厅'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                      ] else if (onMenuPressed != null) ...[
                        IconButton(
                          onPressed: onMenuPressed,
                          tooltip: '菜单',
                          icon: const Icon(Icons.menu_rounded),
                        ),
                      ],
                      if (leadingAction != null) leadingAction!,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (eyebrow != null)
                              Text(
                                eyebrow!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: accent,
                                  fontSize: compact ? 10 : 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.6,
                                ),
                              ),
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                      ),
                      ...actions,
                      if (onSwitchMode != null)
                        TextButton.icon(
                          onPressed: onSwitchMode,
                          icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                          label: Text(compact ? '' : '切换资料库'),
                          style: TextButton.styleFrom(
                            foregroundColor: accent,
                            backgroundColor: softAccent,
                            minimumSize: Size(compact ? 40 : 0, 36),
                            padding: EdgeInsets.symmetric(
                              horizontal: compact ? 8 : 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (secondary != null) secondary!,
                if (search != null) search!,
                if (tabs != null) tabs!,
              ],
            ),
          ),
        );
      },
    );
  }
}

typedef LTLibraryHeader = NarrAItorLibraryHeader;
typedef AppLibraryHeader = NarrAItorLibraryHeader;
