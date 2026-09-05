import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../utils/token_estimator.dart';

/// 完整组装 Prompt 实时预览模态
class PromptPreviewModal extends StatelessWidget {
  final List<Map<String, String>> preview;

  const PromptPreviewModal({
    super.key,
    required this.preview,
  });

  static void show(BuildContext context, List<Map<String, String>> preview) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PromptPreviewModal(preview: preview),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final text = preview.map((m) {
      return '[${m['role']}]\n${m['content']}\n';
    }).join('\n---\n\n');

    final estimator = TokenEstimator(text);
    final totalTokens = estimator.tokens;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.preview_rounded, color: colorScheme.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  '实时 Prompt 装配预览',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  tooltip: '复制完整 Prompt',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制完整装配 Prompt 到剪贴板')),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            Text(
              '共约 ${text.length} 字符 · 预估 $totalTokens tokens',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildTokenBars(context, preview),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: ListView(
                  controller: scrollController,
                  children: [
                    SelectableText(
                      text,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTokenBars(
      BuildContext context, List<Map<String, String>> preview) {
    final theme = Theme.of(context);
    final estimator = TokenEstimator('');
    final parts = estimator.analyzePrompt(preview);
    final total = parts['总计'] ?? 1;
    final colors = [
      AppColors.accent,
      const Color(0xFF4ECDC4),
      const Color(0xFFF0C040),
      const Color(0xFFFF6B6B),
      const Color(0xFF9B51E0),
    ];

    final items = parts.entries.where((e) => e.key != '总计').toList();
    items.sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(items.length, (i) {
          final entry = items[i];
          final percent = (entry.value / total * 100).toStringAsFixed(1);
          final color = colors[i % colors.length];
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      entry.key,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${entry.value}t ($percent%)',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: entry.value / total,
                    minHeight: 4,
                    backgroundColor: color.withValues(alpha: 0.15),
                    color: color,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
