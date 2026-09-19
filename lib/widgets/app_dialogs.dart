import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import '../providers/riverpod_providers.dart';
import '../models/llm_provider.dart';
import '../application/resource_library/edit_drafts.dart';
export '../application/resource_library/edit_drafts.dart';
import '../core/feedback/app_feedback.dart';
import '../models/completion_params.dart';
import '../models/resource_library_mode.dart';
import '../core/theme/app_colors.dart';
import '../core/widgets/form_sub_page_scaffold.dart';
import '../core/widgets/app_confirm_dialog.dart';
import '../core/router/app_router.dart';
import '../features/settings/presentation/screens/settings_pages.dart';
import '../features/settings/presentation/screens/chat_transfer_pages.dart';
import '../screens/resource_library/character_card_edit_page.dart';

/// 显示现代化、语义化 M3 设计风格的模型与 API 设置弹窗
void showApiSettings(BuildContext context) {
  unawaited(AppRouter.push<void>(
    context,
    pageBuilder: (_) => const ApiSettingsPage(),
  ));
}

/// 提供商品牌色
Color providerBrandColor(LLMProvider p) => switch (p) {
      LLMProvider.deepseek => const Color(0xFF3C5DFF), // DeepSeek Blue
      LLMProvider.custom => AppColors.primary,
    };

/// 提供商品牌图标（官方 SVG logo）
Widget providerBrandIcon(LLMProvider p, {double size = 28}) {
  final assetPath = switch (p) {
    LLMProvider.deepseek => 'assets/icons/deepseek.svg',
    _ => null,
  };
  if (assetPath != null) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: SvgPicture.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
  return _brandFallbackIcon(p, size);
}

/// SVG 加载失败时的回退图标（品牌色圆角方块）
Widget _brandFallbackIcon(LLMProvider p, double size) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: providerBrandColor(p),
      borderRadius: BorderRadius.circular(size * 0.26),
    ),
    child: Center(
      child: Text(
        switch (p) {
          LLMProvider.deepseek => 'D',
          LLMProvider.custom => 'C',
        },
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

void showFontSizeDialog(BuildContext context) {
  final provider =
      ProviderScope.containerOf(context, listen: false).read(chatProvider);
  double fontSize = provider.chatFontSize.toDouble() / provider.textScaleFactor;

  showFormSubPage<void>(
    context: context,
    title: '字号调节',
    maxWidth: 640,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.text_fields, size: 20),
                SizedBox(width: 8),
                Text('字号调节',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('A小', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: fontSize,
                    min: 12,
                    max: 20,
                    divisions: 8,
                    onChanged: (v) {
                      setState(() => fontSize = v);
                    },
                  ),
                ),
                const Text('A大', style: TextStyle(fontSize: 20)),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                '预览: 中文 123\n字号大小示例',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: fontSize),
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
                FilledButton(
                  onPressed: () {
                    provider.setChatFontSize(fontSize);
                    Navigator.pop(ctx);
                  },
                  child: const Text('应用'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showExportDialog(BuildContext context) => AppRouter.push<void>(
      context,
      pageBuilder: (_) => const ExportPage(),
    );

void showImportDialog(BuildContext context) {
  unawaited(AppRouter.push<bool>(
    context,
    pageBuilder: (_) => const ImportPage(),
  ));
}

void showCompletionParamsDialog(BuildContext context) {
  final provider =
      ProviderScope.containerOf(context, listen: false).read(chatProvider);
  var params = provider.completionParams;
  var selectedPreset = '自定义';

  showFormSubPage<void>(
    context: context,
    title: '对话参数',
    maxWidth: 760,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.tune, size: 20),
                SizedBox(width: 8),
                Text('参数预设',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: ['自定义', ...CompletionParams.presets.keys].map((name) {
                return ChoiceChip(
                  label: Text(name, style: const TextStyle(fontSize: 11)),
                  selected: selectedPreset == name,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) {
                    setState(() {
                      selectedPreset = name;
                      if (name != '自定义') {
                        params = CompletionParams.presets[name]!;
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            paramSlider('Temperature', params.temperature, 0.0, 2.0, (v) {
              setState(() {
                selectedPreset = '自定义';
                params = params.copyWith(temperature: v);
              });
            }),
            paramSlider('Top-P', params.topP, 0.0, 1.0, (v) {
              setState(() {
                selectedPreset = '自定义';
                params = params.copyWith(topP: v);
              });
            }),
            paramSlider('频惩罚', params.frequencyPenalty, -2.0, 2.0, (v) {
              setState(() {
                selectedPreset = '自定义';
                params = params.copyWith(frequencyPenalty: v);
              });
            }),
            paramSlider('存惩罚', params.presencePenalty, -2.0, 2.0, (v) {
              setState(() {
                selectedPreset = '自定义';
                params = params.copyWith(presencePenalty: v);
              });
            }),
            paramSlider('Max Tokens', params.maxTokens.toDouble(), 512, 16384,
                (v) {
              setState(() {
                selectedPreset = '自定义';
                params = params.copyWith(maxTokens: v.round());
              });
            }),
            const SizedBox(height: 16),
            Row(
              children: [
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    provider.settingsProvider.setCompletionParams(params);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已应用：$selectedPreset')),
                    );
                  },
                  child: const Text('应用'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Widget paramSlider(
  String label,
  double value,
  double min,
  double max,
  ValueChanged<double> onChanged,
) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(label),
          const Spacer(),
          Text(value.toStringAsFixed(2)),
        ],
      ),
      Slider(value: value, min: min, max: max, onChanged: onChanged),
    ],
  );
}

void showSaveWorldviewDialog(BuildContext context) {
  final nameCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final sheet = showFormSubPage<void>(
    context: context,
    title: '保存世界观',
    maxWidth: 720,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('世界观信息',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                    labelText: '名称', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: '描述（可选）', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            Row(children: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              const SizedBox(width: 8),
              FilledButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    final draft = WorldviewEditDraft(
                      name: name,
                      description: descCtrl.text.trim(),
                    );
                    final result =
                        await ProviderScope.containerOf(context, listen: false)
                            .read(resourceCrudControllerProvider)
                            .saveWorldviewDraft(draft);
                    if (!context.mounted) return;
                    if (result.success) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已保存世界观「$name」')));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content:
                              Text('保存失败：${result.errorMessage ?? '未知错误'}')));
                    }
                  },
                  child: const Text('保存')),
            ]),
          ]),
    ),
  );
  unawaited(sheet.whenComplete(() {
    nameCtrl.dispose();
    descCtrl.dispose();
  }));
}

