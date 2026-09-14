import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import '../../widgets/narr_aitor_loading.dart';
import '../../providers/riverpod_providers.dart';
import '../../models/resource_library_mode.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/custom_attribute_importance_visuals.dart';
import '../../core/widgets/form_sub_page_scaffold.dart';
import '../../models/custom_attribute_item.dart';
import '../../utils/time_format.dart';
import '../../utils/structured_json_codec.dart';
import '../../widgets/app_dialogs.dart';
import '../../core/feedback/app_feedback.dart';
import '../../application/resource_library/import_models.dart';
import '../../models/resource_provenance.dart';
import 'resource_card_ai_import_page.dart';

/// 角色卡列表 + 详情弹窗 + 编辑 + AI 导入
class CharacterCardTab {
  /// 编辑角色卡（委托给 app_dialogs 的弹窗）
  static Future<void> showEdit(BuildContext context,
      Map<String, dynamic>? existing, VoidCallback onChanged,
      {ResourceLibraryMode mode = ResourceLibraryMode.adventure}) async {
    await showCreateCharacterCardDialog(context,
        existingCard: existing,
        existingId: existing?['id'] as String?,
        mode: mode);
    onChanged();
  }

  /// 角色卡详情弹窗
  static void showDetail(
      BuildContext context, Map<String, dynamic> item, VoidCallback onChanged,
      {ResourceLibraryMode mode = ResourceLibraryMode.adventure}) {
    final json =
        StructuredJsonCodec.tryDecodeStoredObject(item['json_data']) ?? {};
    final profile = json['world_profile'] is Map
        ? json['world_profile'] as Map
        : const <String, dynamic>{};
    showFormSubPage<void>(
      context: context,
      title: '角色卡详情',
      maxWidth: 760,
      builder: (ctx) => Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(children: [
            Text(json['name'] ?? item['name'] ?? '',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            if (json['gender'] != null && (json['gender'] as String).isNotEmpty)
              Text('${json['gender']}  ·  ${json['profession'] ?? ''}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const Divider(height: 24),
            if (json['personality'] != null &&
                (json['personality'] as String).isNotEmpty) ...[
              const Text('性格特征',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.teal)),
              const SizedBox(height: 6),
              Text(json['personality'] as String,
                  style: const TextStyle(fontSize: 14, height: 1.5)),
              const SizedBox(height: 16),
            ],
            if (json['description'] != null &&
                (json['description'] as String).isNotEmpty) ...[
              const Text('角色描述',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.teal)),
              const SizedBox(height: 6),
              Text(json['description'] as String,
                  style: const TextStyle(fontSize: 14, height: 1.5)),
            ],
            if (profile.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('世界内设定',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.teal)),
              const SizedBox(height: 6),
              ...[
                ['所属势力', profile['faction']],
                ['活动地点', profile['home_location']],
                ['公开目标', profile['public_goal']],
                ['能力来源', profile['ability_source']],
                ['能力代价', profile['ability_cost']],
              ]
                  .where(
                      (item) => (item[1]?.toString().trim() ?? '').isNotEmpty)
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('${item[0]}：${item[1]}',
                          style: const TextStyle(fontSize: 13, height: 1.4)),
                    ),
                  ),
            ],
            () {
              final rawCustom =
                  json['custom_attributes'] ?? json['customAttributes'];
              final customList = <CustomAttributeItem>[];
              if (rawCustom is List) {
                for (final c in rawCustom) {
                  if (c is Map<String, dynamic>) {
                    customList.add(CustomAttributeItem.fromJson(c));
                  } else if (c is Map) {
                    customList.add(CustomAttributeItem.fromJson(
                        Map<String, dynamic>.from(c)));
                  }
                }
              }
              if (customList.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const Text('自添加项',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.teal)),
                  const SizedBox(height: 8),
                  ...customList.map((attr) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: attr.importance ==
                                  CustomAttributeImportance.critical
                              ? attr.importance.color.withValues(alpha: 0.4)
                              : Theme.of(ctx)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  attr.importance.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: attr.importance.color
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(attr.importance.icon,
                                    size: 12, color: attr.importance.color),
                                const SizedBox(width: 4),
                                Text(
                                  attr.importance.label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: attr.importance.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  attr.name,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (attr.value.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    attr.value,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(ctx)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              );
            }(),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    showEdit(context, item, onChanged, mode: mode);
                  },
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('编辑')),
              OutlinedButton.icon(
                  onPressed: () async {
                    final crud =
                        ProviderScope.containerOf(context, listen: false)
                            .read(resourceCrudControllerProvider);
                    final confirm = await showDialog<bool>(
                      context: ctx,
                      builder: (c) => AlertDialog(
                        title: const Text('确认删除'),
                        content: Text('确定要删除角色卡「${item['name']}」吗？'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('取消')),
                          TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('删除',
                                  style: TextStyle(color: AppColors.error))),
                        ],
                      ),
                    );
                    if (confirm != true) return;
                    final result = await crud
                        .deleteCharacterCard(item['id'] as String, mode: mode);
                    if (!result.success) {
                      debugPrint(
                          '[WorldviewEditor] 删除角色卡失败: ${result.errorMessage}');
                      if (ctx.mounted) {
                        AppFeedback.error(
                            ctx, '删除角色卡失败: ${result.errorMessage}');
                      }
                      return;
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    onChanged();
                  },
                  icon: const Icon(Icons.delete, size: 16),
                  label: const Text('删除', style: TextStyle(color: Colors.red))),
            ]),
          ])),
    );
  }

  /// AI 导入角色卡弹窗
  static void showAiImport(BuildContext context, VoidCallback onChanged,
      List<Map<String, dynamic>> worldviewItems,
      {List<Map<String, dynamic>> characterCards = const [],
      String detailInstruction = '',
      AiGenerationDepth aiDepth = AiGenerationDepth.simple,
      String? initialWorldviewId,
      ResourceLibraryMode mode = ResourceLibraryMode.adventure}) {
    ProviderScope.containerOf(context, listen: false)
        .read(resourceCardImportControllerProvider)
        .reset();
    showFormSubPage<void>(
      context: context,
      title: 'AI 助手创作角色卡',
      maxWidth: 840,
      builder: (_) => ResourceCardAiImportPage(
        kind: ResourceCardImportKind.character,
        worldviews: worldviewItems,
        characterCards: characterCards,
        detailInstruction: detailInstruction,
        aiDepth: aiDepth,
        initialWorldviewId: initialWorldviewId,
        mode: mode,
        onChanged: onChanged,
      ),
    );
  }

  /// 角色卡列表
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
          Icon(Icons.person, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(mode.emptyTitle, style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 4),
          Text(mode.emptySubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[400])),
          const SizedBox(height: 8),
          FilledButton.icon(
              onPressed: () => showEdit(context, null, onChanged, mode: mode),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('创建角色卡')),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        final name = item['name'] as String? ?? '';
        final source = item['source'] as String? ?? '';
        final matchingWvId = item['matching_worldview_id'] as String? ?? '';
        final crud = ProviderScope.containerOf(context, listen: false)
            .read(resourceCrudControllerProvider);
        final json = crud.decodeCardData(item);
        final personality = json['personality'] as String? ?? '';
        final weights = crud.decodeWeights(item);
        String matchingWvName = '';
        if (matchingWvId.isNotEmpty) {
          final wv =
              worldviewItems.where((w) => w['id'] == matchingWvId).firstOrNull;
          matchingWvName = wv?['name'] as String? ?? '';
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: AppColors.teal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4)),
                  child: Text(source,
                      style:
                          const TextStyle(fontSize: 10, color: AppColors.teal)),
                ),
            ]),
            subtitle:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (personality.isNotEmpty)
                Text(personality,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[600], height: 1.4)),
              if (weights.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: weights
                          .map((w) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                    color: AppColors.accent
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(3)),
                                child: Text(w,
                                    style: const TextStyle(
                                        fontSize: 9, color: AppColors.accent)),
                              ))
                          .toList()),
                ),
              if (matchingWvName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('契合：$matchingWvName',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.accent)),
                ),
              Text(
                  formatTimestamp(item['updated_at'] as String? ??
                      item['created_at'] as String?),
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textSecondary)),
            ]),
            leading: const Icon(Icons.person, color: AppColors.teal),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                  onPressed: () =>
                      showEdit(context, item, onChanged, mode: mode),
                  icon: const Icon(Icons.edit, size: 18),
                  tooltip: '编辑',
                  visualDensity: VisualDensity.compact),
              IconButton(
                  onPressed: () async {
                    final crud =
                        ProviderScope.containerOf(context, listen: false)
                            .read(resourceCrudControllerProvider);
                    final confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                                title: const Text('确认删除'),
                                content: Text('确定要删除角色卡「$name」吗？'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('取消')),
                                  TextButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text('删除',
                                          style: TextStyle(
                                              color: AppColors.error))),
                                ]));
                    if (confirm != true) return;
                    final result = await crud
                        .deleteCharacterCard(item['id'] as String, mode: mode);
                    if (!result.success) {
                      debugPrint(
                          '[WorldviewEditor] 删除角色卡失败: ${result.errorMessage}');
                      if (context.mounted) {
                        AppFeedback.error(
                            context, '删除角色卡失败: ${result.errorMessage}');
                      }
                      return;
                    }
                    onChanged();
                  },
                  icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                  tooltip: '删除',
                  visualDensity: VisualDensity.compact),
            ]),
            onTap: () => showDetail(context, item, onChanged, mode: mode),
          ),
        );
      },
    );
  }
}
