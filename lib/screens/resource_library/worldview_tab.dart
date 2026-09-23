import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import '../../providers/riverpod_providers.dart';
import '../../core/config/generation_limits.dart';
import '../../models/resource_library_mode.dart';
import '../../widgets/narr_aitor_loading.dart';
import '../../core/widgets/form_sub_page_scaffold.dart';
import '../../core/theme/app_colors.dart';
import '../../utils/time_format.dart';
import '../../models/worldview_details.dart';
import '../../core/feedback/app_feedback.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import '../../application/resource_library/edit_drafts.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/generated/app_localizations_zh.dart';
import 'worldview_ai_import_page.dart';
import 'resource_operation_feedback.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// 世界观列表 + 手动编辑子页面 + AI 导入子页面
class WorldviewTab {
  /// 手动创建/编辑世界观子页面。
  static Future<void> showEdit(BuildContext context,
      Map<String, dynamic>? existing, VoidCallback onChanged,
      {ResourceLibraryMode mode = ResourceLibraryMode.adventure,
      WorldviewEditingMode editingMode = WorldviewEditingMode.simple}) async {
    final l10n = _l10n(context);
    final draft =
        WorldviewEditDraft.fromExisting(existing, editingMode: editingMode);
    final nameCtrl = TextEditingController(text: draft.name);
    final descCtrl = TextEditingController(text: draft.description);
    final effectiveEditingMode = draft.mode;
    final moduleCtrls = <String, TextEditingController>{
      for (final key
          in WorldviewDetails.moduleKeys.where((key) => key != 'overview'))
        key: TextEditingController(text: draft.moduleTexts[key] ?? ''),
    };
    String? validationError;

    final sheet = showFormSubPage<void>(
      context: context,
      title: existing == null
          ? l10n.worldviewCreateTitle
          : l10n.worldviewEditTitle,
      maxWidth: 760,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 24,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            effectiveEditingMode ==
                                    WorldviewEditingMode.detailed
                                ? l10n.worldviewDetailedTitle
                                : l10n.worldviewInfoSection,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 16),
                        TextField(
                            controller: nameCtrl,
                            decoration: InputDecoration(
                                labelText: l10n.nameLabel,
                                border: const OutlineInputBorder())),
                        const SizedBox(height: 12),
                        TextField(
                            controller: descCtrl,
                            maxLines: effectiveEditingMode ==
                                    WorldviewEditingMode.detailed
                                ? 4
                                : 6,
                            decoration: InputDecoration(
                                labelText: effectiveEditingMode ==
                                        WorldviewEditingMode.detailed
                                    ? l10n.worldviewOverviewDetailed
                                    : l10n.worldviewOverviewConcise,
                                alignLabelWithHint: true,
                                border: const OutlineInputBorder())),
                        const SizedBox(height: 12),
                        if (effectiveEditingMode ==
                            WorldviewEditingMode.detailed) ...[
                          Text(
                              l10n.worldviewDetailedLimitTip(GenerationLimits
                                  .detailedWorldviewMaximumCharacters),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          ...moduleCtrls.entries.map((entry) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: TextField(
                                  controller: entry.value,
                                  maxLines: 4,
                                  decoration: InputDecoration(
                                    labelText:
                                        worldViewModuleLabel(entry.key, l10n),
                                    alignLabelWithHint: true,
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              )),
                        ],
                        if (validationError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(validationError!,
                                style: const TextStyle(
                                    color: Colors.red, fontSize: 12)),
                          ),
                        const SizedBox(height: 16),
                        Row(children: [
                          if (existing != null)
                            TextButton(
                                onPressed: () async {
                                  final crud = ProviderScope.containerOf(
                                          context,
                                          listen: false)
                                      .read(resourceCrudControllerProvider);
                                  final confirm = await AppConfirmDialog.show(
                                    context: ctx,
                                    title: l10n.characterCardConfirmDeleteTitle,
                                    message: l10n.worldviewConfirmDeleteMessage(
                                        existing['name'] ?? ''),
                                    confirmLabel: l10n.deleteAction,
                                    isDanger: true,
                                    icon: Icons.delete_outline_rounded,
                                  );
                                  if (!confirm) return;
                                  final result =
                                      await crud.deleteWorldviewPreset(
                                    existing['id'] as String,
                                    mode: mode,
                                  );
                                  if (!result.success) {
                                    debugPrint(
                                        '[WorldviewEditor] 删除世界观失败: ${result.errorMessage}');
                                    if (ctx.mounted) {
                                      AppFeedback.error(
                                          ctx, l10n.worldviewDeleteFailed);
                                    }
                                    return;
                                  }
                                  if (ctx.mounted) {
                                    showResourceOperationSuccess(
                                      ctx,
                                      result,
                                      l10n,
                                    );
                                  }
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  onChanged();
                                },
                                child: Text(l10n.deleteAction,
                                    style: const TextStyle(color: Colors.red))),
                          const Spacer(),
                          TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(l10n.cancelAction)),
                          const SizedBox(width: 8),
                          FilledButton(
                              onPressed: () async {
                                final name = nameCtrl.text.trim();
                                if (name.isEmpty) return;
                                draft.name = name;
                                draft.description = descCtrl.text.trim();
                                for (final entry in moduleCtrls.entries) {
                                  draft.moduleTexts[entry.key] =
                                      entry.value.text.trim();
                                }
                                final result = await ProviderScope.containerOf(
                                        context,
                                        listen: false)
                                    .read(resourceCrudControllerProvider)
                                    .saveWorldviewDraft(draft, mode: mode);
                                if (!result.success) {
                                  debugPrint(
                                      '[WorldviewEditor] 保存世界观失败: ${result.errorMessage}');
                                  if (ctx.mounted) {
                                    setSheetState(() => validationError =
                                        l10n.characterCardSaveFailed(
                                            result.errorMessage ?? ''));
                                  }
                                  return;
                                }
                                if (ctx.mounted) Navigator.pop(ctx);
                                onChanged();
                              },
                              child: Text(l10n.saveAction)),
                        ]),
                      ]),
                ),
              )),
    );
    await sheet.whenComplete(() {
      nameCtrl.dispose();
      descCtrl.dispose();
      for (final controller in moduleCtrls.values) {
        controller.dispose();
      }
    });
  }

  /// AI 导入世界观弹窗
  static void showAiImport(BuildContext context, VoidCallback onChanged,
      List<Map<String, dynamic>> worldviewList,
      {ResourceLibraryMode mode = ResourceLibraryMode.adventure}) {
    final l10n = _l10n(context);
    ProviderScope.containerOf(context, listen: false)
        .read(resourceLibraryImportControllerProvider)
        .reset();
    showFormSubPage<void>(
      context: context,
      title: l10n.worldviewAiAssistantTitle,
      maxWidth: 840,
      builder: (_) => WorldviewAiImportPage(
        mode: mode,
        onChanged: onChanged,
      ),
    );
  }

  /// 世界观列表
  static Widget buildList(bool loading, List<Map<String, dynamic>> items,
      BuildContext context, VoidCallback onChanged,
      {ResourceLibraryMode mode = ResourceLibraryMode.adventure,
      WorldviewEditingMode editingMode = WorldviewEditingMode.simple}) {
    if (loading) return const NarrAItorLoading.normal();
    final l10n = _l10n(context);
    if (items.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.public, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(mode.localizedEmptyTitle(l10n),
              style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 4),
          Text(mode.localizedEmptySubtitle(l10n),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[400])),
          const SizedBox(height: 8),
          FilledButton.icon(
              onPressed: () => showEdit(context, null, onChanged,
                  mode: mode, editingMode: editingMode),
              icon: const Icon(Icons.add, size: 16),
              label: Text(l10n.worldviewCreateAction)),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        final name = item['name'] as String? ?? '';
        final desc = item['description'] as String? ?? '';
        final source = item['source'] as String? ?? '';
        final details = WorldviewDetails.fromJson(
            WorldviewEditDraft.decodeDetailJson(item['detail_json']),
            fallbackDescription: desc);
        final modeLabel = details.mode == WorldviewEditingMode.detailed
            ? l10n.worldviewDetailedTitle
            : l10n.worldviewConciseTitle;
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
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4)),
                child: Text(modeLabel,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.primary)),
              ),
            ]),
            subtitle:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (desc.isNotEmpty)
                Text(desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[600], height: 1.4)),
              Text(
                  formatTimestamp(item['updated_at'] as String? ??
                      item['created_at'] as String?),
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textSecondary)),
            ]),
            leading: const Icon(Icons.public, color: AppColors.teal),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showEdit(context, item, onChanged,
                mode: mode, editingMode: editingMode),
          ),
        );
      },
    );
  }
}
