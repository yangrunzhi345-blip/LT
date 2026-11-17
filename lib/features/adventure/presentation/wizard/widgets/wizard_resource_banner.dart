import 'package:flutter/material.dart';

import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_svg_icon.dart';

/// Shared empty / error banner for one wizard asset type.
///
/// Uses a `Row` + `Expanded` text so long error messages wrap instead of
/// overflowing at the 320 px minimum width.
class WizardResourceBanner extends StatelessWidget {
  const WizardResourceBanner({
    super.key,
    required this.icon,
    required this.message,
    required this.isError,
  });

  final String icon;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: isError
            ? scheme.errorContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSvgIcon(
            icon,
            size: 18,
            color: isError ? scheme.error : scheme.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
