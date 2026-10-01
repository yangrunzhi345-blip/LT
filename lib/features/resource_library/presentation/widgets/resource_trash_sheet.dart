import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../core/localization/app_date_formats.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_svg_icon.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/app_page_scaffold.dart';
import '../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../domain/resources/resource_trash.dart';
import '../../application/use_cases/resource_trash_runtime.dart';
import '../../domain/models/resource_trash_view_state.dart';
import '../controllers/resource_trash_controller.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../core/localization/app_error_localizer.dart';

/// Locale-aware compact timestamp; never the raw persisted value.
String _formatTrashDate(DateTime? value, AppLocalizations l10n) {
  if (value == null) return l10n.revisionUnknownDate;
  return AppDateFormats.compactTimestamp(value, l10n.localeName);
}

String _trashItemSubtitle(ResourceTrashItem item, AppLocalizations l10n) {
  final kind = switch (item.nodeKind) {
    RevisionNodeKindRef.resource => l10n.resourceTrashKindResource,
    RevisionNodeKindRef.section => l10n.resourceTrashKindSection,
    RevisionNodeKindRef.part => l10n.resourceTrashKindPart,
  };
  final reason = switch (item.reason) {
    TrashReason.userDelete => l10n.resourceTrashReasonUserDelete,
  };
  return l10n.resourceTrashSubtitle(
    kind,
    reason,
    _formatTrashDate(item.deletedAt, l10n),
    _formatTrashDate(item.expiresAt, l10n),
  );
}

String _trashNoticeText(ResourceTrashNotice notice, AppLocalizations l10n) {
  if (notice.kind == ResourceTrashNoticeKind.permanentlyDeleted) {
    return l10n.resourceTrashPermanentDeleteSuccess;
  }
  return switch (notice.placement) {
    TrashRestorePlacement.original => l10n.resourceTrashRestoreOriginal,
    TrashRestorePlacement.recreatedSectionUnderRoot =>
      l10n.resourceTrashRestoreFallback,
    TrashRestorePlacement.restoredToLibrary =>
      l10n.resourceTrashRestoreToLibrary,
    TrashRestorePlacement.alreadyRestored => l10n.resourceTrashAlreadyRestored,
    null => l10n.operationFailedRetry,
  };
}

String _trashErrorText(ResourceTrashViewState state, AppLocalizations l10n) {
  final error = state.error == null
      ? state.errorMessage
      : localizeAppError(l10n, state.error!);
  return switch (state.errorKind) {
    ResourceTrashErrorKind.load => l10n.resourceTrashLoadFailed(error),
    ResourceTrashErrorKind.restore => l10n.resourceTrashRestoreFailed(error),
    ResourceTrashErrorKind.permanentDelete =>
      l10n.resourceTrashPermanentDeleteFailed(error),
    null => error,
  };
}

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// Recycle-bin view: list, restore, permanent delete.
///
/// Layout rules (AGENTS.md): every row is a `Column` of dynamic text with a
/// `Wrap` of actions underneath, never a `ListTile` with a long title beside a
/// trailing button group. The sheet is height-bounded and scrollable, so it
/// stays usable at 320 px, on a short landscape viewport and with a large text
/// scale.
final class ResourceTrashView extends StatelessWidget {
  const ResourceTrashView({
    required this.state,
    required this.onRefresh,
    required this.onRestore,
    required this.onPermanentDelete,
    this.showHeader = true,
    super.key,
  });

  final ResourceTrashViewState state;
  final VoidCallback onRefresh;
  final void Function(String trashId) onRestore;

  /// Called only after the view itself has confirmed with the user.
  final void Function(String trashId) onPermanentDelete;

  /// When the view is hosted by a page that already renders the title and a
  /// refresh action, the view's own toolbar is suppressed (no duplicate title).
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = _l10n(context);
    return SafeArea(
      child: ConstrainedBox(
        // Never taller than the viewport: a long bin scrolls instead of
        // pushing the sheet off screen on a short device.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: IconButton(
                    onPressed: state.isLoading ? null : onRefresh,
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: const AppSvgIcon('refresh', size: 18),
                    tooltip: l10n.refreshRecycleBin,
                  ),
                ),
              ),
            if (state.notice != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  _trashNoticeText(state.notice!, l10n),
                  softWrap: true,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (state.errorMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  _trashErrorText(state, l10n),
                  softWrap: true,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            Flexible(child: _buildBody(context)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = _l10n(context);
    if (state.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.isEmpty) {
      return AppEmptyState(
        icon: 'delete',
        title: l10n.emptyRecycleBin,
        description: l10n.resourceTrashEmptyDescription,
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: state.items.length,
      itemBuilder: (context, index) => _buildRow(context, state.items[index]),
    );
  }

  Widget _buildRow(BuildContext context, ResourceTrashItem item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = _l10n(context);
    final busy = state.busyTrashId == item.trashId;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 4, 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            style: theme.textTheme.titleSmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            _trashItemSubtitle(item, l10n),
            softWrap: true,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              TextButton.icon(
                onPressed: busy || state.isLoading
                    ? null
                    : () => onRestore(item.trashId),
                icon: const AppSvgIcon('undo', size: 15),
                label: Text(l10n.restoreAction),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                ),
              ),
              TextButton.icon(
                onPressed: busy || state.isLoading
                    ? null
                    : () => _confirmPermanentDelete(context, item),
                icon: const AppSvgIcon('delete', size: 15),
                label: Text(l10n.permanentlyDelete),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                  foregroundColor: scheme.error,
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Permanent delete is a second, explicit confirmation: it is the only path
  /// in the app that physically destroys resource content.
  Future<void> _confirmPermanentDelete(
    BuildContext context,
    ResourceTrashItem item,
  ) async {
    final l10n = _l10n(context);
    final confirmed = await AppConfirmDialog.show(
      context: context,
      title: l10n.permanentlyDelete,
      message: l10n.permanentDeleteMessage(item.title),
      confirmLabel: l10n.permanentlyDelete,
      isDanger: true,
    );
    if (confirmed) onPermanentDelete(item.trashId);
  }
}

/// Stateful page host of [ResourceTrashView].
final class ResourceTrashPage extends StatefulWidget {
  const ResourceTrashPage({required this.runtime, super.key});

  final ResourceTrashRuntime runtime;

  /// Opens the recycle bin as a navigation page.
  static Future<void> show(
    BuildContext context,
    ResourceTrashRuntime runtime,
  ) {
    return AppRouter.push<void>(
      context,
      pageBuilder: (_) => ResourceTrashPage(runtime: runtime),
    );
  }

  @override
  State<ResourceTrashPage> createState() => _ResourceTrashPageState();
}

class _ResourceTrashPageState extends State<ResourceTrashPage> {
  late final ResourceTrashController _controller =
      ResourceTrashController(runtime: widget.runtime);

  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    return AppPageScaffold(
      title: l10n.recycleBinTitle,
      // The page header owns the title and the refresh action, so the embedded
      // view does not repeat either (no duplicated "Recycle Bin" heading).
      actions: [
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => IconButton(
            tooltip: l10n.refreshRecycleBin,
            onPressed: _controller.state.isLoading
                ? null
                : () => unawaited(_controller.refresh()),
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            icon: const AppSvgIcon('refresh', size: 18),
          ),
        ),
      ],
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => ResourceTrashView(
          showHeader: false,
          state: _controller.state,
          onRefresh: () => unawaited(_controller.refresh()),
          onRestore: (trashId) => unawaited(_controller.restore(trashId)),
          onPermanentDelete: (trashId) =>
              unawaited(_controller.permanentDelete(trashId)),
        ),
      ),
    );
  }
}
