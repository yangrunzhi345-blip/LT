import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/app_page_scaffold.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../utils/token_estimator.dart';

/// Complete assembled prompt preview page.
class PromptPreviewPage extends StatelessWidget {
  final List<Map<String, String>> preview;

  const PromptPreviewPage({
    super.key,
    required this.preview,
  });

  static void show(BuildContext context, List<Map<String, String>> preview) {
    AppRouter.push<void>(
      context,
      pageBuilder: (_) => PromptPreviewPage(preview: preview),
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

    return AppPageScaffold(
      title: '实时 Prompt 装配预览',
      actions: [
        IconButton(
          icon: const Icon(Icons.copy_rounded),
          tooltip: '复制完整 Prompt',
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制完整装配 Prompt 到剪贴板')),
              );
            }
          },
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '共约 ${text.length} 字符 · 预估 $totalTokens tokens',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildTokenBars(context, preview),
          const SizedBox(height: AppSpacing.md),
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
