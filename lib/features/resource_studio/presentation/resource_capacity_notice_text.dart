import '../../../l10n/generated/app_localizations.dart';
import '../domain/models/resource_capacity_view_state.dart';

String resourceCapacityNoticeText(
  ResourceCapacityNotice notice,
  AppLocalizations l10n,
) =>
    switch (notice.type) {
      ResourceCapacityNoticeType.noCompressionNeeded =>
        l10n.capacityNoCompressionNeeded,
      ResourceCapacityNoticeType.compressionAlreadyPublished =>
        l10n.capacityCompressionAlreadyPublished,
      ResourceCapacityNoticeType.compressionPublished =>
        l10n.capacityCompressionPublished(notice.savedCharacters),
      ResourceCapacityNoticeType.retryBlockedByActiveTarget =>
        l10n.capacityRetryBlockedByActiveTarget(
          notice.skippedActiveTargets,
        ),
      ResourceCapacityNoticeType.retryBudgetExhausted =>
        l10n.capacityRetryBudgetExhausted(notice.skippedExhaustedJobs),
      ResourceCapacityNoticeType.retryUnavailable =>
        l10n.capacityRetryUnavailable,
      ResourceCapacityNoticeType.compressionRunSummary =>
        l10n.capacityCompressionRunSummary(
          notice.succeededJobs,
          notice.failedJobs,
          notice.requeuedJobs,
          notice.skippedActiveTargets,
          notice.skippedExhaustedJobs,
        ),
    };
