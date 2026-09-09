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
  final AiGenerationDepth aiDepth;
  final String? initialWorldviewId;
  final ResourceLibraryMode mode;
  final VoidCallback onChanged;

  const ResourceCardAiImportPage({
    super.key,
    required this.kind,
    required this.worldviews,
    required this.characterCards,
    required this.detailInstruction,
    required this.aiDepth,
    this.initialWorldviewId,
    required this.mode,
    required this.onChanged,
  });

  @override
  ConsumerState<ResourceCardAiImportPage> createState() =>
      _ResourceCardAiImportPageState();
}

class _ResourceCardAiImportPageState
    extends ConsumerState<ResourceCardAiImportPage> {
  final TextEditingController _source = TextEditingController();
  String? _worldviewId;
  final Set<String> _selectedIds = {};
  bool _autoSave = true;

  ResourceCardImportController get _controller =>
      ref.read(resourceCardImportControllerProvider);

  bool get _busy =>
      _controller.phase == ResourceCardImportPhase.generating ||
      _controller.phase == ResourceCardImportPhase.saving;

  @override
  void initState() {
    super.initState();
    _worldviewId = widget.initialWorldviewId;
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _scopedCards =>
      WorldviewCharacterScopePolicy.filterSceneResources(
        widget.characterCards,
        _worldviewId,
      );

  List<Map<String, String>> _associatedCharacters() =>
      _controller.associatedCharactersFor(
        cards: _scopedCards,
        selectedIds: _selectedIds,
      );

  @override
  Widget build(BuildContext context) {
    ref.watch(resourceCardImportControllerProvider);
    final error = _controller.errorMessage;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Worldview dropdown (optional)
            if (widget.worldviews.isNotEmpty) ...[
              NarrAItorDropdown<String>(
                value: _worldviewId,
                label: '关联世界观（可选）',
                enabled: !_busy,
                options: [
                  const NarrAItorDropdownOption(value: null, label: '不指定'),
                  ...widget.worldviews.map((item) => NarrAItorDropdownOption(
                        value: item['id']?.toString(),
                        label: item['name']?.toString() ?? '未命名世界观',
                      ))
                ],
                onChanged: (value) => setState(() {
                  _worldviewId = value;
                  // Remove selections that are no longer valid for the new scope
                  final ids = _scopedCards
                      .map((e) => e['id']?.toString() ?? '')
                      .toSet();
                  _selectedIds.removeWhere((id) => !ids.contains(id));
                }),
              ),
              const SizedBox(height: 12),
            ],
            // Existing characters multi‑select
            NarrAItorMultiSelectDropdown<String>(
              values: _selectedIds,
              label: '关联已有角色（可选）',
              emptyText: '暂无已有角色卡',
              selectedBuilder: (values) =>
                  values.isEmpty ? '不指定' : '已选 ${values.length} 个角色',
              options: _scopedCards
                  .map((card) => NarrAItorDropdownOption(
                        value: card['id']?.toString() ?? '',
                        label: card['name']?.toString() ?? '未命名角色',
                      ))
                  .toList(),
              onChanged: _busy
                  ? null
                  : (values) => setState(() {
                        _selectedIds
                          ..clear()
                          ..addAll(values);
                      }),
            ),
            const SizedBox(height: 12),
            // Source text field
            TextField(
              controller: _source,
              minLines: 8,
              maxLines: 16,
              enabled: !_busy,
              decoration: const InputDecoration(
                hintText: '在此粘贴角色或 NPC 原文……',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // Progress display
            if (_busy && _controller.progressStage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _controller.progressStage!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            // Error display
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 12)),
              ),
            // Auto‑save toggle
            SwitchListTile(
              title: const Text('自动保存到资料库'),
              value: _autoSave,
              onChanged: (v) => setState(() => _autoSave = v),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _generate,
                  child: Text(_busy ? '正在生成…' : 'AI 解析'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generate() async {
    final selectedWorldview = widget.worldviews.firstWhere(
        (item) => item['id']?.toString() == _worldviewId,
        orElse: () => {});
    await _controller.generate(
      ResourceCardImportRequest(
        kind: widget.kind,
        source: _source.text,
        worldview: selectedWorldview['description']?.toString() ?? '',
        worldviewId: _worldviewId ?? '',
        associatedCharacters: _associatedCharacters(),
        detailInstruction: widget.detailInstruction,
        aiDepth: widget.aiDepth,
        libraryMode: widget.mode,
      ),
      runInBackground: _autoSave,
    );

    // If auto‑save completed, exit early.
    if (mounted && _controller.phase == ResourceCardImportPhase.completed) {
      Navigator.pop(context);
      widget.onChanged();
      return;
    }

    if (!mounted || _controller.phase != ResourceCardImportPhase.reviewing) {
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.kind == ResourceCardImportKind.character
            ? '确认导入角色卡'
            : '确认导入 NPC'),
        content: SingleChildScrollView(child: _preview(_controller.draft!)),
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
    final saved = await _controller.save(widget.mode);
    if (!mounted || saved == null) return;
    Navigator.pop(context);
    widget.onChanged();
  }

  Widget _preview(ResourceCardImportDraft draft) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < draft.items.length; i++) ...[
          if (i > 0) const Divider(height: 28),
          Text(
            draft.items[i]['name']?.toString() ?? '未命名',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...draft.items[i].entries
              .where((e) => e.key != 'name' && e.key != 'world_profile')
              .map((e) => _previewField(e.key, e.value)),
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
}
