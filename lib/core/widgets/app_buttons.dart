import 'package:flutter/material.dart';

/// 全局统一按钮尺寸规范
enum AppButtonSize {
  small(
    height: 32,
    iconSize: 16,
    fontSize: 12,
    horizontalPadding: 10,
    verticalPadding: 6,
  ),
  medium(
    height: 40,
    iconSize: 18,
    fontSize: 14,
    horizontalPadding: 16,
    verticalPadding: 8,
  ),
  large(
    height: 48,
    iconSize: 20,
    fontSize: 16,
    horizontalPadding: 20,
    verticalPadding: 12,
  );

  final double height;
  final double iconSize;
  final double fontSize;
  final double horizontalPadding;
  final double verticalPadding;

  const AppButtonSize({
    required this.height,
    required this.iconSize,
    required this.fontSize,
    required this.horizontalPadding,
    required this.verticalPadding,
  });

  EdgeInsetsGeometry get padding => EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      );
}

/// 统一主操作按钮 [AppPrimaryButton]
class AppPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? iconWidget;
  final bool isLoading;
  final bool enabled;
  final bool fullWidth;
  final AppButtonSize size;

  const AppPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.iconWidget,
    this.isLoading = false,
    this.enabled = true,
    this.fullWidth = false,
    this.size = AppButtonSize.medium,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isInteractive = enabled && !isLoading;
    final callback = isInteractive ? onPressed : null;

    final Widget? effectiveIcon = isLoading
        ? SizedBox(
            width: size.iconSize,
            height: size.iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.onPrimary,
              ),
            ),
          )
        : (iconWidget ??
            (icon != null ? Icon(icon, size: size.iconSize) : null));

    final child = Text(
      label,
      style: TextStyle(fontSize: size.fontSize),
    );

    final style = FilledButton.styleFrom(
      padding: size.padding,
      minimumSize: Size(fullWidth ? double.infinity : 0, size.height),
    );

    final Widget button = effectiveIcon == null
        ? FilledButton(
            onPressed: callback,
            style: style,
            child: child,
          )
        : FilledButton.icon(
            onPressed: callback,
            style: style,
            icon: effectiveIcon,
            label: child,
          );

    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}

/// 统一次级/描边按钮 [AppSecondaryButton]
class AppSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? iconWidget;
  final bool isLoading;
  final bool enabled;
  final bool fullWidth;
  final AppButtonSize size;

  const AppSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.iconWidget,
    this.isLoading = false,
    this.enabled = true,
    this.fullWidth = false,
    this.size = AppButtonSize.medium,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isInteractive = enabled && !isLoading;
    final callback = isInteractive ? onPressed : null;

    final Widget? effectiveIcon = isLoading
        ? SizedBox(
            width: size.iconSize,
            height: size.iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          )
        : (iconWidget ??
            (icon != null ? Icon(icon, size: size.iconSize) : null));

    final child = Text(
      label,
      style: TextStyle(fontSize: size.fontSize),
    );

    final style = OutlinedButton.styleFrom(
      padding: size.padding,
      minimumSize: Size(fullWidth ? double.infinity : 0, size.height),
    );

    final Widget button = effectiveIcon == null
        ? OutlinedButton(
            onPressed: callback,
            style: style,
            child: child,
          )
        : OutlinedButton.icon(
            onPressed: callback,
            style: style,
            icon: effectiveIcon,
            label: child,
          );

    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}

/// 统一危险/破坏性操作按钮 [AppDangerButton]
class AppDangerButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? iconWidget;
  final bool isLoading;
  final bool enabled;
  final bool fullWidth;
  final AppButtonSize size;
  final bool outlined;

  const AppDangerButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.iconWidget,
    this.isLoading = false,
    this.enabled = true,
    this.fullWidth = false,
    this.size = AppButtonSize.medium,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isInteractive = enabled && !isLoading;
    final callback = isInteractive ? onPressed : null;

    final Widget? effectiveIcon = isLoading
        ? SizedBox(
            width: size.iconSize,
            height: size.iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                outlined ? colorScheme.error : colorScheme.onError,
              ),
            ),
          )
        : (iconWidget ??
            (icon != null ? Icon(icon, size: size.iconSize) : null));

    final child = Text(
      label,
      style: TextStyle(fontSize: size.fontSize),
    );

    if (outlined) {
      final style = OutlinedButton.styleFrom(
        foregroundColor: colorScheme.error,
        side: BorderSide(color: colorScheme.error),
        padding: size.padding,
        minimumSize: Size(fullWidth ? double.infinity : 0, size.height),
      );

      final Widget button = effectiveIcon == null
          ? OutlinedButton(
              onPressed: callback,
              style: style,
              child: child,
            )
          : OutlinedButton.icon(
              onPressed: callback,
              style: style,
              icon: effectiveIcon,
              label: child,
            );

      if (fullWidth) {
        return SizedBox(width: double.infinity, child: button);
      }
      return button;
    }

    final style = FilledButton.styleFrom(
      backgroundColor: colorScheme.error,
      foregroundColor: colorScheme.onError,
      padding: size.padding,
      minimumSize: Size(fullWidth ? double.infinity : 0, size.height),
    );

    final Widget button = effectiveIcon == null
        ? FilledButton(
            onPressed: callback,
            style: style,
            child: child,
          )
        : FilledButton.icon(
            onPressed: callback,
            style: style,
            icon: effectiveIcon,
            label: child,
          );

    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}

/// 统一文本/幽灵按钮 [AppTextButton] (quiet / text 操作)
class AppTextButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? iconWidget;
  final bool isLoading;
  final bool enabled;
  final bool fullWidth;
  final AppButtonSize size;

  const AppTextButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.iconWidget,
    this.isLoading = false,
    this.enabled = true,
    this.fullWidth = false,
    this.size = AppButtonSize.medium,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isInteractive = enabled && !isLoading;
    final callback = isInteractive ? onPressed : null;

    final Widget? effectiveIcon = isLoading
        ? SizedBox(
            width: size.iconSize,
            height: size.iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          )
        : (iconWidget ??
            (icon != null ? Icon(icon, size: size.iconSize) : null));

    final child = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: size.fontSize),
    );

    final style = TextButton.styleFrom(
      padding: size.padding,
      minimumSize: Size(fullWidth ? double.infinity : 0, size.height),
    );

    final Widget button = effectiveIcon == null
        ? TextButton(
            onPressed: callback,
            style: style,
            child: child,
          )
        : TextButton.icon(
            onPressed: callback,
            style: style,
            icon: effectiveIcon,
            label: child,
          );

    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}
