import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;

import '../../core/widgets/form_sub_page_scaffold.dart';
import '../../core/widgets/narr_aitor_dropdown.dart';
import '../../application/resource_library/import_models.dart';
import '../../models/resource_library_mode.dart';
import '../../models/resource_provenance.dart';
import '../../providers/riverpod_providers.dart';
import '../../core/utils/worldview_character_scope_policy.dart';

enum SceneBatchImportKind { character, npc }

enum SceneImportDetailMode { concise, detailed }

extension SceneImportDetailModeText on SceneImportDetailMode {
  String get label => this == SceneImportDetailMode.concise ? '简洁模式' : '详细模式';

  String get instruction => this == SceneImportDetailMode.concise
      ? '使用简洁模式：保留身份、性格、外貌、核心经历和必要关系，避免扩写。'
      : '使用详细模式：在原文事实范围内完整整理身份、性格、外貌、经历、动机、信息与人物关系。';
}

Future<SceneImportDetailMode?> showSceneImportDetailModePicker(
    BuildContext context) {
  return showDialog<SceneImportDetailMode>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('选择导入模式'),
      content: const Text('请选择本次角色资料的整理粒度。该选择会直接传给 AI。'),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(dialogContext, SceneImportDetailMode.concise),
          child: const Text('简洁模式'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(dialogContext, SceneImportDetailMode.detailed),
          child: const Text('详细模式'),
        ),
      ],
    ),
  );
}

/// Batch import for the legacy scene library. The saved JSON stays compatible
/// with its existing card readers while retaining the relationship summary.
Future<void> showSceneBatchImportPage(
  BuildContext context, {
  required SceneBatchImportKind kind,
  required List<Map<String, dynamic>> worldviews,
  List<Map<String, dynamic>> relationshipCandidates = const [],
  SceneImportDetailMode detailMode = SceneImportDetailMode.detailed,
  required VoidCallback onSaved,
  ResourceLibraryMode mode = ResourceLibraryMode.adventure,
}) {
  return showFormSubPage<void>(
    context: context,
    title: '批量 AI 导入${kind == SceneBatchImportKind.character ? '角色' : 'NPC'}',
    maxWidth: 1040,
    builder: (_) => _SceneBatchImportPage(
      kind: kind,
      worldviews: worldviews,
      relationshipCandidates: relationshipCandidates,
      detailMode: detailMode,
      onSaved: onSaved,
      mode: mode,
    ),
  );
}

class _SceneBatchImportPage extends ConsumerStatefulWidget {
  final SceneBatchImportKind kind;
  final List<Map<String, dynamic>> worldviews;
  final List<Map<String, dynamic>> relationshipCandidates;
  final SceneImportDetailMode detailMode;
  final VoidCallback onSaved;
  final ResourceLibraryMode mode;

  const _SceneBatchImportPage({
    required this.kind,
    required this.worldviews,
    this.relationshipCandidates = const [],
    this.detailMode = SceneImportDetailMode.detailed,
    required this.onSaved,
    required this.mode,
  });

  @override
  ConsumerState<_SceneBatchImportPage> createState() =>
      _SceneBatchImportPageState();
}

class _SceneBatchImportPageState extends ConsumerState<_SceneBatchImportPage> {
  final _source = TextEditingController();
  late final TextEditingController _minimumLength;
  late final TextEditingController _maximumLength;
  String? _worldviewId;
  String? _error;
  var _loading = false;
  final Set<String> _relatedResourceIds = {};

  List<Map<String, dynamic>> get _availableRelationshipCandidates =>
      WorldviewCharacterScopePolicy.filterSceneResources(
        widget.relationshipCandidates,
        _worldviewId,
      );

  void _selectWorldview(String? worldviewId) {
    setState(() {
      _worldviewId = worldviewId;
      final allowedIds = _availableRelationshipCandidates
          .map((item) => item['id']?.toString() ?? '')
          .toSet();
      _relatedResourceIds.removeWhere((id) => !allowedIds.contains(id));
    });
  }

  @override
  void initState() {
    super.initState();
    final npc = widget.kind == SceneBatchImportKind.npc;
    _minimumLength = TextEditingController(text: npc ? '1500' : '3000');
    _maximumLength = TextEditingController(text: npc ? '3000' : '5000');
  }

  @override
  void dispose() {
    _source.dispose();
    _minimumLength.dispose();
    _maximumLength.dispose();
    super.dispose();
  }

