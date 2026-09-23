import 'package:flutter/material.dart';

import '../../../../core/widgets/app_read_aloud.dart';
import '../../../../domain/read_aloud/read_aloud_contracts.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// Displays one Part body and its current generation status.
final class ResourceStudioPartCard extends StatelessWidget {
  const ResourceStudioPartCard({
    required this.part,
    required this.content,
    required this.isActive,
    required this.isValidating,
    required this.hasError,
    required this.onRetry,
    super.key,
  });

  final ResourcePart part;
  final String content;
  final bool isActive;
  final bool isValidating;
  final bool hasError;
  final VoidCallback? onRetry;

  /// 单个 Part 的朗读会话/段落 id。
  ///
  /// 与整份资源的连续朗读共用同一段级 id，因此朗读推进时可以映射回本卡片。
  static String readAloudIdFor(ResourcePart part) =>
      'studio-part:${part.id.value}';

  String get readAloudSourceId => readAloudIdFor(part);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = _l10n(context);
    final hasBody = content.trim().isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    part.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                // 只朗读用户实际能看到的正文；生成中/空正文不提供入口。
                if (hasBody && !isActive)
                  AppReadAloudButton(
                    sourceId: readAloudSourceId,
                    sourceType: ReadAloudSourceType.studioPart,
                    text: content,
                    label: part.title,
                    tooltip: l10n.readAloudStart,
                  ),
                if (isActive || isValidating)
                  const Padding(
                    padding: EdgeInsets.only(left: 12, top: 4),
                    child: SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (isActive)
              Text(
                content.isEmpty ? l10n.generationWaiting : content,
                style: theme.textTheme.bodyLarge,
              )
            else
              SelectableText(
                content.isEmpty ? l10n.generationWaiting : content,
                style: theme.textTheme.bodyLarge,
              ),
            if (hasBody) ...[
              const SizedBox(height: 4),
              AppReadAloudControls(sourceId: readAloudSourceId),
            ],
            if (hasError) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.retryAction),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
