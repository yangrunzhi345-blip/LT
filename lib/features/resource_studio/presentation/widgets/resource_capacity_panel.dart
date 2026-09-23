import 'package:flutter/material.dart';

import '../../../../domain/resources/resource_contracts.dart';
import '../../domain/models/resource_capacity_view_state.dart';
import '../resource_capacity_notice_text.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// Capacity status for one resource, with a manual compression entry.
///
/// Layout rules (AGENTS.md): the header is a `Row` only because its right side
/// is a short fixed chip and its left side is `Expanded`; every metric group is
/// a `Wrap`; nothing places unbounded dynamic text beside a button. A 320 px
/// viewport therefore never overflows.
final class ResourceCapacityPanel extends StatelessWidget {
  const ResourceCapacityPanel({
    required this.state,
    required this.onRefresh,
    required this.onCompress,
    required this.onRetry,
    required this.onPublish,
    super.key,
  });

  final ResourceCapacityViewState state;
  final VoidCallback onRefresh;
  final VoidCallback onCompress;
  final VoidCallback onRetry;

  /// Publishes the newest validated compression candidate, behind the revision
  /// boundary.
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = _l10n(context);
    final summary = state.summary;

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
                    l10n.capacityPanelTitle,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (summary != null)
                  _StatusChip(status: summary.snapshot.status),
              ],
            ),
            const SizedBox(height: 8),
            if (summary == null)
              _buildPlaceholder(context)
            else
              _buildMeasurements(context, summary),
            if (state.errorMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                state.errorMessage,
                softWrap: true,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            if (state.notice case final notice?) ...[
              const SizedBox(height: 8),
              Text(
                resourceCapacityNoticeText(notice, l10n),
                softWrap: true,
                style: notice.failedJobs > 0
                    ? TextStyle(color: theme.colorScheme.error)
                    : null,
              ),
            ],
            if (summary != null && summary.latestFailureReason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                l10n.capacityLatestFailureReason(summary.latestFailureReason),
                softWrap: true,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      state.isLoading || state.isWorking ? null : onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(l10n.capacityRefresh),
                ),
                FilledButton.icon(
                  onPressed:
                      state.hasCapacity && !state.isWorking ? onCompress : null,
                  icon: state.isWorking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.compress_rounded),
                  label: Text(state.isWorking
                      ? l10n.capacityCompressing
                      : l10n.capacityGenerateCandidates),
                ),
                OutlinedButton.icon(
                  onPressed: summary != null &&
                          summary.hasRetryableFailures &&
                          !state.isWorking
                      ? onRetry
                      : null,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: Text(
                    summary != null && summary.hasRetryableFailures
                        ? l10n.capacityRetryFailedWithCount(
                            summary.retryableFailedJobs)
                        : l10n.capacityRetryFailed,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: summary != null &&
                          summary.hasPublishableCandidates &&
                          !state.isWorking
                      ? onPublish
                      : null,
                  icon: const Icon(Icons.publish_rounded),
                  label: Text(
                    summary != null && summary.hasPublishableCandidates
                        ? l10n.capacityPublishWithCount(
                            summary.publishableCandidateCount)
                        : l10n.capacityPublish,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.capacityOptimizationTip,
              softWrap: true,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    if (state.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }
    return Text(
      _l10n(context).capacityPreparingState,
      softWrap: true,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  Widget _buildMeasurements(
    BuildContext context,
    ResourceCapacitySummary summary,
  ) {
    final l10n = _l10n(context);
    final snapshot = summary.snapshot;
    final metrics = <String>[
      l10n.capacityTextCharacters(snapshot.totalCharacters),
      l10n.capacitySectionsCount(snapshot.sectionCount),
      l10n.capacityPartsCount(snapshot.partCount),
      l10n.capacityRevisionsCount(snapshot.historicalRevisionCount),
      l10n.capacityArchivedSize(snapshot.archiveSize),
      l10n.capacityQueuedJobs(summary.queuedJobs),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: snapshot.fillRatio.clamp(0.0, 1.0),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final metric in metrics) _MetricChip(label: metric),
          ],
        ),
        if (summary.potentialSavedCharacters > 0) ...[
          const SizedBox(height: 8),
          Text(
            l10n.capacityPotentialSavings(summary.potentialSavedCharacters),
            softWrap: true,
          ),
        ],
      ],
    );
  }
}

final class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final CapacityStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      CapacityStatus.normal => (l10n.capacityStatusNormal, scheme.primary),
      CapacityStatus.elastic => (l10n.capacityStatusElastic, scheme.tertiary),
      CapacityStatus.overflow => (l10n.capacityStatusOverflow, scheme.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12),
      ),
    );
  }
}

final class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