  Future<void> _identify() async {
    final source = _source.text.trim();
    if (source.isEmpty || _loading) return;
    final controller = ref.read(sceneBatchImportControllerProvider);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final candidates = await controller.identify(source);
      if (!mounted) return;
      if (controller.errorMessage != null) {
        setState(() => _error = controller.errorMessage);
        return;
      }
      final selected = await _confirmCandidates(candidates);
      if (selected.isNotEmpty) await _import(selected);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Set<String>> _confirmCandidates(List<String> candidates) async {
    final selected = candidates.toSet();
    if (selected.isEmpty) return const {};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Text('是否导入角色（${candidates.length}）？'),
          content: SizedBox(
            width: 520,
            child: ListView(
              shrinkWrap: true,
              children: [
                const Text('识别到的角色（可多选）',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                for (final name in candidates)
                  CheckboxListTile(
                    value: selected.contains(name),
                    title: Text(name),
                    onChanged: (value) => setDialogState(() {
                      if (value == true) {
                        selected.add(name);
                      } else {
                        selected.remove(name);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消')),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: Text('导入 ${selected.length} 个角色'),
            ),
          ],
        ),
      ),
    );
    return confirmed == true ? selected : const {};
  }

  Future<void> _import(Set<String> selectedNames) async {
    final source = _source.text.trim();
    if (source.isEmpty) return;
    final world = widget.worldviews
        .where((item) => item['id'] == _worldviewId)
        .firstOrNull;
    final worldview = world?['description']?.toString() ?? '';
    final importController = ref.read(sceneBatchImportControllerProvider);
    final related = _availableRelationshipCandidates
        .where((item) => _relatedResourceIds.contains(item['id']?.toString()))
        .map(importController.relationshipContextOf)
        .toList(growable: false);
    final minimum = int.tryParse(_minimumLength.text) ?? 0;
    final maximum = int.tryParse(_maximumLength.text) ?? 0;
    final request = SceneBatchImportRequest(
      source: source,
      kind: widget.kind == SceneBatchImportKind.npc ? 'npc' : 'character',
      detailInstruction: widget.detailMode.instruction,
      aiDepth: widget.detailMode == SceneImportDetailMode.detailed
          ? AiGenerationDepth.detailed
          : AiGenerationDepth.simple,
      minimumTotalLength: minimum,
      maximumTotalLength: maximum,
      worldview: worldview,
      worldviewId: _worldviewId ?? '',
      relatedCharacters: related,
      libraryMode: widget.mode,
    );
    final controller = ref.read(sceneBatchImportControllerProvider);
    final saved = await controller.importSelected(request, selectedNames);
    if (!mounted) return;
    if (saved == null) {
      setState(() => _error = controller.errorMessage);
      return;
    }
    final label = widget.kind == SceneBatchImportKind.character ? '角色卡' : 'NPC';
    widget.onSaved();
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已批量导入 $saved 个$label')));
  }

  Future<void> _selectRelatedCharacters() async {
    final selected = await showFormSubPage<Set<String>>(
      context: context,
      title: '关联已有角色',
      maxWidth: 720,
      builder: (_) => _SceneRelationshipPickerPage(
        candidates: _availableRelationshipCandidates,
        selectedIds: _relatedResourceIds,
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _relatedResourceIds
        ..clear()
        ..addAll(selected);
    });
  }

  @override
  Widget build(BuildContext context) {
    final importController = ref.watch(sceneBatchImportControllerProvider);
    final label = widget.kind == SceneBatchImportKind.character ? '角色卡' : 'NPC';
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      children: [
        const Text('提供角色资料',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('AI 会先识别人名，经你确认后逐个生成角色。',
            style: TextStyle(color: Theme.of(context).hintColor)),
        const SizedBox(height: 20),
        if (widget.worldviews.isNotEmpty) ...[
          NarrAItorDropdown<String>(
            value: _worldviewId,
            label: '所属世界观（可选）',
            options: [
              const NarrAItorDropdownOption(value: null, label: '不指定'),
              ...widget.worldviews.map((item) => NarrAItorDropdownOption(
                  value: item['id']?.toString(),
                  label: item['name']?.toString() ?? '未命名世界观')),
            ],
            onChanged: _selectWorldview,
          ),
          const SizedBox(height: 16),
        ],
        const SizedBox(height: 18),
        Text('关联角色（可选)', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _availableRelationshipCandidates.isEmpty
              ? null
              : _selectRelatedCharacters,
          icon: const Icon(Icons.group_add_outlined),
          label: Text(_relatedResourceIds.isEmpty
              ? _worldviewId == null
                  ? '请先选择世界观'
                  : '选择关联角色'
              : '已关联 ${_relatedResourceIds.length} 个角色'),
        ),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _minimumLength,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: '最少总字数', border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _maximumLength,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: '最多总字数', border: OutlineInputBorder()),
            ),
          ),
        ]),
        const SizedBox(height: 18),
        TextField(
          controller: _source,
          minLines: 14,
          maxLines: 24,
          decoration: InputDecoration(
            labelText: '$label资料',
            hintText: '粘贴包含多个$label的章节、设定或人物小传……',
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
          ),
        ),
        if ((_error ?? importController.errorMessage) != null) ...[
          const SizedBox(height: 10),
          Text(_error ?? importController.errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _loading ? null : _identify,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.person_search_outlined),
            label: Text(_loading ? '正在识别…' : '识别角色'),
          ),
        ),
      ],
    );
  }
}

class _SceneRelationshipPickerPage extends StatefulWidget {
  final List<Map<String, dynamic>> candidates;
  final Set<String> selectedIds;

  const _SceneRelationshipPickerPage({
    required this.candidates,
    required this.selectedIds,
  });

  @override
  State<_SceneRelationshipPickerPage> createState() =>
      _SceneRelationshipPickerPageState();
}

class _SceneRelationshipPickerPageState
    extends State<_SceneRelationshipPickerPage> {
  late final Set<String> _selected = Set<String>.from(widget.selectedIds);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('选择对象（可多选）', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('生成资料会依据原文和这些已有角色建立可验证的关系。',
            style: TextStyle(color: Theme.of(context).hintColor)),
        const SizedBox(height: 16),
        for (final item in widget.candidates)
          CheckboxListTile(
            value: _selected.contains(item['id']?.toString()),
            title: Text(item['name']?.toString() ?? ''),
            onChanged: item['id'] == null
                ? null
                : (value) => setState(() {
                      final id = item['id'].toString();
                      if (value == true) {
                        _selected.add(id);
                      } else {
                        _selected.remove(id);
                      }
                    }),
          ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => Navigator.pop(context, _selected),
            icon: const Icon(Icons.check_rounded),
            label: Text('确认关联 ${_selected.length} 个角色'),
          ),
        ),
      ],
    );
  }
}
