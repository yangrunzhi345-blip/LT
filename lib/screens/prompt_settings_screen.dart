import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import '../providers/riverpod_providers.dart';
import '../models/dialogue_level.dart';
import '../utils/token_estimator.dart';
import '../core/theme/app_colors.dart';

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
        text: provider.settingsProvider.customSystemPrompt);
    _authorsNoteController =
        TextEditingController(text: provider.settingsProvider.authorsNote);
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
    final text = preview.map((m) {
      return '[${m['role']}]\n${m['content']}\n';
    }).join('\n---\n\n');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Prompt 预览',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              Text(
                  '共约 ${text.length} 字符 · 预估 ${TokenEstimator(text).tokens} tokens',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(height: 8),
              _buildTokenBars(preview),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView(
                    controller: scrollController,
                    children: [
                      SelectableText(
                        text,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTokenBars(List<Map<String, String>> preview) {
    final estimator = TokenEstimator('');
    final parts = estimator.analyzePrompt(preview);
    final total = parts['总计'] ?? 1;
    final colors = [
      AppColors.accent,
      const Color(0xFF4ECDC4),
      const Color(0xFFF0C040),
      const Color(0xFFFF6B6B)
    ];

    final items = parts.entries.where((e) => e.key != '总计').toList();
    items.sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(items.length, (i) {
          final entry = items[i];
          final percent = (entry.value / total * 100).toStringAsFixed(1);
          final color = colors[i % colors.length];
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(entry.key,
                        style:
                            TextStyle(fontSize: 10, color: Colors.grey[500])),
                    const Spacer(),
                    Text('${entry.value}t ($percent%)',
                        style:
                            TextStyle(fontSize: 10, color: Colors.grey[500])),
                  ],
                ),
                const SizedBox(height: 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: entry.value / total,
                    minHeight: 6,
                    backgroundColor: color.withValues(alpha: 0.1),
                    color: color,
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        Text('总计 $total tokens',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600])),
      ],
    );
  }

  // ─── P1-1: 预设导入/导出 ───

  void _showPresetImportDialog() {
    final controller = TextEditingController();
    final sheet = showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('导入预设',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                Text('粘贴预设 JSON（支持列表或 {"presets": [...]} 格式）',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                const SizedBox(height: 12),
                TextField(
                    controller: controller,
                    scrollPadding: const EdgeInsets.only(bottom: 120),
                    maxLines: 6,
                    decoration: const InputDecoration(
                        hintText: '在此粘贴 JSON...', border: OutlineInputBorder()),
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                const SizedBox(height: 16),
                Row(children: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('取消')),
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
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(result)));
                      },
                      child: const Text('导入')),
                ]),
              ]),
        ),
      ),
    );
    unawaited(sheet.whenComplete(() {
      controller.dispose();
    }));
  }

  void _showPresetExport() {
    final json = ref.read(chatProvider).libraryProvider.exportPresetsToJson();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('导出预设',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 250),
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8)),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(8),
                    child: Text(json,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('关闭')),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已生成 JSON，请手动复制')));
                    },
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('全选复制'),
                  ),
                ]),
              ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(chatProvider);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('提示词设置',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          // P1-1: 预设导入/导出
          IconButton(
            icon: const Icon(Icons.file_download_outlined, size: 18),
            onPressed: () => _showPresetImportDialog(),
            tooltip: '导入预设',
          ),
          IconButton(
            icon: const Icon(Icons.file_upload_outlined, size: 18),
            onPressed: () => _showPresetExport(),
            tooltip: '导出预设',
          ),
          TextButton.icon(
            onPressed: _showPromptPreview,
            icon: const Icon(Icons.preview, size: 18),
            label: const Text('预览'),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 +
              MediaQuery.of(context).viewPadding.bottom +
              MediaQuery.of(context).viewInsets.bottom,
        ),
        children: [
          // Presets
          _buildSectionTitle('对话模式分级', '选择生成速度、细节密度和字数预算'),
          const SizedBox(height: 8),
          ...DialogueLevel.values.map((level) {
            return RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: level.id,
              // ignore: deprecated_member_use
              groupValue: provider.settingsProvider.dialogueLevel.id,
              // ignore: deprecated_member_use
              onChanged: (_) =>
                  provider.settingsProvider.setDialogueLevel(level),
              title: Text('${level.id} · ${level.label}'),
              subtitle: Text('${level.wordRangeLabel} · ${level.description}'),
            );
          }),
          const SizedBox(height: 16),

          // Presets
          _buildSectionTitle('预设方案', '一键切换提示词配置'),
          const SizedBox(height: 8),
          TextField(
            controller: _systemPromptController,
            scrollPadding: const EdgeInsets.only(bottom: 120),
            maxLines: 10,
            decoration: InputDecoration(
              hintText: '留空则使用默认提示词...',
              alignLabelWithHint: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('已写 ${_systemPromptController.text.length} 字符',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const Spacer(),
              TextButton(
                onPressed: _systemPromptController.text.isNotEmpty
                    ? () {
                        _systemPromptController.clear();
                        provider.settingsProvider.setCustomSystemPrompt('');
                        setState(() {});
                      }
                    : null,
                child: const Text('清空'),
              ),
              FilledButton.tonalIcon(
                onPressed: () {
                  provider.settingsProvider.setCustomSystemPrompt(
                      _systemPromptController.text.trim());
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('系统提示词已保存')),
                  );
                },
                icon: const Icon(Icons.save, size: 16),
                label: const Text('保存'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Author's Note
          _buildSectionTitle('作者注释', '在对话深度处以指定频率注入'),
          const SizedBox(height: 8),
          TextField(
            controller: _authorsNoteController,
            scrollPadding: const EdgeInsets.only(bottom: 120),
            maxLines: 6,
            decoration: InputDecoration(
              hintText: '例如：注意保持角色性格一致...',
              alignLabelWithHint: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 12),

          // Depth
          Row(
            children: [
              const Text('注入深度', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _noteDepth.toDouble(),
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: _noteDepth == 0 ? '紧跟系统提示词' : '在第 $_noteDepth 条消息后',
                  onChanged: (v) => setState(() => _noteDepth = v.round()),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '$_noteDepth',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Frequency
          Row(
            children: [
              const Text('注入频率', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _noteFrequency.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: '每 $_noteFrequency 轮',
                  onChanged: (v) => setState(() => _noteFrequency = v.round()),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '$_noteFrequency',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _noteDepth == 0 ? '将在系统提示词之后、每次对话时注入' : '将在历史消息深度 $_noteDepth 处注入',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () {
              provider.settingsProvider
                  .setAuthorsNote(_authorsNoteController.text.trim());
              provider.settingsProvider
                  .setAuthorsNoteConfig(_noteDepth, _noteFrequency);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('作者注释已保存')),
              );
            },
            icon: const Icon(Icons.save, size: 16),
            label: const Text('保存注释设置'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
      ],
    );
  }
}

const JsonEncoder encoder = JsonEncoder.withIndent('  ');