/// 新建/编辑角色卡对话框（侧边栏、资源库、Builder 公用）
/// [existingCard] 传入时进入编辑模式，[existingId] 为数据库 ID
Future<CharacterCardEditDraft?> showCreateCharacterCardDialog(
    BuildContext context,
    {Map<String, dynamic>? existingCard,
    String? existingId,
    String? defaultMatchingWorldviewId,
    List<Map<String, dynamic>>? worldviewPresets,
    String? activeWorldviewDescription,
    ResourceLibraryMode mode = ResourceLibraryMode.adventure}) {
  return showCharacterCardEditPage(
    context,
    existingCard: existingCard,
    existingId: existingId,
    defaultMatchingWorldviewId: defaultMatchingWorldviewId,
    worldviewPresets: worldviewPresets,
    activeWorldviewDescription: activeWorldviewDescription,
    mode: mode,
  );
}

/// 导入角色卡对话框（粘贴 JSON）
void showImportCharacterCardDialog(BuildContext context) {
  final controller = TextEditingController();
  final page = showFormSubPage<void>(
    context: context,
    title: '导入角色卡',
    maxWidth: 760,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.file_download, size: 20, color: AppColors.accent),
              SizedBox(width: 8),
              Text('导入角色卡',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 8),
            Text('粘贴 SillyTavern / Chub 角色卡 JSON',
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              scrollPadding: const EdgeInsets.only(bottom: 120),
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: '在此粘贴角色卡 JSON 内容...',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(children: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  final text = controller.text.trim();
                  if (text.isEmpty) return;
                  final result =
                      await ProviderScope.containerOf(context, listen: false)
                          .read(chatProvider)
                          .libraryProvider
                          .importCharacterCardJson(text);
                  if (!ctx.mounted || !context.mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(result)),
                  );
                },
                child: const Text('导入'),
              ),
            ]),
          ]),
    ),
  );
  unawaited(page.whenComplete(controller.dispose));
}

