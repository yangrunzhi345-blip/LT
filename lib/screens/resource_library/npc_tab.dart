import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import '../../widgets/narr_aitor_loading.dart';
import '../../providers/riverpod_providers.dart';
import '../../models/resource_library_mode.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/form_sub_page_scaffold.dart';
import '../../utils/time_format.dart';
import '../../core/feedback/app_feedback.dart';
import '../../application/resource_library/import_models.dart';
import '../../models/resource_provenance.dart';
import 'resource_card_ai_import_page.dart';
import 'npc_edit_page.dart';

/// NPC 列表 + 编辑子页面 + JSON 导入 + AI 导入子页面
class NpcTab {
  /// 手动创建/编辑 NPC 子页面。
  static Future<void> showEdit(
      BuildContext context,
      Map<String, dynamic>? existing,
      VoidCallback onChanged,
      List<Map<String, dynamic>> worldviewItems,
      {ResourceLibraryMode mode = ResourceLibraryMode.adventure}) {
    return showNpcEditPage(
      context,
      existing: existing,
      onChanged: onChanged,
      worldviewItems: worldviewItems,
      mode: mode,
    );
  }

  /// AI 导入 NPC 弹窗
  static void showAiImport(BuildContext context, VoidCallback onChanged,
      List<Map<String, dynamic>> worldviewItems,
      {List<Map<String, dynamic>> characterCards = const [],
      String detailInstruction = '',
      AiGenerationDepth aiDepth = AiGenerationDepth.simple,
      ResourceLibraryMode mode = ResourceLibraryMode.adventure}) {
    ProviderScope.containerOf(context, listen: false)
        .read(resourceCardImportControllerProvider)
        .reset();
    showFormSubPage<void>(
      context: context,
      title: 'AI 助手创作 NPC',
      maxWidth: 840,
      builder: (_) => ResourceCardAiImportPage(
        kind: ResourceCardImportKind.npc,
        worldviews: worldviewItems,
        characterCards: characterCards,
        detailInstruction: detailInstruction,
        aiDepth: aiDepth,
        mode: mode,
        onChanged: onChanged,
      ),
    );
  }

  /// NPC 列表
  static Widget buildList(
      bool loading,
      List<Map<String, dynamic>> items,
      List<Map<String, dynamic>> worldviewItems,
      BuildContext context,
      VoidCallback onChanged,
      {ResourceLibraryMode mode = ResourceLibraryMode.adventure}) {
    if (loading) return const NarrAItorLoading.normal();
    if (items.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.people, size: 48, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text(mode.emptyTitle, style: TextStyle(color: Colors.grey[500])),
        const SizedBox(height: 4),
        Text(mode.emptySubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey[400])),
        const SizedBox(height: 8),
        FilledButton.icon(
            onPressed: () =>
                showEdit(context, null, onChanged, worldviewItems, mode: mode),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('创建 NPC')),
      ]));
    }
    return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[i];
          final name = item['name'] as String? ?? '';
          final source = item['source'] as String? ?? '';
          final worldviewId = item['matching_worldview_id'] as String? ?? '';
          final crud = ProviderScope.containerOf(context, listen: false)
              .read(resourceCrudControllerProvider);
          final json = crud.decodeCardData(item);
          final role =
              json['profession'] as String? ?? json['role'] as String? ?? '';
          final personality = json['personality'] as String? ?? '';
          final age = json['age']?.toString() ?? '';
          String worldviewName = '';
          if (worldviewId.isNotEmpty) {
            worldviewName = worldviewItems
                    .where((w) => w['id'] == worldviewId)
                    .firstOrNull?['name'] as String? ??
                '';
          }
          return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Row(children: [
                  Expanded(
                      child: Text(name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600))),
                  if (source.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.teal.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(source,
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.teal)),
                    ),
                ]),
                subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (role.isNotEmpty ||
                          personality.isNotEmpty ||
                          age.isNotEmpty)
                        Text(
                            [
                              if (age.isNotEmpty) '$age岁',
                              if (role.isNotEmpty) role,
                              if (personality.isNotEmpty) personality
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                      if (worldviewName.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text('契合：$worldviewName',
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.accent))),
                      () {
                        final rawCustom = json['custom_attributes'] ??
                            json['customAttributes'];
                        final customCount =
                            (rawCustom is List) ? rawCustom.length : 0;
                        if (customCount > 0) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text('自添加项：$customCount 项',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.teal,
                                    fontWeight: FontWeight.w500)),
                          );
                        }
                        return const SizedBox.shrink();
                      }(),
                      Text(
                          formatTimestamp(item['updated_at'] as String? ??
                              item['created_at'] as String?),
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.textSecondary)),
                    ]),
                leading: const Icon(Icons.person, color: AppColors.teal),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      onPressed: () => showEdit(
                          context, item, onChanged, worldviewItems,
                          mode: mode),
                      visualDensity: VisualDensity.compact),
                  IconButton(
                      icon: const Icon(Icons.delete,
                          size: 18, color: AppColors.error),
                      onPressed: () async {
                        final crud =
                            ProviderScope.containerOf(context, listen: false)
                                .read(resourceCrudControllerProvider);
                        final confirm = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                                    title: const Text('确认删除'),
                                    content: Text('确定要删除 NPC「$name」吗？'),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, false),
                                          child: const Text('取消')),
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, true),
                                          child: const Text('删除',
                                              style: TextStyle(
                                                  color: AppColors.error)))
                                    ]));
                        if (confirm != true) return;
                        final result = await crud
                            .deleteNpcCard(item['id'] as String, mode: mode);
                        if (!result.success) {
                          debugPrint(
                              '[WorldviewEditor] 删除NPC失败: ${result.errorMessage}');
                          if (context.mounted) {
                            AppFeedback.error(context, '删除 NPC 失败，请重试');
                          }
                          return;
                        }
                        onChanged();
                      },
                      visualDensity: VisualDensity.compact),
                ]),
                onTap: () => showEdit(context, item, onChanged, worldviewItems,
                    mode: mode),
              ));
        });
  }
}
