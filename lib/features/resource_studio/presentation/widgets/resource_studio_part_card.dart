import 'package:flutter/material.dart';

import '../../../../domain/resources/resource_contracts.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            SelectableText(
              content.isEmpty ? '等待生成内容…' : content,
              style: theme.textTheme.bodyLarge,
            ),
            if (hasError) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试此内容'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
