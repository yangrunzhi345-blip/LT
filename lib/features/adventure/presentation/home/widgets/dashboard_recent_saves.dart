import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/feedback/app_feedback.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../../core/widgets/app_svg_icon.dart';
import '../../../../../core/widgets/workbench_section.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../../providers/riverpod_providers.dart';

/// The most recent story leads, followed by a dense list of real adventures.
class DashboardRecentSaves extends ConsumerWidget {
  const DashboardRecentSaves({super.key, this.onOpenWizard});
  final VoidCallback? onOpenWizard;

  Future<void> _delete(
      BuildContext context, WidgetRef ref, int id, String title) async {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final confirmed = await AppConfirmDialog.show(
      context: context,
      title: l10n.dashboardDeleteAdventureTitle,
      message: l10n.dashboardDeleteAdventureMessage(title),
      confirmLabel: l10n.deleteAction,
      isDanger: true,
    );
    if (confirmed && context.mounted) {
      await ref.read(chatProvider).deleteAdventure(id);
      if (context.mounted) {
        AppFeedback.success(context, l10n.dashboardAdventureDeleted(title));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final chat = ref.watch(chatProvider);
    final adventures = chat.adventureList;
    if (adventures.isEmpty) {
      return WorkbenchSection(
        title: l10n.dashboardNoAdventuresTitle,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.dashboardNoAdventuresDesc),
          if (onOpenWizard != null)
            TextButton(
                onPressed: onOpenWizard,
                child: Text(l10n.dashboardWizardCardAction)),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      WorkbenchSection(
        title: l10n.dashboardContinueAdventures,
        child: _AdventureRow(
          item: adventures.first,
          primary: true,
          onOpen: (id) => chat.openAdventure(id),
          onDelete: (id, title) => _delete(context, ref, id, title),
        ),
      ),
      if (adventures.length > 1) ...[
        const SizedBox(height: AppSpacing.xl),
        WorkbenchSection(
            title: l10n.workbenchRecentAdventures,
            child: Column(children: [
              for (final item in adventures.skip(1))
                _AdventureRow(
                    item: item,
                    onOpen: (id) => chat.openAdventure(id),
                    onDelete: (id, title) => _delete(context, ref, id, title)),
            ])),
      ],
    ]);
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
              tooltip: l10n.dashboardDeleteAdventureTooltip,
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
