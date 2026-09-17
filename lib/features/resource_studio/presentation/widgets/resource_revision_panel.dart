import 'package:flutter/material.dart';

import '../../domain/models/resource_revision_view_state.dart';

/// Version history of one resource, with a restore action per entry.
///
/// Layout rules (AGENTS.md): the header is a `Row` because its right side is a
/// short fixed button and its left side is `Expanded`; every list row places
/// dynamic text (cause, timestamp, counts) in a `Column` above a `Wrap` of
/// actions, never beside a button in a tight `Row`. The whole panel therefore
/// stays overflow-free down to a 320 px viewport and at large text scales.
final class ResourceRevisionPanel extends StatelessWidget {
  const ResourceRevisionPanel({
    required this.state,
    required this.onRefresh,
    required this.onRestore,
    super.key,
  });

  final ResourceRevisionViewState state;
  final VoidCallback onRefresh;
  final void Function(String revisionId) onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '版本历史',
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: state.isLoading ? null : onRefresh,
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新版本历史',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (state.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (state.hasError)
              Text(
                state.errorMessage,
                softWrap: true,
                style: TextStyle(color: theme.colorScheme.error),
              )
            else if (!state.hasHistory)
              Text(
                '还没有可恢复的历史版本',
                softWrap: true,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ..._buildItems(context),
            if (state.statusMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(state.statusMessage, softWrap: true),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildItems(BuildContext context) {
    final theme = Theme.of(context);
    return [
      for (final item in state.items)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: theme.textTheme.bodyLarge,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (item.isHead)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Chip(
                            label: Text('当前'),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    softWrap: true,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // The action is wrapped so a narrow viewport or a large text
                  // scale moves it to its own line instead of overflowing.
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed:
                          state.canRestore && !item.isHead && !state.isLoading
                              ? () => onRestore(item.revisionId)
                              : null,
                      icon: const Icon(Icons.history),
                      label: const Text('恢复到此版本'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ];
  }
}
