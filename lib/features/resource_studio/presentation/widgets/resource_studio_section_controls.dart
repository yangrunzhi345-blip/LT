import 'package:flutter/material.dart';

import '../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../domain/resources/section_control.dart';
import '../../domain/models/section_control_view_state.dart';
import '../resource_studio_user_message.dart';

/// Section-level control panel for the Resource Studio.
///
/// Shows one row per section with its title, lifecycle status, sibling order
/// and last update, plus the section operations (generate / regenerate,
/// validate, rename, move, delete).
///
/// Responsive rules:
/// - no fixed widths and no horizontal scrolling: metadata and actions live in
///   [Wrap] so a 320 px viewport reflows instead of overflowing;
/// - dynamic text (titles, status, timestamps) is either ellipsized with a
///   bounded `maxLines` or allowed to wrap;
/// - secondary operations sit in an overflow menu so the primary actions stay
///   reachable at any width.
final class ResourceStudioSectionControls extends StatelessWidget {
  const ResourceStudioSectionControls({
    required this.state,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onCreate,
    required this.onRename,
    required this.onDelete,
    required this.onMove,
    required this.onValidate,
    required this.onRegenerate,
    super.key,
  });

  final SectionControlViewState state;
  final VoidCallback onRefresh;
  final VoidCallback onLoadMore;
  final VoidCallback onCreate;
  final void Function(SectionControlEntry entry, String title) onRename;
  final ValueChanged<SectionControlEntry> onDelete;
  final void Function(SectionControlEntry entry, int targetIndex) onMove;
  final ValueChanged<SectionControlEntry> onValidate;
  final ValueChanged<SectionControlEntry> onRegenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ExpansionTile(
        initiallyExpanded: false,
        title: Text('章节控制', style: theme.textTheme.titleMedium),
        subtitle: Text('${state.totalCount} 个章节'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: state.isLoading ? null : onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('刷新'),
              ),
              FilledButton.icon(
                onPressed: state.resourceId == null ? null : onCreate,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('新增章节'),
              ),
            ],
          ),
          if (state.errorMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              state.errorMessage,
              softWrap: true,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          if (state.lastMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(state.lastMessage, softWrap: true),
          ],
          const SizedBox(height: 8),
          if (state.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (state.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('该资源还没有章节。'),
            )
          else
            for (var index = 0; index < state.entries.length; index++)
              _SectionControlTile(
                key: ValueKey(state.entries[index].id.value),
                entry: state.entries[index],
                index: index,
                isBusy: state.isBusy(state.entries[index].id.value),
                canMoveUp: index > 0,
                canMoveDown: index < state.entries.length - 1,
                onRename: onRename,
                onDelete: onDelete,
                onMove: onMove,
                onValidate: onValidate,
                onRegenerate: onRegenerate,
              ),
          if (state.hasMore)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onLoadMore,
                icon: const Icon(Icons.expand_more_rounded, size: 18),
                label: Text(
                  '加载更多（已显示 ${state.entries.length}/'
                  '${state.totalCount}）',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

final class _SectionControlTile extends StatelessWidget {
  const _SectionControlTile({
    required this.entry,
    required this.index,
    required this.isBusy,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onRename,
    required this.onDelete,
    required this.onMove,
    required this.onValidate,
    required this.onRegenerate,
    super.key,
  });

  final SectionControlEntry entry;
  final int index;
  final bool isBusy;
  final bool canMoveUp;
  final bool canMoveDown;
  final void Function(SectionControlEntry entry, String title) onRename;
  final ValueChanged<SectionControlEntry> onDelete;
  final void Function(SectionControlEntry entry, int targetIndex) onMove;
  final ValueChanged<SectionControlEntry> onValidate;
  final ValueChanged<SectionControlEntry> onRegenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final actionable = !isBusy;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    entry.title.isEmpty ? '（未命名章节）' : entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (isBusy)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _StatusPill(
                  label: _generationLabel(entry.generationState),
                  color: _generationColor(entry.generationState, scheme),
                ),
                _StatusPill(
                  label: _validationLabel(entry.validationState),
                  color: _validationColor(entry.validationState, scheme),
                ),
                _StatusPill(label: '序号 ${entry.orderIndex + 1}', color: null),
                _StatusPill(
                  label: '更新 ${_formatTime(entry.updatedAt)}',
                  color: null,
                ),
              ],
            ),
            if (entry.validationState == SectionValidationState.invalid &&
                entry.validationMessage.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                resourceStudioUserMessage(entry.validationMessage),
                softWrap: true,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                Tooltip(
                  message: _regenerateTooltip(entry),
                  child: TextButton.icon(
                    // Gated on task presence, not Part count: a hand-authored
                    // section can have Parts but still be unable to generate.
                    // A fully completed section is also gated off: re-running
                    // its tasks needs a controlled reset or a revision, which
                    // is owned by Phase 9, and advertising a dead action is
                    // worse than disabling it with a reason (Phase 7 D2).
                    onPressed: actionable && _canRegenerate(entry)
                        ? () => onRegenerate(entry)
                        : null,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: Text(_generateLabel(entry)),
                  ),
                ),
                TextButton.icon(
                  onPressed: actionable ? () => onValidate(entry) : null,
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('验证'),
                ),
                PopupMenuButton<_SectionMenuAction>(
                  enabled: actionable,
                  tooltip: '更多操作',
                  onSelected: (action) => _handleMenu(context, action),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: _SectionMenuAction.rename,
                      child: Text('重命名'),
                    ),
                    PopupMenuItem(
                      value: _SectionMenuAction.moveUp,
                      enabled: canMoveUp,
                      child: const Text('上移'),
                    ),
                    PopupMenuItem(
                      value: _SectionMenuAction.moveDown,
                      enabled: canMoveDown,
                      child: const Text('下移'),
                    ),
                    const PopupMenuItem(
                      value: _SectionMenuAction.delete,
                      child: Text('删除'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleMenu(
    BuildContext context,
    _SectionMenuAction action,
  ) async {
    switch (action) {
      case _SectionMenuAction.rename:
        final title = await _promptTitle(context, entry.title);
        if (title != null && title.trim().isNotEmpty) {
          onRename(entry, title.trim());
        }
      case _SectionMenuAction.moveUp:
        onMove(entry, index - 1);
      case _SectionMenuAction.moveDown:
        onMove(entry, index + 1);
      case _SectionMenuAction.delete:
        final confirmed = await _confirmDelete(context);
        if (confirmed) onDelete(entry);
    }
  }

  Future<String?> _promptTitle(BuildContext context, String current) {
    return showDialog<String>(
      context: context,
      builder: (_) => _RenameSectionDialog(initialTitle: current),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return AppConfirmDialog.show(
      context: context,
      title: '删除章节',
      message: '确定删除「${entry.title.isEmpty ? entry.id.value : entry.title}」'
          '及其所有内容吗？',
      confirmLabel: '删除',
      isDanger: true,
      icon: Icons.delete_outline_rounded,
    );
  }

  /// Label of the AI generation action.
  ///
  /// "生成" when there is nothing to regenerate (a hand-authored section, or a
  /// task-backed section whose Parts are still empty); "重新生成" once content
  /// exists or generation has already run.
  static String _generateLabel(SectionControlEntry entry) {
    if (!entry.hasGenerationTasks) return '生成';
    if (entry.generationState == SectionGenerationState.completed) {
      return '重新生成';
    }
    return entry.partCount > 0 ? '重新生成' : '生成';
  }

  /// Whether the generation action can actually run for [entry].
  ///
  /// A fully completed section used to be gated off because Phase 5 refuses to
  /// restart a completed task. Phase 9 supplies the missing half — the revision
  /// boundary reopens those tasks under a controlled reset inside the same
  /// transaction that records the pre-regeneration snapshot — so the action is
  /// available again and rolling back is possible if the user dislikes the
  /// result.
  static bool _canRegenerate(SectionControlEntry entry) =>
      entry.hasGenerationTasks &&
      entry.generationState != SectionGenerationState.generating &&
      entry.generationState != SectionGenerationState.validating;

  /// Explains why the generation action is enabled or disabled.
  static String _regenerateTooltip(SectionControlEntry entry) {
    if (!entry.hasGenerationTasks) {
      return '该章节没有生成任务（非 AI 蓝图创建），无法生成';
    }
    if (entry.generationState == SectionGenerationState.completed) {
      return '重新运行该章节的生成任务；当前内容会先记录为历史版本，可随时恢复';
    }
    return '重新运行该章节的生成任务';
  }

  static String _generationLabel(SectionGenerationState state) =>
      switch (state) {
        SectionGenerationState.pending => '待生成',
        SectionGenerationState.generating => '生成中',
        SectionGenerationState.generated => '已生成',
        SectionGenerationState.validating => '生成中',
        SectionGenerationState.completed => '已保存',
        SectionGenerationState.failed => '优化失败',
        SectionGenerationState.cancelled => '已取消',
      };

  static String _validationLabel(SectionValidationState state) =>
      switch (state) {
        SectionValidationState.unvalidated => '建议优化',
        SectionValidationState.validating => '正在优化',
        SectionValidationState.valid => '已准备完成',
        SectionValidationState.invalid => '优化失败',
        SectionValidationState.stale => '建议优化',
      };

  static Color _generationColor(
    SectionGenerationState state,
    ColorScheme scheme,
  ) =>
      switch (state) {
        SectionGenerationState.completed => scheme.primary,
        SectionGenerationState.generated => scheme.tertiary,
        SectionGenerationState.generating ||
        SectionGenerationState.validating =>
          scheme.secondary,
        SectionGenerationState.failed => scheme.error,
        SectionGenerationState.cancelled => scheme.outline,
        SectionGenerationState.pending => scheme.outline,
      };

  static Color _validationColor(
    SectionValidationState state,
    ColorScheme scheme,
  ) =>
      switch (state) {
        SectionValidationState.valid => scheme.primary,
        SectionValidationState.invalid => scheme.error,
        SectionValidationState.validating => scheme.secondary,
        SectionValidationState.stale => scheme.tertiary,
        SectionValidationState.unvalidated => scheme.outline,
      };

  static String _formatTime(DateTime? time) {
    if (time == null) return '—';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}

final class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effective = color ?? scheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: effective.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: effective.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style:
            Theme.of(context).textTheme.labelSmall?.copyWith(color: effective),
      ),
    );
  }
}

enum _SectionMenuAction { rename, moveUp, moveDown, delete }

/// Rename dialog that owns its [TextEditingController].
///
/// The controller must live in a stateful widget: disposing it when the future
/// completes would run while the route is still animating out and the
/// `TextField` would rebuild against a disposed controller.
final class _RenameSectionDialog extends StatefulWidget {
  const _RenameSectionDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_RenameSectionDialog> createState() => _RenameSectionDialogState();
}

final class _RenameSectionDialogState extends State<_RenameSectionDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialTitle);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('重命名章节'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '章节标题'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: const Text('保存'),
          ),
        ],
      );
}
