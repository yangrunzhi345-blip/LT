import 'package:flutter/material.dart';

import '../../domain/models/resource_revision_view_state.dart';
import '../../../../core/localization/app_error_localizer.dart';
import '../resource_revision_text.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

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
    final l10n = _l10n(context);

    return Card(
      child: ExpansionTile(
        initiallyExpanded: false,
        title: Text(
          l10n.revisionHistoryTitle,
          style: theme.textTheme.titleMedium,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(l10n.revisionCount(state.items.length)),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: state.isLoading ? null : onRefresh,
              icon: const Icon(Icons.refresh),
              tooltip: l10n.refreshRevisionHistory,
              visualDensity: VisualDensity.compact,
            ),
          ),
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
              state.error == null
                  ? resourceRevisionErrorText(state.errorMessage, l10n)
                  : localizeAppError(l10n, state.error!),
              softWrap: true,
              style: TextStyle(color: theme.colorScheme.error),
            )
          else if (!state.hasHistory)
            Text(
              l10n.noRestorableRevisions,
              softWrap: true,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ..._buildItems(context),
          if (state.notice != null) ...[
            const SizedBox(height: 8),
            Text(resourceRevisionNoticeText(state.notice!, l10n),
                softWrap: true),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildItems(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = _l10n(context);
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
                          resourceRevisionTitle(item, l10n),
                          style: theme.textTheme.bodyLarge,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (item.isHead)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Chip(
                            label: Text(l10n.currentRevision),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    resourceRevisionSubtitle(item, l10n),
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
                      label: Text(l10n.restoreRevision),
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
