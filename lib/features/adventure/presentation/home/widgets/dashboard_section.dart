import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';

/// Vertical rhythm for the Adventure Dashboard.
///
/// Two deliberate scales: macro spacing separates major groups, micro spacing
/// separates subsections and rows. Keeping them distinct is what stops the page
/// flattening back into `title / divider / content / AppSpacing.lg` repeats.
class DashboardMetrics {
  DashboardMetrics._();

  /// Between one major group and the next.
  static const double groupGap = 28;

  /// Major group title -> its content.
  static const double groupTitleGap = 12;

  /// Between sibling subsections inside a major group.
  static const double subsectionGap = 20;

  /// Subsection title -> its content.
  static const double subsectionTitleGap = 12;

  /// Between sibling rows inside a subsection.
  static const double rowGap = 8;
}

/// A major dashboard region.
///
/// Hierarchy comes from the type scale (one step above [DashboardSubsection])
/// and from macro spacing — never from a card, a coloured block or a full-width
/// divider under every title. Major groups are separated by the caller using
/// [DashboardMetrics.groupGap].
class DashboardGroup extends StatelessWidget {
  const DashboardGroup({
    super.key,
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;

  /// Optional quiet contextual action rendered beside the title.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(fontSize: 16),
            ),
            if (action case final action?) action,
          ],
        ),
        const SizedBox(height: DashboardMetrics.groupTitleGap),
        child,
      ],
    );
  }
}

/// A subsection inside a major group (e.g. "世界设定" under "你的资料").
///
/// One type step below [DashboardGroup], with a single quiet divider and micro
/// spacing — the divider policy is: major groups use spacing, subsections may
/// use one quiet divider, list rows use separators only between true siblings.
class DashboardSubsection extends StatelessWidget {
  const DashboardSubsection({
    super.key,
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            if (action case final action?) action,
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Divider(height: 1, color: scheme.outlineVariant),
        const SizedBox(height: DashboardMetrics.subsectionTitleGap),
        child,
      ],
    );
  }
}
