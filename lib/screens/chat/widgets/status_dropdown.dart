import 'package:flutter/material.dart';
import '../../../core/widgets/app_action_menu.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Chat status actions. Despite the historical name this is an *action* menu
/// (`edit` / `delete`), so it uses the shared [AppActionMenu] kernel rather than
/// a value select.
class StatusDropdown extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const StatusDropdown(
      {super.key, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppActionMenu<String>(
      icon: 'more',
      iconSize: 18,
      tooltip: l10n.chatMoreActions,
      items: [
        AppActionMenuItem(
          value: 'edit',
          label: l10n.chatEditStatus,
          icon: 'edit',
        ),
        AppActionMenuItem(
          value: 'delete',
          label: l10n.chatDeleteStatus,
          icon: 'delete',
          destructive: true,
          dividerBefore: true,
        ),
      ],
      onSelected: (val) {
        if (val == 'edit') onEdit();
        if (val == 'delete') onDelete();
      },
    );
  }
}
