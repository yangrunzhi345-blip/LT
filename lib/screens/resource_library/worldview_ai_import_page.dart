import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/resource_library_import_controller.dart';
import '../../core/router/app_router.dart';
import '../../core/widgets/narr_aitor_dropdown.dart';
import '../../models/resource_library_mode.dart';
import '../../models/worldview_details.dart';
import '../../providers/riverpod_providers.dart';
import '../../application/resources/resource_creation_contracts.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../features/resource_studio/presentation/pages/resource_studio_page.dart';

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
                    : progress.targetCharacters != null
                        ? '当前有效字数 ${progress.currentCharacters} / ${progress.targetCharacters}\n${progress.partialText}'
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
    final source = sourceCtrl.text.trim();
    if (source.isEmpty) return;
    final name = source.split(RegExp(r'\r?\n')).first.trim();
    await AppRouter.push<void>(
      context,
      pageBuilder: (_) => ResourceStudioPage(
        creationDraft: ResourceStudioCreationDraft(
          type: ResourceType.worldview,
          name: name.isEmpty
              ? 'AI 导入世界观'
              : (name.length > 80 ? name.substring(0, 80) : name),
          referenceSource: ReferenceSource.text(source, label: '世界观导入'),
          targetCharacters: target ?? 10000,
          origin: 'worldview-import',
          libraryMode: widget.mode.storageValue,
        ),
      ),
    );
    if (!mounted) return;
    Navigator.pop(context);
    widget.onChanged();
  }
}
