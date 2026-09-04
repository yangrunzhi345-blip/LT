import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_action_button.dart';

class ErrorStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String retryLabel;
  final VoidCallback? onRetry;

  const ErrorStateView({
    super.key,
    this.icon = Icons.error_outline_rounded,
    required this.title,
    required this.message,
    this.retryLabel = '重试',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              AppActionButton.secondary(
                label: retryLabel,
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
