import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/app_page_scaffold.dart';
import '../../../../core/widgets/app_confirm_dialog.dart';
import '../../application/use_cases/resource_trash_runtime.dart';
import '../../domain/models/resource_trash_view_state.dart';
import '../controllers/resource_trash_controller.dart';

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
    super.key,
  });

  final ResourceTrashViewState state;
  final VoidCallback onRefresh;
  final void Function(String trashId) onRestore;

  /// Called only after the view itself has confirmed with the user.
  final void Function(String trashId) onPermanentDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '回收站',
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: state.isLoading ? null : onRefresh,
                    icon: const Icon(Icons.refresh),
                    tooltip: '刷新回收站',
                  ),
                ],
              ),
            ),
            if (state.statusMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(state.statusMessage, softWrap: true),
              ),
            if (state.errorMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  state.errorMessage,
                  softWrap: true,
                  style: TextStyle(color: theme.colorScheme.error),
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
    final theme = Theme.of(context);
    if (state.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Text('回收站是空的', style: theme.textTheme.bodyMedium),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: state.items.length,
      itemBuilder: (context, index) => _buildRow(context, state.items[index]),
    );
  }

  Widget _buildRow(BuildContext context, ResourceTrashItem item) {
    final theme = Theme.of(context);
    final busy = state.busyTrashId == item.trashId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: theme.textTheme.bodyLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                item.subtitle,
                softWrap: true,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: busy || state.isLoading
                        ? null
                        : () => onRestore(item.trashId),
                    icon: const Icon(Icons.restore),
                    label: const Text('恢复'),
                  ),
                  TextButton.icon(
                    onPressed: busy || state.isLoading
                        ? null
                        : () => _confirmPermanentDelete(context, item),
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('永久删除'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Permanent delete is a second, explicit confirmation: it is the only path
  /// in the app that physically destroys resource content.
  Future<void> _confirmPermanentDelete(
    BuildContext context,
    ResourceTrashItem item,
  ) async {
    final confirmed = await AppConfirmDialog.show(
      context: context,
      title: '永久删除',
      message: '「${item.title}」及其内容将被彻底删除，无法恢复。\n确定要继续吗？',
      confirmLabel: '永久删除',
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
    return AppPageScaffold(
      title: '回收站',
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => ResourceTrashView(
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
