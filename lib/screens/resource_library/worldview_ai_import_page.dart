import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/resource_library/import_models.dart';
import '../../controllers/resource_library_import_controller.dart';
import '../../core/widgets/narr_aitor_dropdown.dart';
import '../../models/resource_library_mode.dart';
import '../../models/worldview_details.dart';
import '../../providers/riverpod_providers.dart';

class WorldviewAiImportPage extends ConsumerStatefulWidget {
  final ResourceLibraryMode mode;
  final VoidCallback onChanged;

  const WorldviewAiImportPage({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  @override
  ConsumerState<WorldviewAiImportPage> createState() =>
      _WorldviewAiImportPageState();
}

class _WorldviewAiImportPageState extends ConsumerState<WorldviewAiImportPage> {
  final TextEditingController sourceCtrl = TextEditingController();
  final TextEditingController targetCharactersCtrl =
      TextEditingController(text: '10000');
  var importMode = WorldviewEditingMode.simple;
  bool _autoSave = true;

  ResourceLibraryImportController get controller =>
      ref.read(resourceLibraryImportControllerProvider);

  bool get busy =>
      controller.phase == ResourceImportPhase.generating ||
      controller.phase == ResourceImportPhase.saving;

  @override
  void dispose() {
    sourceCtrl.dispose();
    targetCharactersCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(resourceLibraryImportControllerProvider);
    final progress = controller.worldviewProgress;
    final error = controller.errorMessage;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('原文内容',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('粘贴任意文字（txt / md / HTML / 小说片段），AI 将自动提取并整合为世界观',
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            const SizedBox(height: 12),
            TextField(
              controller: sourceCtrl,
              maxLines: 10,
              minLines: 5,
              enabled: !busy,
              decoration: const InputDecoration(
                hintText: '在此粘贴原文内容...',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            NarrAItorDropdown<WorldviewEditingMode>(
              value: importMode,
              label: '导入模式',
              enabled: !busy,
              options: const [
                NarrAItorDropdownOption(
                    value: WorldviewEditingMode.simple, label: '简洁模式'),
                NarrAItorDropdownOption(
                    value: WorldviewEditingMode.detailed, label: '详细模式'),
              ],
              onChanged: (value) {
                if (value != null) setState(() => importMode = value);
              },
            ),
            if (busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress?.fraction),
              const SizedBox(height: 8),
              Text(
                progress == null
                    ? '正在准备推演…'
                    : '正在推演第 ${progress.completedQuestions >= progress.totalQuestions ? progress.totalQuestions : progress.completedQuestions + 1}/${progress.totalQuestions} 阶段：${progress.partialText}',
                style: const TextStyle(fontSize: 12),
              ),
              if (progress?.partialText.trim().isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(progress!.partialText,
                      maxLines: 6, overflow: TextOverflow.ellipsis),
                ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error,
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
            SwitchListTile(
              title: const Text('自动保存到资料库'),
              value: _autoSave,
              onChanged: (v) => setState(() => _autoSave = v),
            ),
            if (importMode == WorldviewEditingMode.detailed) ...[
              const SizedBox(height: 12),
              TextField(
                controller: targetCharactersCtrl,
                enabled: !busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '期望总字数',
                  helperText: '自适应分阶段高并发推演全套9大模块，提速数倍并自动保存',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                const Spacer(),
                if (busy)
                  TextButton(
                    onPressed: () {
                      controller.detachWorldviewToBackground();
                      Navigator.pop(context);
                    },
                    child: const Text('后台运行'),
                  ),
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: busy ? null : _generate,
                  child: const Text('AI 解析'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generate() async {
    final target = importMode == WorldviewEditingMode.detailed
        ? int.tryParse(targetCharactersCtrl.text.trim())
        : null;
    await controller.generateWorldview(
      WorldviewImportRequest(
        source: sourceCtrl.text,
        libraryMode: widget.mode,
        aiDepth: importMode == WorldviewEditingMode.detailed
            ? AiGenerationDepth.detailed
            : AiGenerationDepth.simple,
        targetTotalCharacters: target,
      ),
      runInBackground: _autoSave,
    );
    if (mounted && controller.phase == ResourceImportPhase.completed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已自动保存到资料库')),
      );
      Navigator.pop(context);
      widget.onChanged();
      return;
    }
    if (!mounted || controller.phase != ResourceImportPhase.reviewing) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认导入世界观'),
        content:
            SingleChildScrollView(child: _preview(controller.worldviewDraft!)),
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
    await controller.saveWorldview(mode: widget.mode);
    if (!mounted || controller.phase != ResourceImportPhase.completed) return;
    Navigator.pop(context);
    widget.onChanged();
  }

  Widget _preview(WorldviewImportDraft draft) {
    Map<String, dynamic>? detail;
    try {
      final decoded = jsonDecode(draft.detailJson);
      if (decoded is Map) detail = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    final details = WorldviewDetails.fromJson(
      detail,
      fallbackDescription: draft.description,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(draft.name,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text(draft.description),
        for (final key
            in WorldviewDetails.moduleKeys.where((k) => k != 'overview'))
          if (_moduleText(details.modules[key]).isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(_moduleLabel(key),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(_moduleText(details.modules[key])),
          ],
      ],
    );
  }

  String _moduleText(dynamic value) {
    if (value is String) return value.trim();
    if (value is List) {
      return value.map(_moduleText).where((s) => s.isNotEmpty).join('\n');
    }
    if (value is Map) {
      final content = value['content'] ?? value['summary'];
      if (content != null) return _moduleText(content);
      return value.entries
          .where((e) => e.key.toString() != 'status')
          .map((e) => _moduleText(e.value))
          .where((s) => s.isNotEmpty)
          .join('\n');
    }
    return '';
  }

  String _moduleLabel(String key) => switch (key) {
        'world_rules' => '规则与边界',
        'world_state' => '当前世界现状',
        'locations' => '地点与地理',
        'factions' => '势力与组织',
        'customs_and_life' => '风俗与生活',
        'timeline' => '历史与时间线',
        'glossary' => '术语表',
        'creative_constraints' => '创作约束',
        _ => key,
      };
}
