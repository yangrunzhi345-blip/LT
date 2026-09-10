import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;

import '../../../../core/feedback/app_feedback.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../models/dialogue_level.dart';
import '../../../../providers/riverpod_providers.dart';
import '../widgets/prompt_preview_modal.dart';

/// 现代化提示词与模型推演参数设定主屏
/// 提供完全纯净的白板设定环境，支持对话密度分级、全局系统提示词、作者注注入与实时装配预览
class PromptSettingsScreen extends ConsumerStatefulWidget {
  const PromptSettingsScreen({super.key});

  @override
  ConsumerState<PromptSettingsScreen> createState() =>
      _PromptSettingsScreenState();
}

class _PromptSettingsScreenState extends ConsumerState<PromptSettingsScreen> {
  late TextEditingController _systemPromptController;
  late TextEditingController _authorsNoteController;
  late int _noteDepth;
  late int _noteFrequency;

  @override
  void initState() {
    super.initState();
    final provider = ref.read(chatProvider);
    _systemPromptController = TextEditingController(
      text: provider.settingsProvider.customSystemPrompt,
    );
    _authorsNoteController = TextEditingController(
      text: provider.settingsProvider.authorsNote,
    );
    _noteDepth = provider.authorsNoteDepth;
    _noteFrequency = provider.authorsNoteFrequency;
  }

  @override
  void dispose() {
    _systemPromptController.dispose();
    _authorsNoteController.dispose();
    super.dispose();
  }

  void _showPromptPreview() {
    final provider = ref.read(chatProvider);
    final preview = provider.getFullPromptPreview();
    PromptPreviewModal.show(context, preview);
  }

  void _showPresetImportDialog() {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.file_download_outlined,
                        color: colorScheme.primary, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      '导入提示词预设',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '粘贴提示词预设 JSON（支持列表或 {"presets": [...]} 格式）',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText: '在此粘贴预设 JSON 文本...',
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.35),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final json = controller.text.trim();
                        if (json.isEmpty) return;
                        final result = ref
                            .read(chatProvider)
                            .libraryProvider
                            .importPresetsFromJson(json);
                        Navigator.pop(ctx);
                        AppFeedback.success(context, result);
                      },
                      child: const Text('导入'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() => controller.dispose());
  }

  void _showPresetExport() {
    final json = ref.read(chatProvider).libraryProvider.exportPresetsToJson();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.file_upload_outlined,
                      color: colorScheme.primary, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    '导出提示词预设',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 250),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    json,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('关闭'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      AppFeedback.success(context, '已生成预设 JSON，可直接全选复制');
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('完成'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = ref.watch(chatProvider);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('提示词与推演编排'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined, size: 20),
            tooltip: '导入预设',
            onPressed: _showPresetImportDialog,
          ),
          IconButton(
            icon: const Icon(Icons.file_upload_outlined, size: 20),
            tooltip: '导出预设',
            onPressed: _showPresetExport,
          ),
          FilledButton.tonalIcon(
            onPressed: _showPromptPreview,
            icon: const Icon(Icons.preview_rounded, size: 16),
            label: const Text('预览'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        children: [
          // 对话分级与字数预算
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.format_size_rounded,
                        color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '对话模式分级 (Dialogue Level)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '选择模型在单轮对话中的字数输出预算与描摹细节密度。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ...DialogueLevel.values.map((level) {
                  final selected =
                      level.id == provider.settingsProvider.dialogueLevel.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () =>
                          provider.settingsProvider.setDialogueLevel(level),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: selected
                              ? colorScheme.primaryContainer
                                  .withValues(alpha: 0.45)
                              : colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? colorScheme.primary.withValues(alpha: 0.5)
                                : colorScheme.outlineVariant
                                    .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 18,
                              color: selected
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${level.id} · ${level.label}',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${level.wordRangeLabel} · ${level.description}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 系统全局提示词 (System Prompt - 纯白板设计)
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.terminal_rounded,
                        color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '全局系统提示词 (System Prompt)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '纯净初始状态。留空时系统将采用极简通用的推演规范。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _systemPromptController,
                  maxLines: 8,
                  decoration: InputDecoration(
                    hintText: '在此编写自定义系统设定、世界规则或角色推演守则（留空使用纯净默认规则）...',
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Text(
                      '已写 ${_systemPromptController.text.length} 字符',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _systemPromptController.text.isNotEmpty
                          ? () {
                              _systemPromptController.clear();
                              provider.settingsProvider
                                  .setCustomSystemPrompt('');
                              setState(() {});
                            }
                          : null,
                      child: const Text('清空'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        provider.settingsProvider.setCustomSystemPrompt(
                          _systemPromptController.text.trim(),
                        );
                        AppFeedback.success(context, '全局系统提示词已保存');
                      },
                      icon: const Icon(Icons.save_rounded, size: 16),
                      label: const Text('保存提示词'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 作者注释 (Author's Note - 动态深度注入)
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.edit_note_rounded,
                        color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '作者注释 (Author\'s Note)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '在会话上下文中指定轮数深度注入高权重指示。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _authorsNoteController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: '例如：聚焦于主角行动的细致刻画，保持环境氛围神秘悬疑...',
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    const Text('注入深度', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Slider(
                        value: _noteDepth.toDouble(),
                        min: 0,
                        max: 10,
                        divisions: 10,
                        label: _noteDepth == 0 ? '紧跟系统设定' : '第 $_noteDepth 轮前',
                        onChanged: (v) =>
                            setState(() => _noteDepth = v.round()),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text(
                        '$_noteDepth',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('注入频率', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Slider(
                        value: _noteFrequency.toDouble(),
                        min: 1,
                        max: 10,
                        divisions: 9,
                        label: '每 $_noteFrequency 轮',
                        onChanged: (v) =>
                            setState(() => _noteFrequency = v.round()),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text(
                        '$_noteFrequency',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      provider.settingsProvider
                          .setAuthorsNote(_authorsNoteController.text.trim());
                      provider.settingsProvider
                          .setAuthorsNoteConfig(_noteDepth, _noteFrequency);
                      AppFeedback.success(context, '作者注释设置已保存');
                    },
                    icon: const Icon(Icons.save_rounded, size: 16),
                    label: const Text('保存注释配置'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
