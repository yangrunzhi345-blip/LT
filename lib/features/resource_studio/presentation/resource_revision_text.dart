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
) {
  final label = item.label.trim();
  if (label.isEmpty) return resourceRevisionCauseLabel(item.cause, l10n);

  // Older revisions persist presentation labels. Translate only known labels
  // emitted by LT itself; arbitrary labels may have been supplied by users.
  return switch (label) {
    '恢复前' => l10n.revisionBeforeRestore,
    '压缩前' => l10n.revisionBeforeCompression,
    '删除前快照' => resourceRevisionCauseLabel(RevisionCause.deletion, l10n),
    '保存后快照' => resourceRevisionCauseLabel(RevisionCause.manualSave, l10n),
    '大纲确认' => resourceRevisionCauseLabel(RevisionCause.planning, l10n),
    'assembly' => l10n.revisionAssembly,
    '恢复到原位置' => l10n.resourceTrashRestoreOriginal,
    '原所属章节已不存在，已恢复到资源根下的新章节' => l10n.resourceTrashRestoreFallback,
    '已恢复到资源库' => l10n.resourceTrashRestoreToLibrary,
    '该条目已恢复，本次未改变任何内容' => l10n.resourceTrashAlreadyRestored,
    _ => _localizedGeneratedRevisionLabel(label, l10n) ?? label,
  };
}

String? _localizedGeneratedRevisionLabel(
  String label,
  AppLocalizations l10n,
) {
  const restorePrefix = '恢复到 ';
  if (label.startsWith(restorePrefix)) {
    final causeLabel = label.substring(restorePrefix.length);
    for (final cause in RevisionCause.values) {
      if (cause.displayLabel == causeLabel) {
        return l10n.revisionRestored(resourceRevisionCauseLabel(cause, l10n));
      }
    }
  }

  final compressionMatch = RegExp(r'^语义压缩（节省 (\d+) 字）$').firstMatch(label);
  if (compressionMatch case final match?) {
    return l10n.revisionCompressionSaved(int.parse(match[1]!));
  }

  if (label.endsWith(' 前快照')) {
    final mode = label.substring(0, label.length - ' 前快照'.length);
    final localizedMode = switch (mode) {
      'regenerate' => l10n.revisionModeRegenerate,
      'rewrite' => l10n.revisionModeRewrite,
      'expand' => l10n.revisionModeExpand,
      'condense' => l10n.revisionModeCondense,
      _ => null,
    };
    if (localizedMode != null) {
      return l10n.revisionBeforeRegeneration(localizedMode);
    }
  }

  return null;
}

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
