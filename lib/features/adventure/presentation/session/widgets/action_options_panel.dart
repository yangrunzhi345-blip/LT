import 'package:flutter/material.dart';
import '../../../../../core/theme/app_spacing.dart';

/// 剧情推演行动选项面板
/// 自适应流式排布，将行动指令清晰呈现
class ActionOptionsPanel extends StatelessWidget {
  final List<String> options;
  final ValueChanged<String> onOptionSelected;
  final bool disabled;

  const ActionOptionsPanel({
    super.key,
    required this.options,
    required this.onOptionSelected,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.alt_route_rounded,
                  size: 14, color: colorScheme.primary),
              const SizedBox(width: 4),
              Text(
                '可选行动分支',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs + 2),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((opt) {
              return ActionChip(
                avatar: const Icon(Icons.arrow_forward_ios_rounded, size: 12),
                label: Text(
                  opt,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                backgroundColor: colorScheme.surfaceContainerLow,
                side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                onPressed: disabled ? null : () => onOptionSelected(opt),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
