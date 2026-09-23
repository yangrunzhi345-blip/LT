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
import '../../core/widgets/app_confirm_dialog.dart';
import '../../application/resource_library/import_models.dart';
import '../../models/resource_provenance.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/generated/app_localizations_zh.dart';
import 'resource_card_ai_import_page.dart';
import 'resource_operation_feedback.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

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
    final l10n = _l10n(context);
    final json =
        StructuredJsonCodec.tryDecodeStoredObject(item['json_data']) ?? {};
    final profile = json['world_profile'] is Map
        ? json['world_profile'] as Map
        : const <String, dynamic>{};
    showFormSubPage<void>(
      context: context,
      title: l10n.characterCardDetailTitle,
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
              Text(l10n.characterPersonalityTraits,
                  style: const TextStyle(
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
              Text(l10n.characterDescription,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.teal)),
              const SizedBox(height: 6),
              Text(json['description'] as String,
                  style: const TextStyle(fontSize: 14, height: 1.5)),
            ],
            if (profile.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(l10n.inWorldSettingSection,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.teal)),
              const SizedBox(height: 6),
              ...[
                [l10n.factionLabel, profile['faction']],
                [l10n.locationLabel, profile['home_location']],
                [l10n.publicGoalLabel, profile['public_goal']],
                [l10n.abilitySourceLabel, profile['ability_source']],
                [l10n.abilityCostLabel, profile['ability_cost']],
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
                  Text(l10n.characterCustomFields,
                      style: const TextStyle(
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
                              : Colors.transparent,
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
                                  attr.importance.color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              attr.importance.localizedLabel(l10n),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: attr.importance.color,
                              ),
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
                                if (attr.description != null &&
                                    attr.description!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    attr.description!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.grey[500],
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
                  label: Text(l10n.editAction)),
              OutlinedButton.icon(
                  onPressed: () async {
                    final crud =
                        ProviderScope.containerOf(context, listen: false)
                            .read(resourceCrudControllerProvider);
                    final confirm = await AppConfirmDialog.show(
                      context: ctx,
                      title: l10n.characterCardConfirmDeleteTitle,
                      message: l10n.characterCardConfirmDeleteMessage(
                          item['name'] ?? ''),
                      confirmLabel: l10n.deleteAction,
                      isDanger: true,
                      icon: Icons.delete_outline_rounded,
                    );
                    if (!confirm) return;
                    final result = await crud
                        .deleteCharacterCard(item['id'] as String, mode: mode);
                    if (!result.success) {
                      debugPrint(
                          '[WorldviewEditor] 删除角色卡失败: ${result.errorMessage}');
                      if (ctx.mounted) {
                        AppFeedback.error(
                            ctx,
                            l10n.characterCardDeleteFailed(
                                result.errorMessage ?? ''));
                      }
                      return;
                    }
                    if (ctx.mounted) {
                      showResourceOperationSuccess(ctx, result, l10n);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    onChanged();
                  },
                  icon: const Icon(Icons.delete, size: 16),
                  label: Text(l10n.deleteAction,
                      style: const TextStyle(color: Colors.red))),
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
    final l10n = _l10n(context);
    ProviderScope.containerOf(context, listen: false)
        .read(resourceCardImportControllerProvider)
        .reset();
    showFormSubPage<void>(
      context: context,
      title: l10n.characterAiAssistantCreateTitle,
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
    final l10n = _l10n(context);
    if (items.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.person, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(mode.localizedEmptyTitle(l10n),
              style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 4),
          Text(mode.localizedEmptySubtitle(l10n),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[400])),
          const SizedBox(height: 8),
          FilledButton.icon(
              onPressed: () => showEdit(context, null, onChanged, mode: mode),
              icon: const Icon(Icons.add, size: 16),
              label: Text(l10n.characterCreateAction)),
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
                  child: Text(l10n.characterMatchWorldview(matchingWvName),
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
                  tooltip: l10n.editAction,
                  visualDensity: VisualDensity.compact),
              IconButton(
                  onPressed: () async {
                    final crud =
                        ProviderScope.containerOf(context, listen: false)
                            .read(resourceCrudControllerProvider);
                    final confirm = await AppConfirmDialog.show(
                        context: context,
                        title: l10n.characterCardConfirmDeleteTitle,
                        message: l10n.characterCardConfirmDeleteMessage(name),
                        confirmLabel: l10n.deleteAction,
                        isDanger: true,
                        icon: Icons.delete_outline_rounded);
                    if (!confirm) return;
                    final result = await crud
                        .deleteCharacterCard(item['id'] as String, mode: mode);
                    if (!result.success) {
                      debugPrint(
                          '[WorldviewEditor] 删除角色卡失败: ${result.errorMessage}');
                      if (context.mounted) {
                        AppFeedback.error(
                            context,
                            l10n.characterCardDeleteFailed(
                                result.errorMessage ?? ''));
                      }
                      return;
                    }
                    if (context.mounted) {
                      showResourceOperationSuccess(context, result, l10n);
                    }
                    onChanged();
                  },
                  icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                  tooltip: l10n.deleteAction,
                  visualDensity: VisualDensity.compact),
            ]),
            onTap: () => showDetail(context, item, onChanged, mode: mode),
          ),
        );
      },
    );
  }
}
