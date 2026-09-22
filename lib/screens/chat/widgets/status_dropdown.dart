import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';

class StatusDropdown extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const StatusDropdown(
      {super.key, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      tooltip: l10n.chatMoreActions,
      icon: const Icon(Icons.more_vert_rounded, size: 18),
      padding: EdgeInsets.zero,
      onSelected: (val) {
        if (val == 'edit') onEdit();
        if (val == 'delete') onDelete();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              const Icon(Icons.edit_outlined, size: 16),
              const SizedBox(width: 8),
              Text(l10n.chatEditStatus),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 16, color: colorScheme.error),
              const SizedBox(width: 8),
              Text(l10n.chatDeleteStatus,
                  style: TextStyle(color: colorScheme.error)),
            ],
          ),
        ),
      ],
    );
  }
}
