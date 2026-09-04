
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/resource_library/import_models.dart';
import '../../controllers/resource_card_import_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/narr_aitor_dropdown.dart';
import '../../models/resource_library_mode.dart';
import '../../providers/riverpod_providers.dart';
import '../../core/utils/worldview_character_scope_policy.dart';

class ResourceCardAiImportPage extends ConsumerStatefulWidget {
  final ResourceCardImportKind kind;
  final List<Map<String, dynamic>> worldviews;
  final List<Map<String, dynamic>> characterCards;
  final String detailInstruction;
  final ResourceLibraryMode mode;
  final VoidCallback onChanged;

  const ResourceCardAiImportPage({
    super.key,
    required this.kind,
    required this.worldviews,
    required this.characterCards,
    required this.detailInstruction,
    required this.mode,
    required this.onChanged,
  });

  @override
  ConsumerState<ResourceCardAiImportPage> createState() =>
      _ResourceCardAiImportPageState();
}

class _ResourceCardAiImportPageState
    extends ConsumerState<ResourceCardAiImportPage> {
  final _source = TextEditingController();
  String? _worldviewId;
  final Set<String> _selectedIds = {};

  ResourceCardImportController get controller =>
      ref.read(resourceCardImportControllerProvider);

  bool get busy =>
      controller.phase == ResourceCardImportPhase.generating ||
      controller.phase == ResourceCardImportPhase.saving;

  List<Map<String, dynamic>> get scopedCards =>
      WorldviewCharacterScopePolicy.filterSceneResources(
        widget.characterCards,
        _worldviewId,
      );

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  List<Map<String, String>> _associatedCharacters() =>
      controller.associatedCharactersFor(
        cards: scopedCards,
        selectedIds: _selectedIds,
      );

  Future<void> _generate() async {
    final worldview = widget.worldviews
        .where((item) => item['id']?.toString() == _worldviewId)
        .firstOrNull;
    await controller.generate(ResourceCardImportRequest(
      kind: widget.kind,
      source: _source.text,
      worldview: worldview?['description']?.toString() ?? '',
      worldviewId: _worldviewId ?? '',
      associatedCharacters: _associatedCharacters(),
      detailInstruction: widget.detailInstruction,
      libraryMode: widget.mode,
    ));
    if (!mounted || controller.phase != ResourceCardImportPhase.reviewing) {
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.kind == ResourceCardImportKind.character
            ? '确认导入角色卡'
            : '确认导入 NPC'),
        content: SingleChildScrollView(child: _preview(controller.draft!)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('返回修改'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认保存'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) return;
    final saved = await controller.save(widget.mode);
    if (!mounted || saved == null) return;
    Navigator.pop(context);
    widget.onChanged();
  }

  Widget _preview(ResourceCardImportDraft draft) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < draft.items.length; index++) ...[
          if (index > 0) const Divider(height: 28),
          Text(draft.items[index]['name']?.toString() ?? '未命名',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...draft.items[index].entries
              .where((entry) =>
                  entry.key != 'name' && entry.key != 'world_profile')
              .map((entry) => _previewField(entry.key, entry.value)),
        ],
      ],
    );
  }

  Widget _previewField(String key, dynamic value) {
    final text = value is String ? value.trim() : value?.toString() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text('$key：$text', style: const TextStyle(height: 1.35)),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(resourceCardImportControllerProvider);
    final error = controller.errorMessage;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('原文内容', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (widget.worldviews.isNotEmpty) ...[
              NarrAItorDropdown<String>(
                value: _worldviewId,
                label: '关联世界观（可选）',
                enabled: !busy,
                options: [
                  const NarrAItorDropdownOption(value: null, label: '不指定'),
                  ...widget.worldviews.map((item) => NarrAItorDropdownOption(
                        value: item['id']?.toString(),
                        label: item['name']?.toString() ?? '未命名世界观',
                      )),
                ],
                onChanged: (value) => setState(() {
                  _worldviewId = value;
                  final ids = scopedCards
                      .map((item) => item['id']?.toString() ?? '')
                      .toSet();
                  _selectedIds.removeWhere((id) => !ids.contains(id));
                }),
              ),
              const SizedBox(height: 12),
            ],
            NarrAItorMultiSelectDropdown<String>(
              values: _selectedIds,
              label: '关联已有角色（可选）',
              emptyText: '暂无已有角色卡',
              selectedBuilder: (values) =>
                  values.isEmpty ? '不指定' : '已选 ${values.length} 个角色',
              options: scopedCards.map((card) {
                return NarrAItorDropdownOption(
                  value: card['id']?.toString() ?? '',
                  label: card['name']?.toString() ?? '未命名角色',
                );
              }).toList(),
              onChanged: busy
                  ? null
                  : (values) => setState(() {
                        _selectedIds
                          ..clear()
                          ..addAll(values);
                      }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _source,
              enabled: !busy,
              minLines: 8,
              maxLines: 16,
              decoration: const InputDecoration(
                hintText: '在此粘贴角色或 NPC 原文……',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child:
                    Text(error, style: const TextStyle(color: AppColors.error)),
              ),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: busy ? null : _generate,
                  child: Text(busy ? '正在生成…' : 'AI 解析'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
