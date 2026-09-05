import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;

import '../../application/resource_library/edit_drafts.dart';
import '../../core/feedback/app_feedback.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/custom_attribute_editor_section.dart';
import '../../core/widgets/form_sub_page_scaffold.dart';
import '../../core/widgets/narr_aitor_dropdown.dart';
import '../../models/custom_attribute_item.dart';
import '../../models/resource_library_mode.dart';
import '../../providers/riverpod_providers.dart';

/// 新建/编辑 NPC 页面
Future<void> showNpcEditPage(
  BuildContext context, {
  Map<String, dynamic>? existing,
  required VoidCallback onChanged,
  required List<Map<String, dynamic>> worldviewItems,
  ResourceLibraryMode mode = ResourceLibraryMode.adventure,
}) {
  return showFormSubPage<void>(
    context: context,
    title: existing == null ? '新建 NPC' : '编辑 NPC',
    maxWidth: 760,
    builder: (ctx) => NpcEditPage(
      existing: existing,
      onChanged: onChanged,
      worldviewItems: worldviewItems,
      mode: mode,
    ),
  );
}

class NpcEditPage extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final VoidCallback onChanged;
  final List<Map<String, dynamic>> worldviewItems;
  final ResourceLibraryMode mode;

  const NpcEditPage({
    super.key,
    required this.existing,
    required this.onChanged,
    required this.worldviewItems,
    this.mode = ResourceLibraryMode.adventure,
  });

  @override
  State<NpcEditPage> createState() => _NpcEditPageState();
}

class _NpcEditPageState extends State<NpcEditPage> {
  late final NpcEditDraft draft;
  late final TextEditingController nameCtrl;
  late final TextEditingController ageCtrl;
  late final TextEditingController profCtrl;
  late final TextEditingController persCtrl;
  late final TextEditingController appearCtrl;

  late String gender;
  late String worldviewId;
  late List<CustomAttributeItem> customAttributes;

  @override
  void initState() {
    super.initState();
    draft = NpcEditDraft.fromExisting(widget.existing);
    nameCtrl = TextEditingController(text: draft.name);
    ageCtrl = TextEditingController(text: draft.age);
    profCtrl = TextEditingController(text: draft.profession);
    persCtrl = TextEditingController(text: draft.personality);
    appearCtrl = TextEditingController(text: draft.appearance);
    gender = draft.gender;
    worldviewId = draft.worldviewId;
    customAttributes = List.from(draft.customAttributes);
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    ageCtrl.dispose();
    profCtrl.dispose();
    persCtrl.dispose();
    appearCtrl.dispose();
    super.dispose();
  }

  Future<void> _deleteNpc() async {
    final crud = ProviderScope.containerOf(context, listen: false)
        .read(resourceCrudControllerProvider);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 NPC「${nameCtrl.text.trim()}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('删除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final result = await crud.deleteNpcCard(
      widget.existing!['id'] as String,
      mode: widget.mode,
    );
    if (!result.success) {
      debugPrint('[NpcEditPage] 删除NPC失败: ${result.errorMessage}');
      if (mounted) {
        AppFeedback.error(context, '删除 NPC 失败，请重试');
      }
      return;
    }
    if (mounted) Navigator.pop(context);
    widget.onChanged();
  }

  Future<void> _saveNpc() async {
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    draft.name = name;
    draft.gender = gender;
    draft.age = ageCtrl.text.trim();
    draft.profession = profCtrl.text.trim();
    draft.personality = persCtrl.text.trim();
    draft.appearance = appearCtrl.text.trim();
    draft.worldviewId = worldviewId;
    draft.customAttributes = customAttributes;
    final result = await ProviderScope.containerOf(context, listen: false)
        .read(resourceCrudControllerProvider)
        .saveNpcDraft(draft, mode: widget.mode);
    if (!result.success) {
      debugPrint('[NpcEditPage] 保存NPC失败: ${result.errorMessage}');
      if (mounted) {
        AppFeedback.error(context, '保存失败：${result.errorMessage}');
      }
      return;
    }
    if (mounted) Navigator.pop(context);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(children: [
              Icon(widget.existing == null ? Icons.person_add : Icons.edit,
                  size: 20, color: AppColors.accent),
              const SizedBox(width: 8),
              const Text('NPC 信息',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 16),
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
              Expanded(
                child: NarrAItorDropdown<String>(
                  value: gender,
                  label: '性别',
                  options: ['男', '女', '其他']
                      .map((g) => NarrAItorDropdownOption(value: g, label: g))
                      .toList(),
                  onChanged: (v) => setState(() => gender = v ?? '男'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
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
                const NarrAItorDropdownOption(value: null, label: '无'),
                ...widget.worldviewItems.map((wv) => NarrAItorDropdownOption(
                    value: wv['id'] as String,
                    label: wv['name'] as String? ?? '')),
              ],
              onChanged: (v) => setState(() => worldviewId = v ?? ''),
            ),
            const SizedBox(height: 16),
            CustomAttributeEditorSection(
              initialItems: customAttributes,
              onChanged: (items) {
                customAttributes = items;
              },
            ),
            const SizedBox(height: 20),
            Row(children: [
              if (widget.existing != null)
                TextButton(
                  onPressed: _deleteNpc,
                  child: const Text('删除',
                      style: TextStyle(color: AppColors.error)),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saveNpc,
                child: Text(widget.existing != null ? '保存' : '创建'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
