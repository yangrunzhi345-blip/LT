import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../../../core/widgets/app_page_scaffold.dart';
import '../../../../../../providers/riverpod_providers.dart';

/// Manages saved conversations outside the sidebar overlay.
class ConversationManagePage extends ConsumerStatefulWidget {
  const ConversationManagePage({super.key});

  @override
  ConsumerState<ConversationManagePage> createState() =>
      _ConversationManagePageState();
}

class _ConversationManagePageState
    extends ConsumerState<ConversationManagePage> {
  final Set<int> _selectedIds = {};
  bool _isDeleting = false;
  String? _error;

  Future<void> _deleteSelected() async {
    if (_isDeleting || _selectedIds.isEmpty) return;
    final chat = ref.read(chatProvider);
    final availableIds =
        chat.adventureList.map((item) => item['id']).whereType<int>().toSet();
    final selected = _selectedIds.intersection(availableIds);
    if (selected.isEmpty) return;
    final count = selected.length;
    final confirmed = await AppConfirmDialog.show(
      context: context,
      title: '删除场景对话',
      message: '确定删除选中的 $count 段场景对话吗？删除后历史对话与演变剧情将无法恢复。',
      confirmLabel: '删除',
      isDanger: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _isDeleting = true;
      _error = null;
    });
    try {
      for (final id in selected) {
        await chat.deleteAdventure(id);
        if (!mounted) return;
        setState(() => _selectedIds.remove(id));
      }
    } catch (error) {
      if (mounted) setState(() => _error = '删除中断，请检查剩余会话后重试：$error');
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final adventures = ref.watch(chatProvider).adventureList;
    final items = [
      for (final item in adventures)
        if (item['id'] is int)
          (id: item['id'] as int, title: item['title'] as String? ?? '未命名场景'),
    ];
    final ids = items.map((item) => item.id).toSet();
    final selectedCount = _selectedIds.intersection(ids).length;

    return AppPageScaffold(
      title: '管理过去的对话',
      bottomBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Text('已选 $selectedCount 项'),
              FilledButton.icon(
                key: const Key('conversation-manage-delete'),
                onPressed:
                    _isDeleting || selectedCount == 0 ? null : _deleteSelected,
                icon: _isDeleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline),
                label: Text(_isDeleting ? '删除中...' : '批量删除'),
              ),
            ],
          ),
        ),
      ),
      body: items.isEmpty
          ? const Center(child: Text('暂无可管理的场景对话'))
          : ListView(
              children: [
                CheckboxListTile(
                  key: const Key('conversation-manage-select-all'),
                  title: const Text('全选'),
                  value: selectedCount == items.length,
                  onChanged: _isDeleting
                      ? null
                      : (value) => setState(() {
                            if (value == true) {
                              _selectedIds.addAll(ids);
                            } else {
                              _selectedIds.clear();
                            }
                          }),
                ),
                const Divider(height: 1),
                for (final item in items)
                  CheckboxListTile(
                    key: Key('conversation-manage-${item.id}'),
                    title: Text(item.title),
                    subtitle: const Text('场景对话'),
                    value: _selectedIds.contains(item.id),
                    onChanged: _isDeleting
                        ? null
                        : (value) => setState(() {
                              if (value == true) {
                                _selectedIds.add(item.id);
                              } else {
                                _selectedIds.remove(item.id);
                              }
                            }),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
              ],
            ),
    );
  }
}
