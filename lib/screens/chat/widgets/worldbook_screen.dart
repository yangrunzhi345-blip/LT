import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;

import '../../../core/feedback/app_feedback.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/world_entry.dart';
import '../../../providers/riverpod_providers.dart';

/// 世界书（Worldbook）管理页 — 当前冒险的世界条目列表与编辑。
///
/// 数据经 adventureProvider（状态层）读写，页面不触碰 Repository。
class WorldBookScreen extends ConsumerStatefulWidget {
  const WorldBookScreen({super.key});

  @override
  ConsumerState<WorldBookScreen> createState() => _WorldBookScreenState();
}

class _WorldBookScreenState extends ConsumerState<WorldBookScreen> {
  @override
  Widget build(BuildContext context) {
    final adventure = ref.watch(adventureProvider);
    final entries = adventure.worldEntries;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
      appBar: AppBar(
        title: const Text('世界书'),
        actions: [
          IconButton(
            tooltip: '导入',
            icon: const Icon(Icons.upload_file),
            onPressed: () => _importJson(context),
          ),
          IconButton(
            tooltip: '导出',
            icon: const Icon(Icons.download),
            onPressed: () =>
                _exportJson(context, adventure.exportWorldBookJson()),
          ),
        ],
      ),
      body: entries.isEmpty
          ? Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.menu_book_outlined,
                        size: 46, color: AppColors.accent),
                    const SizedBox(height: 12),
                    const Text('世界书为空',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text('点击右下角 + 添加世界条目，或从其他来源导入',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ]),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                        entry.enabled ? Icons.bookmark : Icons.bookmark_border,
                        color: entry.enabled ? AppColors.accent : Colors.grey),
                    title: Text(entry.keys.join('，'),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      entry.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Switch(
                        value: entry.enabled,
                        onChanged: (value) {
                          final updated = WorldEntry.fromJson(entry.toJson())
                            ..enabled = value;
                          adventure.updateWorldEntry(updated);
                        },
                      ),
                      IconButton(
                        tooltip: '编辑',
                        icon: const Icon(Icons.edit, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _showEditor(context, adventure, entry),
                      ),
                      IconButton(
                        tooltip: '删除',
                        icon: const Icon(Icons.delete,
                            size: 18, color: Colors.red),
                        visualDensity: VisualDensity.compact,
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('确认删除'),
                              content:
                                  Text('确定要删除世界条目「${entry.keys.join('，')}」吗？'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('取消')),
                                TextButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('删除',
                                        style:
                                            TextStyle(color: AppColors.error))),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await adventure.deleteWorldEntry(entry.id ?? -1);
                          }
                        },
                      ),
                    ]),
                    onTap: () => _showEditor(context, adventure, entry),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: '新建条目',
        onPressed: () => _showEditor(context, adventure, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showEditor(
      BuildContext context, dynamic adventure, WorldEntry? existing) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _WorldEntryEditorDialog(
        existing: existing,
        adventureId: adventure.currentAdventureId ?? 0,
      ),
    );
    if (saved == true && context.mounted) {
      AppFeedback.success(context, existing == null ? '世界条目已添加' : '世界条目已更新');
    }
  }

  Future<void> _exportJson(BuildContext context, String json) async {
    await Clipboard.setData(ClipboardData(text: json));
    if (context.mounted) {
      AppFeedback.success(context, '已复制世界书 JSON 到剪贴板');
    }
  }

  Future<void> _importJson(BuildContext context) async {
    final text = await _pasteText(context);
    if (text == null || text.trim().isEmpty) return;
    final adventure = ref.read(adventureProvider);
    try {
      await adventure.importWorldBookJson(text.trim(), '剪贴板导入');
      if (context.mounted) {
        AppFeedback.success(context, '世界书导入成功');
      }
    } catch (e) {
      if (context.mounted) {
        AppFeedback.error(context, '导入失败：${e.toString().split('\n').first}');
      }
    }
  }

  Future<String?> _pasteText(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('导入世界书'),
        content: const Text('将世界书 JSON 粘贴到下方后确认导入。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final data = await Clipboard.getData('text/plain');
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext, data?.text);
            },
            child: const Text('从剪贴板粘贴并导入'),
          ),
        ],
      ),
    );
  }
}

/// 世界条目编辑对话框（核心字段）。
class _WorldEntryEditorDialog extends StatefulWidget {
  final WorldEntry? existing;
  final int adventureId;

  const _WorldEntryEditorDialog({
    required this.existing,
    required this.adventureId,
  });

  @override
  State<_WorldEntryEditorDialog> createState() =>
      _WorldEntryEditorDialogState();
}

class _WorldEntryEditorDialogState extends State<_WorldEntryEditorDialog> {
  late final TextEditingController _keysCtrl =
      TextEditingController(text: widget.existing?.keys.join('，') ?? '');
  late final TextEditingController _contentCtrl =
      TextEditingController(text: widget.existing?.content ?? '');
  late final TextEditingController _probabilityCtrl = TextEditingController(
      text: widget.existing?.probability.toString() ?? '100');
  late final TextEditingController _cooldownCtrl =
      TextEditingController(text: widget.existing?.cooldown.toString() ?? '0');
  late bool _enabled = widget.existing?.enabled ?? true;

  @override
  void dispose() {
    _keysCtrl.dispose();
    _contentCtrl.dispose();
    _probabilityCtrl.dispose();
    _cooldownCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? '新建世界条目' : '编辑世界条目'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _keysCtrl,
                decoration: const InputDecoration(
                    labelText: '触发关键词（逗号分隔）', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contentCtrl,
                maxLines: 5,
                minLines: 3,
                decoration: const InputDecoration(
                    labelText: '条目内容', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _probabilityCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: '触发概率 %', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _cooldownCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: '冷却轮数', border: OutlineInputBorder()),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用'),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消')),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final keys = _keysCtrl.text
        .split(RegExp(r'[,，]'))
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toList();
    if (keys.isEmpty) {
      AppFeedback.error(context, '请至少填写一个触发关键词');
      return;
    }
    final existing = widget.existing;
    final entry = WorldEntry(
      id: existing?.id,
      adventureId: existing?.adventureId ?? widget.adventureId,
      keys: keys,
      content: _contentCtrl.text.trim(),
      insertionOrder: existing?.insertionOrder ?? 0,
      probability: int.tryParse(_probabilityCtrl.text) ?? 100,
      cooldown: int.tryParse(_cooldownCtrl.text) ?? 0,
      sticky: existing?.sticky ?? 0,
      useRegex: existing?.useRegex ?? false,
      insertPosition:
          existing?.insertPosition ?? WorldEntryPosition.afterPrompt,
      recursive: existing?.recursive ?? false,
      enabled: _enabled,
      sourceType: existing?.sourceType ?? 'manual',
      sourceId: existing?.sourceId ?? '',
      sourceSnapshotHash: existing?.sourceSnapshotHash ?? '',
    );
    final adventure = ProviderScope.containerOf(context, listen: false)
        .read(adventureProvider);
    if (existing == null) {
      await adventure.addWorldEntry(entry);
    } else {
      await adventure.updateWorldEntry(entry);
    }
    if (mounted) Navigator.pop(context, true);
  }
}
