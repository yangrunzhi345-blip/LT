import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import '../../providers/riverpod_providers.dart';
import '../../models/resource_library_mode.dart';
import '../../core/theme/app_colors.dart';
import '../../core/feedback/app_feedback.dart';
import '../../utils/time_format.dart';
import '../../widgets/narr_aitor_loading.dart';

/// 预存冒险列表
class TemplateTab {
  static Widget buildList(bool loading, List<Map<String, dynamic>> items,
      BuildContext context, VoidCallback onChanged,
      {ResourceLibraryMode mode = ResourceLibraryMode.adventure}) {
    if (loading) return const NarrAItorLoading.normal();
    if (items.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.folder_open, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(mode == ResourceLibraryMode.creation ? '暂无创作模板' : '暂无预存场景',
              style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 4),
          Text('在「智能生成」或「自由定制」中保存冒险预设',
              style: TextStyle(fontSize: 12, color: Colors.grey[400])),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        final name = item['name'] as String? ?? '';
        final status = item['status'] as String? ?? 'draft';
        final wvName = item['worldview_name'] as String? ?? '';
        final createdAt = item['created_at'] as String? ?? '';
        final isComplete = status == 'complete';
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Row(children: [
              Expanded(
                  child: Text(name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: isComplete
                        ? Colors.green.withValues(alpha: 0.12)
                        : Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4)),
                child: Text(isComplete ? '已完成' : '未完成',
                    style: TextStyle(
                        fontSize: 10,
                        color: isComplete
                            ? Colors.green[700]
                            : Colors.orange[700])),
              ),
            ]),
            subtitle:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (wvName.isNotEmpty)
                Text('世界观：$wvName',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              if (createdAt.isNotEmpty)
                Text(
                    formatTimestamp(item['updated_at'] as String? ?? createdAt),
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textSecondary)),
            ]),
            leading: Icon(isComplete ? Icons.check_circle : Icons.edit_note,
                color: isComplete ? Colors.green : Colors.orange),
            onTap: () => _showDetail(context, item, mode),
            trailing: IconButton(
              icon: const Icon(Icons.delete, size: 18, color: Colors.red),
              onPressed: () async {
                final crud = ProviderScope.containerOf(context, listen: false)
                    .read(resourceCrudControllerProvider);
                final confirm = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                            title: const Text('确认删除'),
                            content: Text('确定要删除预存场景「$name」吗？'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(c, false),
                                  child: const Text('取消')),
                              TextButton(
                                  onPressed: () => Navigator.pop(c, true),
                                  child: const Text('删除',
                                      style: TextStyle(color: Colors.red)))
                            ]));
                if (confirm != true) return;
                final result = await crud
                    .deleteAdventureTemplate(item['id'] as String, mode: mode);
                if (!result.success) {
                  debugPrint(
                      '[WorldviewEditor] 删除模板失败: ${result.errorMessage}');
                  if (context.mounted) {
                    AppFeedback.error(
                        context, '删除模板失败: ${result.errorMessage}');
                  }
                }
                onChanged();
              },
              visualDensity: VisualDensity.compact,
            ),
          ),
        );
      },
    );
  }

  /// 模板内容详情（复用 buildPresetData 的结构化解析）。
  static Future<void> _showDetail(BuildContext context,
      Map<String, dynamic> item, ResourceLibraryMode mode) async {
    final preset = ProviderScope.containerOf(context, listen: false)
        .read(adventureTemplateControllerProvider)
        .buildPresetData(item);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(item['name'] as String? ?? '模板详情'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: preset == null
                ? const Text('模板数据不完整，无法预览')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🌍 ${preset.worldview}',
                          style: const TextStyle(height: 1.5)),
                      const Divider(height: 24),
                      Text(
                          '👤 ${preset.charName}'
                          '（${preset.gender} · ${preset.age} · ${preset.profession}）',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (preset.background.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(preset.background),
                      ],
                      if (preset.openingScene.isNotEmpty) ...[
                        const Divider(height: 24),
                        Text('🎬 ${preset.openingScene}',
                            style: const TextStyle(height: 1.5)),
                      ],
                      if (preset.options.isNotEmpty) ...[
                        const Divider(height: 24),
                        const Text('可用行动',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        for (final option in preset.options)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('· $option'),
                          ),
                      ],
                      if (preset.supportingCharacters.isNotEmpty) ...[
                        const Divider(height: 24),
                        const Text('配角',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        for (final character in preset.supportingCharacters)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child:
                                Text('· ${character.name}（${character.role}）：'
                                    '${character.personality}'),
                          ),
                      ],
                    ],
                  ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭')),
        ],
      ),
    );
  }
}
