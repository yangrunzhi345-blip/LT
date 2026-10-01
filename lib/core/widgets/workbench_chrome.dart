import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Compact page header for workspace pages.
///
/// Editorial Workbench: a 20 px title, optional quiet subtitle and right-aligned
/// actions, with an optional toolbar row underneath. No large AppBar, no
/// decorative band.
class WorkbenchPageHeader extends StatelessWidget {
  const WorkbenchPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const <Widget>[],
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(leading == null ? 16 : 4, 12, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge,
                        ),
                        if (subtitle case final subtitle?) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ...actions,
                ],
              ),
            ),
            if (bottom case final bottom?) bottom,
            Divider(height: 1, color: scheme.outlineVariant),
          ],
        ),
      ),
    );
  }
}

/// A single compact control row under a page header.
///
/// Height is a minimum, not a fixed value, so tabs can wrap on narrow widths
/// without clipping.
class WorkbenchToolbar extends StatelessWidget {
  const WorkbenchToolbar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 12, 0),
    this.minHeight = 38,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: child,
        ),
      ),
    );
  }
}

/// A quiet text tab: label + 2 px underline when selected.
///
/// Replaces filled pill/`ChoiceChip` filters where the control is a single
/// choice among a small set.
class WorkbenchTabButton extends StatelessWidget {
  const WorkbenchTabButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: scheme.onSurface.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color:
                        selected ? scheme.onSurface : scheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 2,
                  width: 18,
                  decoration: BoxDecoration(
                    color: selected ? scheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wrapping container for [WorkbenchTabButton]s.
class WorkbenchTabBar extends StatelessWidget {
  const WorkbenchTabBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 4,
        runSpacing: 0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      );
}

/// Label / value row used for state matrices and inspectors.
///
/// Preferred over one-card-per-attribute: hierarchy comes from alignment and
/// typography, not containers.
class WorkbenchPropertyRow extends StatelessWidget {
  const WorkbenchPropertyRow({
    super.key,
    required this.label,
    required this.value,
    this.labelWidth = 104,
    this.valueColor,
    this.trailing,
  });

  final String label;
  final String value;
  final double labelWidth;
  final Color? valueColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(color: valueColor),
            ),
          ),
          if (trailing case final trailing?) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing,
          ],
        ],
      ),
    );
  }
}
