import 'package:flutter/material.dart';

import '../../widgets/narr_aitor_loading.dart';

enum _AppActionButtonVariant { primary, secondary, danger }

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
    final child = Text(label);

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
    };
  }
}
