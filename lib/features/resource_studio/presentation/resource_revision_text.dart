import '../../../domain/resources/resource_revision.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/models/resource_revision_view_state.dart';
import 'resource_studio_user_message.dart';

String resourceRevisionCauseLabel(
  RevisionCause cause,
  AppLocalizations l10n,
) =>
    switch (cause) {
      RevisionCause.manualSave => l10n.revisionCauseManualSave,
      RevisionCause.generation => l10n.revisionCauseGeneration,
      RevisionCause.planning => l10n.revisionCausePlanning,
      RevisionCause.regeneration => l10n.revisionCauseRegeneration,
      RevisionCause.compression => l10n.revisionCauseCompression,
      RevisionCause.restore => l10n.revisionCauseRestore,
      RevisionCause.migration => l10n.revisionCauseMigration,
      RevisionCause.deletion => l10n.revisionCauseDeletion,
    };

String resourceRevisionTitle(
  ResourceRevisionItem item,
  AppLocalizations l10n,
) =>
    item.label.trim().isNotEmpty
        ? item.label
        : resourceRevisionCauseLabel(item.cause, l10n);

String resourceRevisionSubtitle(
  ResourceRevisionItem item,
  AppLocalizations l10n,
) {
  final date = item.createdAt == null
      ? l10n.revisionUnknownDate
      : _formatRevisionDate(item.createdAt!.toLocal(), l10n.localeName);
  return l10n.revisionItemSubtitle(date, item.nodeCount, item.charCount);
}

String _formatRevisionDate(DateTime value, String localeName) {
  final date = localeName.startsWith('en')
      ? '${value.month}/${value.day}/${value.year}'
      : '${value.year}/${value.month}/${value.day}';
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$date $hour:$minute';
}

String resourceRevisionNoticeText(
  RevisionRestoreNotice notice,
  AppLocalizations l10n,
) =>
    switch (notice.type) {
      RevisionRestoreNoticeType.alreadyAtRevision =>
        l10n.revisionAlreadyCurrent,
      RevisionRestoreNoticeType.restored => l10n.revisionRestored(
          resourceRevisionCauseLabel(
            notice.sourceCause ?? RevisionCause.restore,
            l10n,
          ),
        ),
    };

String resourceRevisionErrorText(String error, AppLocalizations l10n) =>
    l10n.resourceRevisionOperationFailed(
      resourceStudioUserMessage(error, l10n),
    );
