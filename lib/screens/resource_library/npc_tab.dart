import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import '../../widgets/narr_aitor_loading.dart';
import '../../providers/riverpod_providers.dart';
import '../../models/resource_library_mode.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/form_sub_page_scaffold.dart';
import '../../core/widgets/narr_aitor_dropdown.dart';
import '../../utils/time_format.dart';
import '../../core/feedback/app_feedback.dart';
import '../../application/resource_library/import_models.dart';
import '../../application/resource_library/edit_drafts.dart';
import 'resource_card_ai_import_page.dart';

/// NPC 列表 + 编辑子页面 + JSON 导入 + AI 导入子页面
class NpcTab {
  /// 手动创建/编辑 NPC 子页面。
  static Future<void> showEdit(
      BuildContext context,
      Map<String, dynamic>? existing,
      VoidCallback onChanged,
      List<Map<String, dynamic>> worldviewItems,
      {ResourceLibraryMode mode = ResourceLibraryMode.adventure}) async {
    final draft = NpcEditDraft.fromExisting(existing);
    final nameCtrl = TextEditingController(text: draft.name);
    final ageCtrl = TextEditingController(text: draft.age);
    final profCtrl = TextEditingController(text: draft.profession);
    final persCtrl = TextEditingController(text: draft.personality);
    final appearCtrl = TextEditingController(text: draft.appearance);
    String gender = draft.gender;
    String worldviewId = draft.worldviewId;
    final sheet = showFormSubPage<void>(
      context: context,
      title: existing == null ? '新建 NPC' : '编辑 NPC',
      maxWidth: 760,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header — matching character card dialog style
                Row(children: [
                  Icon(existing == null ? Icons.person_add : Icons.edit,
                      size: 20, color: AppColors.accent),
                  const SizedBox(width: 8),
                  const Text('NPC 信息',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 16),
                // Form fields — wrapped in Flexible+SingleChildScrollView matching char card
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                        controller: nameCtrl,
                        scrollPadding: const EdgeInsets.only(bottom: 120),
                        decoration: const InputDecoration(
                            labelText: '姓名 *',
                            border: OutlineInputBorder(),
                            isDense: true),
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Flexible(
                          child: NarrAItorDropdown<String>(
                            value: gender,
                            label: '性别',
                            options: ['男', '女', '其他']
                                .map((g) =>
                                    NarrAItorDropdownOption(value: g, label: g))
                                .toList(),
                            onChanged: (v) =>
                                setSheetState(() => gender = v ?? '男'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: TextField(
                            controller: ageCtrl,
                            scrollPadding: const EdgeInsets.only(bottom: 120),
                            decoration: const InputDecoration(
                                labelText: '年龄',
                                border: OutlineInputBorder(),
                                isDense: true),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      TextField(
                        controller: profCtrl,
                        scrollPadding: const EdgeInsets.only(bottom: 120),
                        decoration: const InputDecoration(
                            labelText: '职业/身份',
                            border: OutlineInputBorder(),
                            isDense: true),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: persCtrl,
                        scrollPadding: const EdgeInsets.only(bottom: 120),
                        decoration: const InputDecoration(
                            labelText: '性格',
                            border: OutlineInputBorder(),
                            isDense: true),
                        maxLines: 3,
                        minLines: 2,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: appearCtrl,
                        scrollPadding: const EdgeInsets.only(bottom: 120),
                        decoration: const InputDecoration(
                            labelText: '外貌描述',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(),
                            isDense: true),
                        maxLines: 3,
                        minLines: 2,
                      ),
                      const SizedBox(height: 10),
                      NarrAItorDropdown<String>(
                        value: worldviewId.isEmpty ? null : worldviewId,
                        label: '契合世界观（可选）',
                        options: [
                          const NarrAItorDropdownOption(
                              value: null, label: '无'),
                          ...worldviewItems.map((wv) => NarrAItorDropdownOption(
                              value: wv['id'] as String,
                              label: wv['name'] as String? ?? '')),
                        ],
                        onChanged: (v) =>
                            setSheetState(() => worldviewId = v ?? ''),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  if (existing != null)
                    TextButton(
                      onPressed: () async {
                        final crud =
                            ProviderScope.containerOf(context, listen: false)
                                .read(resourceCrudControllerProvider);
                        final confirm = await showDialog<bool>(
                            context: ctx,
                            builder: (c) => AlertDialog(
                                    title: const Text('确认删除'),
                                    content:
                                        Text('确定要删除 NPC「${nameCtrl.text}」吗？'),
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
                        final result = await crud.deleteNpcCard(
                            existing['id'] as String,
                            mode: mode);
                        if (!result.success) {
                          debugPrint(
                              '[WorldviewEditor] 删除NPC失败: ${result.errorMessage}');
                          if (ctx.mounted) {
                            AppFeedback.error(ctx, '删除 NPC 失败，请重试');
                          }
                          return;
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        onChanged();
                      },
                      child: const Text('删除',
                          style: TextStyle(color: AppColors.error)),
                    ),
                  const Spacer(),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('取消')),
                  const SizedBox(width: 8),
                  FilledButton(
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) return;
                        draft.name = name;
                        draft.gender = gender;
                        draft.age = ageCtrl.text.trim();
                        draft.profession = profCtrl.text.trim();
                        draft.personality = persCtrl.text.trim();
                        draft.appearance = appearCtrl.text.trim();
                        draft.worldviewId = worldviewId;
                        final result = await ProviderScope.containerOf(context,
                                listen: false)
                            .read(resourceCrudControllerProvider)
                            .saveNpcDraft(draft, mode: mode);
                        if (!result.success) {
                          debugPrint(
                              '[NpcTab] 保存NPC失败: ${result.errorMessage}');
                          if (ctx.mounted) {
                            AppFeedback.error(
                                ctx, '保存失败：${result.errorMessage}');
                          }
                          return;
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        onChanged();
                      },
                      child: Text(existing != null ? '保存' : '创建')),
                ]),
              ]),
        ),
      ),
    );
    await sheet.whenComplete(() {
      for (final c in [nameCtrl, ageCtrl, profCtrl, persCtrl, appearCtrl]) {
        c.dispose();
      }
    });
  }

  /// AI 导入 NPC 弹窗
  static void showAiImport(BuildContext context, VoidCallback onChanged,
      List<Map<String, dynamic>> worldviewItems,
      {List<Map<String, dynamic>> characterCards = const [],
      String detailInstruction = '',
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
