import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/feedback/app_feedback.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../../core/widgets/app_svg_icon.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../../providers/riverpod_providers.dart';
import 'dashboard_section.dart';

/// The user's stories: the most recent one leads as the primary "continue"
/// action, the rest follow as a quiet list.
///
/// Owns no onboarding. When there is nothing to continue it renders nothing;
/// the empty-state invitation belongs to [DashboardStartActions] so the page
/// never shows two competing "start a wizard" entry points.
class DashboardRecentSaves extends ConsumerWidget {
  const DashboardRecentSaves({super.key});

  Future<void> _delete(
      BuildContext context, WidgetRef ref, int id, String title) async {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final confirmed = await AppConfirmDialog.show(
      context: context,
      title: l10n.moveToTrashAction,
      message: l10n.moveToTrashMessage(title),
      confirmLabel: l10n.moveToTrashAction,
      isDanger: true,
    );
    if (confirmed && context.mounted) {
      try {
        await ref.read(chatProvider).moveAdventureToTrash(id);
        if (context.mounted) {
          AppFeedback.success(context, l10n.moveToTrashAction);
        }
      } catch (_) {
        if (context.mounted) AppFeedback.error(context, l10n.moveToTrashFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final chat = ref.watch(chatProvider);
    final adventures = chat.adventureList;
    if (adventures.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashboardGroup(
          key: const Key('dashboard-group-continue'),
          title: l10n.dashboardContinueAdventures,
          child: _PrimaryAdventure(
            child: _AdventureRow(
              item: adventures.first,
              primary: true,
              onOpen: (id) => chat.openAdventure(id),
              onDelete: (id, title) => _delete(context, ref, id, title),
            ),
          ),
        ),
      ],
    );
  }
}

/// Restrained neutral band around the active story — a subtle border and small
/// radius, not a floating card. It is the one region allowed a surface lift so
/// the page reads as a workspace with a focus, not a flat list.
class _PrimaryAdventure extends StatelessWidget {
  const _PrimaryAdventure({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _AdventureRow extends StatelessWidget {
  const _AdventureRow(
      {required this.item,
      required this.onOpen,
      required this.onDelete,
      this.primary = false});
  final Map<String, dynamic> item;
  final ValueChanged<int> onOpen;
  final void Function(int, String) onDelete;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final title = item['title'] as String? ?? l10n.dashboardUnnamedAdventure;
    final id = item['id'] as int?;
    final updated = item['updated_at']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Tooltip(
                  message: title,
                  child: Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium))),
          IconButton(
              tooltip: l10n.moveToTrashAction,
              onPressed: id == null ? null : () => onDelete(id, title),
              icon: const AppSvgIcon('delete', size: 18)),
        ]),
        if (updated.isNotEmpty)
          Text(l10n.dashboardSavedAt(updated),
              style: Theme.of(context).textTheme.bodySmall),
        Align(
            alignment: Alignment.centerLeft,
            child: primary
                ? FilledButton(
                    onPressed: id == null ? null : () => onOpen(id),
                    child: Text(l10n.dashboardContinueExploring))
                : TextButton(
                    onPressed: id == null ? null : () => onOpen(id),
                    child: Text(l10n.dashboardContinueExploring))),
      ]),
    );
  }
}