/// 对话资料库专用的角色卡编辑器。
///
/// 对话角色不绑定世界观、年龄或外貌等场景角色字段，重点描述对话身份、
/// 性格、表达方式和系统行为。场景资料库继续使用上方的通用角色卡编辑器。
Future<void> showCreateConversationCharacterCardDialog(
  BuildContext context, {
  Map<String, dynamic>? existingCard,
  String? existingId,
}) async {
  final isEdit = existingCard != null;
  Map<String, dynamic> json = {};
  if (existingCard != null) {
    try {
      final decoded = jsonDecode(existingCard['json_data'] as String? ?? '{}');
      if (decoded is Map<String, dynamic>) json = decoded;
    } catch (_) {}
  }
  final nameCtrl =
      TextEditingController(text: existingCard?['name'] ?? json['name'] ?? '');
  final roleCtrl = TextEditingController(text: json['role']?.toString() ?? '');
  final userCallNameCtrl =
      TextEditingController(text: json['user_call_name']?.toString() ?? '');
  final personalityCtrl =
      TextEditingController(text: json['personality']?.toString() ?? '');
  final speakingStyleCtrl =
      TextEditingController(text: json['speaking_style']?.toString() ?? '');
  final backgroundCtrl = TextEditingController(
      text: (json['background'] ?? json['description'])?.toString() ?? '');
  final scenarioCtrl =
      TextEditingController(text: json['scenario']?.toString() ?? '');
  final systemPromptCtrl =
      TextEditingController(text: json['system_prompt']?.toString() ?? '');

  final sheet = showFormSubPage<void>(
    context: context,
    title: isEdit ? '编辑对话角色卡' : '新建对话角色卡',
    maxWidth: 760,
    builder: (ctx) => Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isEdit ? Icons.edit_rounded : Icons.badge_outlined,
                      size: 20,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '对话角色设定',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '这里的角色只用于对话模式，可以完全不使用奈拉。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '角色名称 *',
                    hintText: '例如：奈拉、顾问、我的写作搭档',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: roleCtrl,
                  decoration: const InputDecoration(
                    labelText: '身份定位',
                    hintText: '例如：通用 AI 助手、语言教练、世界观顾问',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: userCallNameCtrl,
                  decoration: const InputDecoration(
                    labelText: '如何称呼用户',
                    hintText: '例如：用户、创作者、指挥官、老师',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: personalityCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '性格与行为特点',
                    hintText: '描述角色的性格、价值观和处理问题的方式',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: speakingStyleCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '说话方式',
                    hintText: '例如：简洁、温柔，必要时用步骤和示例解释',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: backgroundCtrl,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '背景设定',
                    hintText: '角色从哪里来，以及它了解什么',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: scenarioCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '对话情境',
                    hintText: '描述角色与用户通常在哪种情境下交流',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: systemPromptCtrl,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '额外行为指令',
                    hintText: '可选：补充角色必须遵守的行为规则',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        Material(
          color: Theme.of(ctx).scaffoldBackgroundColor,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  if (isEdit)
                    TextButton(
                      onPressed: () async {
                        final confirmed = await AppConfirmDialog.show(
                          context: ctx,
                          title: '删除对话角色卡？',
                          message: '确定要删除“${nameCtrl.text.trim()}”吗？',
                          confirmLabel: '删除',
                          isDanger: true,
                          icon: Icons.delete_outline_rounded,
                        );
                        if (!confirmed) return;
                        if (!ctx.mounted) return;
                        final result = await ProviderScope.containerOf(
                          ctx,
                          listen: false,
                        )
                            .read(resourceCrudControllerProvider)
                            .deleteCharacterCard(
                              existingId!,
                              mode: ResourceLibraryMode.conversation,
                            );
                        if (!result.success) {
                          if (ctx.mounted) {
                            AppFeedback.error(
                                ctx, '删除角色卡失败: ${result.errorMessage}');
                          }
                          return;
                        }
                        if (result.message != null && ctx.mounted) {
                          AppFeedback.success(ctx, result.message!);
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text(
                        '删除',
                        style: TextStyle(color: AppColors.error),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('请填写角色名称')),
                        );
                        return;
                      }
                      final now = DateTime.now().toIso8601String();
                      final result = await ProviderScope.containerOf(
                        context,
                        listen: false,
                      ).read(resourceCrudControllerProvider).saveCharacterCard(
                            id: existingId ??
                                DateTime.now()
                                    .millisecondsSinceEpoch
                                    .toString(),
                            name: name,
                            jsonData: jsonEncode({
                              'name': name,
                              'role': roleCtrl.text.trim(),
                              'user_call_name': userCallNameCtrl.text.trim(),
                              'personality': personalityCtrl.text.trim(),
                              'speaking_style': speakingStyleCtrl.text.trim(),
                              'background': backgroundCtrl.text.trim(),
                              'scenario': scenarioCtrl.text.trim(),
                              'system_prompt': systemPromptCtrl.text.trim(),
                            }),
                            source:
                                existingCard?['source'] as String? ?? '手动创建',
                            now: now,
                            mode: ResourceLibraryMode.conversation,
                          );
                      if (!result.success) {
                        if (ctx.mounted) {
                          AppFeedback.error(
                            ctx,
                            '保存失败：${result.errorMessage ?? '未知错误'}',
                          );
                        }
                        return;
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: Text(isEdit ? '保存' : '创建'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  unawaited(sheet.whenComplete(() {
    for (final controller in [
      nameCtrl,
      roleCtrl,
      userCallNameCtrl,
      personalityCtrl,
      speakingStyleCtrl,
      backgroundCtrl,
      scenarioCtrl,
      systemPromptCtrl,
    ]) {
      controller.dispose();
    }
  }));
}
