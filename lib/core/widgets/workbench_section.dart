import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Content section with a quiet heading and wrapping contextual actions.
///
/// Hierarchy comes from the heading + a 1 px divider + spacing, never from a
/// container or a card.
class WorkbenchSection extends StatelessWidget {
  const WorkbenchSection(
      {super.key, required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              if (action case final action?) action,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      );
}
