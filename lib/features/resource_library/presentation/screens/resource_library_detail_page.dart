import 'package:flutter/material.dart';

import '../../../../../core/feedback/app_feedback.dart';
import '../../../../../core/widgets/app_buttons.dart';
import '../../../../../core/widgets/app_confirm_dialog.dart';
import '../../../resource_studio/presentation/pages/resource_studio_page.dart';
import '../../domain/models/resource_library_view_state.dart';
import '../../../../../l10n/generated/app_localizations.dart';

final class ResourceLibraryDetailPage extends StatefulWidget {
  const ResourceLibraryDetailPage({
    required this.item,
    required this.onMoveToTrash,
    super.key,
  });

  final ResourceLibraryItem item;
  final Future<String?> Function() onMoveToTrash;

  @override
  State<ResourceLibraryDetailPage> createState() =>
      _ResourceLibraryDetailPageState();
}

final class _ResourceLibraryDetailPageState
    extends State<ResourceLibraryDetailPage> {
  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.resourceDetailTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text(item.typeLabel)),
                    Chip(label: Text(item.status.label)),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  item.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                  softWrap: true,
                ),
                if (item.summary.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(item.summary, softWrap: true),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: item.isStudioAvailable
                      ? () async {
                          // Keep the library's route future pending until the
                          // editor closes, then return to refresh its list.
                          await Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => ResourceStudioPage(
                                resourceId: item.id,
                              ),
                            ),
                          );
                          if (context.mounted) Navigator.of(context).pop();
                        }
                      : null,
                  icon: const Icon(Icons.edit_note_rounded),
                  label: Text(
                    item.isStudioAvailable
                        ? l10n.resourceEnterStudio
                        : l10n.resourceLegacyNoStudio,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  l10n.resourceActions,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                AppDangerButton(
                  key: const Key('resource-move-to-trash-button'),
                  label: l10n.moveToTrashAction,
                  icon: Icons.delete_outline_rounded,
                  outlined: true,
                  fullWidth: true,
                  isLoading: _isDeleting,
                  onPressed: _confirmMoveToTrash,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmMoveToTrash() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await AppConfirmDialog.show(
      context: context,
      title: l10n.moveToTrashAction,
      message: l10n.moveToTrashMessage(widget.item.name),
      confirmLabel: l10n.moveToTrashAction,
      isDanger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isDeleting = true);
    final message = await widget.onMoveToTrash();
    if (!mounted) return;
    if (message == null) {
      setState(() => _isDeleting = false);
      AppFeedback.error(context, l10n.moveToTrashFailed);
      return;
    }
    Navigator.of(context).pop(message);
  }
}
