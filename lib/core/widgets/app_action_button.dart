import 'package:flutter/material.dart';

import '../../widgets/narr_aitor_loading.dart';
export 'app_buttons.dart';

enum _AppActionButtonVariant { primary, secondary, danger, text }

class AppActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool enabled;
  final bool fullWidth;
  final _AppActionButtonVariant _variant;

  const AppActionButton.primary({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    this.enabled = true,
    this.fullWidth = false,
  }) : _variant = _AppActionButtonVariant.primary;

  const AppActionButton.secondary({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    this.enabled = true,
    this.fullWidth = false,
  }) : _variant = _AppActionButtonVariant.secondary;

  const AppActionButton.danger({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    this.enabled = true,
    this.fullWidth = false,
  }) : _variant = _AppActionButtonVariant.danger;

  const AppActionButton.text({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    this.enabled = true,
    this.fullWidth = false,
  }) : _variant = _AppActionButtonVariant.text;

  const AppActionButton.quiet({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    this.enabled = true,
    this.fullWidth = false,
  }) : _variant = _AppActionButtonVariant.text;

  @override
  Widget build(BuildContext context) {
    final callback = enabled && !isLoading ? onPressed : null;
    final buttonIcon = isLoading
        ? const SizedBox(
            width: 16,
            height: 16,
            child: NarrAItorLoading.mini(size: 16),
          )
        : icon == null
            ? null
            : Icon(icon, size: 18);
    final child = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    final Widget button = switch (_variant) {
      _AppActionButtonVariant.secondary => buttonIcon == null
          ? OutlinedButton(onPressed: callback, child: child)
          : OutlinedButton.icon(
              onPressed: callback,
              icon: buttonIcon,
              label: child,
            ),
      _AppActionButtonVariant.danger => buttonIcon == null
          ? FilledButton(
              onPressed: callback,
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: child,
            )
          : FilledButton.icon(
              onPressed: callback,
              icon: buttonIcon,
              label: child,
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
      _AppActionButtonVariant.text => buttonIcon == null
          ? TextButton(onPressed: callback, child: child)
          : TextButton.icon(
              onPressed: callback,
              icon: buttonIcon,
              label: child,
            ),
      _AppActionButtonVariant.primary => buttonIcon == null
          ? FilledButton(onPressed: callback, child: child)
          : FilledButton.icon(
              onPressed: callback,
              icon: buttonIcon,
              label: child,
            ),
    };

    if (!fullWidth) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}

/// 自带并发守卫的 [AppActionButton] 包装，用于一次性保存、删除和创建操作。
class AppAsyncActionButton extends StatefulWidget {
  const AppAsyncActionButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.fullWidth = false,
  }) : _variant = _AppActionButtonVariant.primary;

  const AppAsyncActionButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.fullWidth = false,
  }) : _variant = _AppActionButtonVariant.secondary;

  const AppAsyncActionButton.danger({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.fullWidth = false,
  }) : _variant = _AppActionButtonVariant.danger;

  const AppAsyncActionButton.text({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.fullWidth = false,
  }) : _variant = _AppActionButtonVariant.text;

  const AppAsyncActionButton.quiet({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.fullWidth = false,
  }) : _variant = _AppActionButtonVariant.text;

  final String label;
  final IconData? icon;
  final Future<void> Function() onPressed;
  final bool fullWidth;
  final _AppActionButtonVariant _variant;

  @override
  State<AppAsyncActionButton> createState() => _AppAsyncActionButtonState();
}

class _AppAsyncActionButtonState extends State<AppAsyncActionButton> {
  bool _loading = false;

  Future<void> _run() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget._variant) {
      _AppActionButtonVariant.primary => AppActionButton.primary(
          label: widget.label,
          icon: widget.icon,
          isLoading: _loading,
          onPressed: _run,
          fullWidth: widget.fullWidth),
      _AppActionButtonVariant.secondary => AppActionButton.secondary(
          label: widget.label,
          icon: widget.icon,
          isLoading: _loading,
          onPressed: _run,
          fullWidth: widget.fullWidth),
      _AppActionButtonVariant.danger => AppActionButton.danger(
          label: widget.label,
          icon: widget.icon,
          isLoading: _loading,
          onPressed: _run,
          fullWidth: widget.fullWidth),
      _AppActionButtonVariant.text => AppActionButton.text(
          label: widget.label,
          icon: widget.icon,
          isLoading: _loading,
          onPressed: _run,
          fullWidth: widget.fullWidth),
    };
  }
}

/// 响应式动作操作栏 [AppResponsiveActionBar]
///
/// 遵循 AGENTS.md 响应式与 320px 适配规范：
/// - 宽屏 (桌面/平板或宽度充裕) 下：横向排列 (Row/Wrap)，右对齐或两端对齐
/// - 窄屏 (宽度 < 360 或空间受限) 下：自动换行 (Wrap) 或转为竖向列 (Column)，
///   彻底杜绝 320px 逻辑视口下的横向 RenderFlex Overflow。
class AppResponsiveActionBar extends StatelessWidget {
  final List<Widget> children;
  final WrapAlignment alignment;
  final double spacing;
  final double runSpacing;
  final bool forceColumnOnCompact;

  const AppResponsiveActionBar({
    super.key,
    required this.children,
    this.alignment = WrapAlignment.end,
    this.spacing = 8.0,
    this.runSpacing = 8.0,
    this.forceColumnOnCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 360.0 ||
            (forceColumnOnCompact && constraints.maxWidth < 600.0);

        if (isNarrow && forceColumnOnCompact) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: runSpacing),
                children[i],
              ],
            ],
          );
        }

        return Wrap(
          alignment: alignment,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: spacing,
          runSpacing: runSpacing,
          children: children,
        );
      },
    );
  }
}
