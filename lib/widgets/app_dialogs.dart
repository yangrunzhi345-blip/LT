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
import '../l10n/generated/app_localizations.dart';

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
  final l10n = AppLocalizations.of(context);
  final provider =
      ProviderScope.containerOf(context, listen: false).read(chatProvider);
  double fontSize = provider.chatFontSize.toDouble() / provider.textScaleFactor;

  showFormSubPage<void>(
    context: context,
    title: l10n?.fontSizeAdjustment ?? 'Font Size Adjustment',
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
            Row(
              children: [
                const Icon(Icons.text_fields, size: 20),
                const SizedBox(width: 8),
                Text(l10n?.fontSizeAdjustment ?? 'Font Size Adjustment',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(l10n?.fontSizeSmallA ?? 'A Small',
                    style: const TextStyle(fontSize: 12)),
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
                Text(l10n?.fontSizeLargeA ?? 'A Large',
                    style: const TextStyle(fontSize: 20)),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                l10n?.fontSizePreview ?? 'Preview: Text 123\nFont size sample',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: fontSize),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n?.closeAction ?? 'Close'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    provider.setChatFontSize(fontSize);
                    Navigator.pop(ctx);
                  },
                  child: Text(l10n?.applyAction ?? 'Apply'),
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

String _completionPresetLabel(BuildContext context, String name) {
  final l10n = AppLocalizations.of(context);
  if (name == '自定义') return l10n?.customPreset ?? 'Custom';
  if (name == '深度思考 (V4.1 复杂推演)') return l10n?.presetDeepThinking ?? name;
  if (name == '极速叙事 (默认体验)') return l10n?.presetFastNarrative ?? name;
  if (name == '极限推理 (长考解谜)') return l10n?.presetDeepReasoning ?? name;
  if (name == '轻量日常 (极速低延迟)') return l10n?.presetLightweightDaily ?? name;
  return name;
}

void showCompletionParamsDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final provider =
      ProviderScope.containerOf(context, listen: false).read(chatProvider);
  var params = provider.completionParams;
  var selectedPreset = '自定义';

  showFormSubPage<void>(
    context: context,
    title: l10n?.dialogueParams ?? 'Dialogue Parameters',
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
            Row(
              children: [
                const Icon(Icons.tune, size: 20),
                const SizedBox(width: 8),
                Text(l10n?.parameterPresets ?? 'Parameter Presets',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: ['自定义', ...CompletionParams.presets.keys].map((name) {
                return ChoiceChip(
                  label: Text(_completionPresetLabel(ctx, name),
                      style: const TextStyle(fontSize: 11)),
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
            paramSlider(l10n?.frequencyPenalty ?? 'Frequency Penalty',
                params.frequencyPenalty, -2.0, 2.0, (v) {
              setState(() {
                selectedPreset = '自定义';
                params = params.copyWith(frequencyPenalty: v);
              });
            }),
            paramSlider(l10n?.presencePenalty ?? 'Presence Penalty',
                params.presencePenalty, -2.0, 2.0, (v) {
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
                    final presetName =
                        _completionPresetLabel(context, selectedPreset);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          l10n?.appliedPreset(presetName) ??
                              'Applied: $presetName',
                        ),
                      ),
                    );
                  },
                  child: Text(l10n?.applyAction ?? 'Apply'),
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
  final l10n = AppLocalizations.of(context);
  final nameCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final sheet = showFormSubPage<void>(
    context: context,
    title: l10n?.saveWorldview ?? 'Save Worldview',
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
            Text(l10n?.worldviewInfo ?? 'Worldview Info',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                    labelText: l10n?.name ?? 'Name',
                    border: const OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                    labelText:
                        l10n?.descriptionOptional ?? 'Description (Optional)',
                    border: const OutlineInputBorder())),
            const SizedBox(height: 12),
            Row(children: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n?.cancelAction ?? 'Cancel')),
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
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(l10n?.worldviewSaved(name) ??
                              'Saved worldview "$name"')));
                    } else {
                      final error = result.errorMessage ??
                          l10n?.unknownError ??
                          'Unknown error';
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(l10n?.saveFailed(error) ??
                              'Save failed: $error')));
                    }
                  },
                  child: Text(l10n?.saveAction ?? 'Save')),
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
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController();
  final page = showFormSubPage<void>(
    context: context,
    title: l10n?.importCharacterCard ?? 'Import Character Card',
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
            Row(children: [
              const Icon(Icons.file_download,
                  size: 20, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(l10n?.importCharacterCard ?? 'Import Character Card',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 8),
            Text(
                l10n?.pasteCharacterCardJson ??
                    'Paste SillyTavern / Chub character card JSON',
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              scrollPadding: const EdgeInsets.only(bottom: 120),
              maxLines: 8,
              decoration: InputDecoration(
                hintText: l10n?.pasteCharacterCardJsonHint ??
                    'Paste character card JSON content here...',
                border: const OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(children: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n?.cancelAction ?? 'Cancel'),
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
                child: Text(l10n?.importAction ?? 'Import'),
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
  final l10n = AppLocalizations.of(context);
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
    title: isEdit
        ? (l10n?.editDialoguePersonaCard ?? 'Edit Dialogue Persona Card')
        : (l10n?.newDialoguePersonaCard ?? 'New Dialogue Persona Card'),
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
                    Text(
                      l10n?.dialoguePersonaSettings ??
                          'Dialogue Character Settings',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n?.dialoguePersonaSettingsDesc ??
                      'Characters here are only used for dialogue mode and can completely bypass Naela.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: l10n?.personaNameRequired ?? 'Character Name *',
                    hintText: l10n?.personaNameHint ??
                        'e.g. Naela, Advisor, My Writing Partner',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: roleCtrl,
                  decoration: InputDecoration(
                    labelText: l10n?.personaRole ?? 'Role & Identity',
                    hintText: l10n?.personaRoleHint ??
                        'e.g. General AI Assistant, Language Coach, Worldview Advisor',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: userCallNameCtrl,
                  decoration: InputDecoration(
                    labelText:
                        l10n?.personaUserCallName ?? 'How to Address User',
                    hintText: l10n?.personaUserCallNameHint ??
                        'e.g. User, Creator, Commander, Teacher',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: personalityCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText:
                        l10n?.personaPersonality ?? 'Personality & Traits',
                    hintText: l10n?.personaPersonalityHint ??
                        'Describe personality, values, and problem-solving approaches',
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: speakingStyleCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: l10n?.personaSpeakingStyle ?? 'Speaking Style',
                    hintText: l10n?.personaSpeakingStyleHint ??
                        'e.g. Concise, gentle, with steps and examples if needed',
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: backgroundCtrl,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: l10n?.personaBackground ?? 'Background',
                    hintText: l10n?.personaBackgroundHint ??
                        'Where the character comes from and what it knows',
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: scenarioCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: l10n?.personaScenario ?? 'Dialogue Scenario',
                    hintText: l10n?.personaScenarioHint ??
                        'Describe in what context the character communicates with the user',
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: systemPromptCtrl,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: l10n?.personaSystemPrompt ??
                        'Extra System Instructions',
                    hintText: l10n?.personaSystemPromptHint ??
                        'Optional: supplementary rules the character must follow',
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
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
                        final cardName = nameCtrl.text.trim();
                        final confirmed = await AppConfirmDialog.show(
                          context: ctx,
                          title: l10n?.deleteDialoguePersonaTitle ??
                              'Delete dialogue character card?',
                          message: l10n
                                  ?.deleteDialoguePersonaPrompt(cardName) ??
                              'Are you sure you want to delete "$cardName"?',
                          confirmLabel: l10n?.deleteAction ?? 'Delete',
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
                            final err = result.errorMessage ??
                                l10n?.unknownError ??
                                'Unknown error';
                            AppFeedback.error(
                                ctx,
                                l10n?.deleteCharacterCardFailed(err) ??
                                    'Failed to delete character card: $err');
                          }
                          return;
                        }
                        if (result.message != null && ctx.mounted) {
                          AppFeedback.success(ctx, result.message!);
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: Text(
                        l10n?.deleteAction ?? 'Delete',
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(l10n?.cancelAction ?? 'Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                              content: Text(l10n?.pleaseEnterPersonaName ??
                                  'Please enter character name')),
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
                            source: existingCard?['source'] as String? ??
                                (l10n?.manuallyCreated ?? 'Manually created'),
                            now: now,
                            mode: ResourceLibraryMode.conversation,
                          );
                      if (!result.success) {
                        if (ctx.mounted) {
                          final err = result.errorMessage ??
                              l10n?.unknownError ??
                              'Unknown error';
                          AppFeedback.error(
                            ctx,
                            l10n?.saveFailed(err) ?? 'Save failed: $err',
                          );
                        }
                        return;
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: Text(isEdit
                        ? (l10n?.saveAction ?? 'Save')
                        : (l10n?.createAction ?? 'Create')),
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
