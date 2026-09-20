import 'package:flutter/material.dart';

import '../../../../../core/feedback/app_feedback.dart';
import '../../../../../core/widgets/app_buttons.dart';
import '../../../../../core/widgets/app_confirm_dialog.dart';
import '../../../resource_studio/presentation/pages/resource_studio_page.dart';
import '../../domain/models/resource_library_view_state.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('资源详情')),
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
                    item.isStudioAvailable ? '进入创作工作台' : '旧资源暂不支持高级创作',
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  '资源操作',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                AppDangerButton(
                  key: const Key('resource-move-to-trash-button'),
                  label: '移入回收站',
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
    final confirmed = await AppConfirmDialog.show(
      context: context,
      title: '移入回收站',
      message: '将「${widget.item.name}」移入回收站？之后可在回收站中恢复。',
      confirmLabel: '移入回收站',
      isDanger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isDeleting = true);
    final message = await widget.onMoveToTrash();
    if (!mounted) return;
    if (message == null) {
      setState(() => _isDeleting = false);
      AppFeedback.error(context, '移入回收站失败，请重试');
      return;
    }
    Navigator.of(context).pop(message);
  }
}
