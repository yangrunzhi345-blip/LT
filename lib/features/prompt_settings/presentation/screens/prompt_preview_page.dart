import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/app_page_scaffold.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../utils/token_estimator.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

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
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final text = preview.map((m) {
      return '[${m['role']}]\n${m['content']}\n';
    }).join('\n---\n\n');

    final estimator = TokenEstimator(text);
    final totalTokens = estimator.tokens;

    return AppPageScaffold(
      title: l10n.promptPreviewTitle,
      actions: [
        IconButton(
          icon: const Icon(Icons.copy_rounded),
          tooltip: l10n.copyFullPrompt,
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.fullPromptCopied)),
              );
            }
          },
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.promptPreviewStats(text.length, totalTokens),
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
