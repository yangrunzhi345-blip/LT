import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../features/settings/presentation/widgets/provider_config_section.dart';
import 'narr_aitor_loading.dart';
import '../screens/resource_library/character_card_edit_page.dart';

/// 显示现代化、语义化 M3 设计风格的模型与 API 设置弹窗
void showApiSettings(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final scheme = theme.colorScheme;
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.45 : 0.12,
                  ),
                  blurRadius: 36,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 顶部标题栏
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      border: Border(
                        bottom: BorderSide(
                          color: scheme.outlineVariant.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.tune_rounded,
                            size: 20,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '模型与 API 服务配置',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '配置 DeepSeek 官方 API 或自定义兼容接口',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          tooltip: '关闭',
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  // 内容配置区
                  const Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(20),
                      child: ProviderConfigSection(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
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

Future<void> showExportDialog(BuildContext context) async {
  final provider =
      ProviderScope.containerOf(context, listen: false).read(chatProvider);
  final jsonl = await provider.exportToJsonl();
  final txt = provider.exportToTxt();
  final md = provider.exportToMarkdown();
  final html = provider.exportToHtml();

  if (!context.mounted) return;

  final jsonlController = TextEditingController(text: jsonl);
  final txtController = TextEditingController(text: txt);
  final mdController = TextEditingController(text: md);
  final htmlController = TextEditingController(text: html);

  final exportSheet = showFormSubPage<void>(
    context: context,
    title: '导出聊天',
    maxWidth: 960,
    builder: (ctx) => DefaultTabController(
      length: 4,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.file_upload_outlined, size: 20),
                const SizedBox(width: 8),
                const Text('导出内容',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '导出文件可能包含剧情、角色、提示词和用户输入；疑似密钥已默认脱敏。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 8),
            // Save buttons — one per format
            Wrap(spacing: 6, runSpacing: 4, children: [
              _buildSaveBtn(ctx, txt, 'txt', provider.currentTitle, 'TXT'),
              _buildSaveBtn(ctx, md, 'md', provider.currentTitle, 'MD'),
              _buildSaveBtn(ctx, html, 'html', provider.currentTitle, 'HTML'),
              _buildSaveBtn(
                  ctx, jsonl, 'jsonl', provider.currentTitle, 'JSONL'),
            ]),
            const SizedBox(height: 8),
            const TabBar(
              tabs: [
                Tab(text: 'JSONL（完整）'),
                Tab(text: 'TXT（纯文本）'),
                Tab(text: 'MARKDOWN'),
                Tab(text: 'HTML'),
              ],
              labelStyle: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                children: [
                  buildExportTab(context, jsonlController, jsonl.length),
                  buildExportTab(context, txtController, txt.length),
                  buildExportTab(context, mdController, md.length),
                  buildExportTab(context, htmlController, html.length),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  unawaited(exportSheet.whenComplete(() {
    jsonlController.dispose();
    txtController.dispose();
    mdController.dispose();
    htmlController.dispose();
  }));
}

Widget buildExportTab(
    BuildContext context, TextEditingController ctrl, int length) {
  return Column(
    children: [
      const SizedBox(height: 8),
      Text('$length 字符',
          style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      const SizedBox(height: 8),
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: ctrl,
            readOnly: true,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(8),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: () {
          Clipboard.setData(ClipboardData(text: ctrl.text));
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已复制到剪贴板')),
          );
        },
        icon: const Icon(Icons.copy, size: 16),
        label: const Text('复制全部'),
      ),
    ],
  );
}

void showImportDialog(BuildContext context) {
  final txtCtrl = TextEditingController();
  final mdCtrl = TextEditingController();
  final htmlCtrl = TextEditingController();
  final jsonlCtrl = TextEditingController();
  bool aiLoading = false;
  String? aiError;
  const tabFormats = ['txt', 'md', 'html', 'JSONL'];

  final importSheet = showFormSubPage<void>(
    context: context,
    title: '导入聊天',
    maxWidth: 960,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => DefaultTabController(
        length: 4,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.file_download_outlined,
                      size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                const Text('导入内容',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ]),
              const SizedBox(height: 8),
              Text('粘贴聊天记录，AI 自动识别格式并整合为对话',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(height: 12),
              // Tab bar
              const TabBar(
                tabs: [
                  Tab(text: 'TXT（纯文本）'),
                  Tab(text: 'MARKDOWN'),
                  Tab(text: 'HTML'),
                  Tab(text: 'JSONL（完整）'),
                ],
                labelStyle: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildImportTab(txtCtrl),
                    _buildImportTab(mdCtrl),
                    _buildImportTab(htmlCtrl),
                    _buildImportTab(jsonlCtrl),
                  ],
                ),
              ),
              // AI loading/error
              if (aiLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Center(
                    child: Column(children: [
                      NarrAItorLoading.mini(),
                      SizedBox(height: 8),
                      Text('AI 正在解析对话...',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ]),
                  ),
                ),
              if (aiError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(aiError!,
                      style: const TextStyle(
                          color: AppColors.error, fontSize: 12)),
                ),
              const SizedBox(height: 12),
              // Action buttons
              Row(children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: aiLoading
                        ? null
                        : () async {
                            // Determine active tab and get its controller
                            final tabCtrl = DefaultTabController.of(ctx);
                            final idx = tabCtrl.index;
                            final format = tabFormats[idx];
                            final ctrl =
                                [txtCtrl, mdCtrl, htmlCtrl, jsonlCtrl][idx];
                            final content = ctrl.text.trim();
                            if (content.isEmpty) return;
                            final provider = ProviderScope.containerOf(context,
                                    listen: false)
                                .read(chatProvider);

                            if (format == 'JSONL') {
                              try {
                                await provider.importFromJsonl(content, '');
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('导入成功')),
                                  );
                                }
                              } catch (e) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text('导入失败：$e')),
                                  );
                                }
                              }
                              return;
                            }

                            if (provider.apiKey.isEmpty) {
                              setSheetState(() => aiError = '请先在设置中配置 API Key');
                              return;
                            }
                            setSheetState(() {
                              aiLoading = true;
                              aiError = null;
                            });
                            try {
                              final msgs = await ProviderScope.containerOf(
                                context,
                                listen: false,
                              ).read(aiImportServiceProvider).importChat(
                                    rawContent: content,
                                    fileType: format,
                                  );
                              if (!ctx.mounted) return;
                              if (msgs.isEmpty) {
                                setSheetState(() {
                                  aiLoading = false;
                                  aiError = 'AI 未能解析出有效对话，请检查内容格式';
                                });
                                return;
                              }
                              final jsonlLines =
                                  msgs.map((m) => jsonEncode(m)).join('\n');
                              await provider.importFromJsonl(jsonlLines, '');
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text('AI 导入成功，共 ${msgs.length} 条消息')),
                                );
                              }
                            } catch (e) {
                              if (!ctx.mounted) return;
                              setSheetState(() {
                                aiLoading = false;
                                aiError =
                                    '导入失败: ${e.toString().split("\n").first}';
                              });
                            }
                          },
                    child: Text(aiLoading ? '解析中...' : 'AI 解析导入'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    ),
  );

  unawaited(importSheet.whenComplete(() {
    txtCtrl.dispose();
    mdCtrl.dispose();
    htmlCtrl.dispose();
    jsonlCtrl.dispose();
  }));
}

Widget _buildImportTab(TextEditingController ctrl) {
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: TextField(
      controller: ctrl,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      decoration: const InputDecoration(
        hintText: '在此粘贴聊天内容...',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.all(8),
      ),
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    ),
  );
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

void showTokenDashboard(BuildContext context) {
  final provider =
      ProviderScope.containerOf(context, listen: false).read(chatProvider);
  final summary = provider.getTokenSummary();
  final modelUsage = summary['modelUsage'] as Map<String, int>;
  showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.data_usage, size: 20, color: AppColors.accent),
                SizedBox(width: 8),
                Text('Token 用量',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 16),
              tokenStat('本次会话', '${summary['sessionTokens']} tokens'),
              tokenStat('累计总量', '${summary['totalTokens']} tokens'),
              tokenStat('平均/条', '${summary['avgPerMessage']} tokens/条'),
              const Divider(),
              Text('按模型统计',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(height: 4),
              ...modelUsage.entries
                  .map((e) => tokenStat(e.key, '${e.value} tokens')),
              const SizedBox(height: 8),
              Row(children: [
                const Spacer(),
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('关闭')),
              ]),
            ]),
      ),
    ),
  );
}

Widget tokenStat(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Text(label, style: const TextStyle(fontSize: 13)),
      const Spacer(),
      Text(value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    ]),
  );
}

Widget paramSlider(String label, double value, double min, double max,
    ValueChanged<double> onChanged) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(value.toStringAsFixed(2),
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ],
      ),
      Slider(value: value, min: min, max: max, onChanged: onChanged),
    ],
  );
}

void showThemeDialog(BuildContext context) {
  showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('主题配色',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              themeChip(ctx, '默认', AppColors.accent),
              themeChip(ctx, '森林', const Color(0xFF2E7D32)),
              themeChip(ctx, '海洋', const Color(0xFF0288D1)),
              themeChip(ctx, '暗金', const Color(0xFFC9A050)),
              themeChip(ctx, '紫夜', const Color(0xFF7B1FA2)),
              themeChip(ctx, '暖橙', const Color(0xFFE65100)),
            ]),
          ],
        ),
      ),
    ),
  );
}

Widget themeChip(BuildContext ctx, String name, Color seed) {
  final provider =
      ProviderScope.containerOf(ctx, listen: false).read(chatProvider);
  return ChoiceChip(
    label: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: seed, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(name, style: const TextStyle(fontSize: 12)),
    ]),
    selected: provider.colorSeed == seed,
    onSelected: (_) {
      provider.setColorSeed(seed);
      Navigator.pop(ctx);
      ScaffoldMessenger.of(ctx)
          .showSnackBar(const SnackBar(content: Text('主题已切换')));
    },
    visualDensity: VisualDensity.compact,
  );
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

Widget _buildSaveBtn(
    BuildContext ctx, String content, String ext, String title, String label) {
  return OutlinedButton.icon(
    onPressed: () async {
      final path = await ProviderScope.containerOf(ctx, listen: false)
          .read(conversationExportUseCaseProvider)
          .saveToFile(content: content, extension: ext, title: title);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(path != null ? '已保存: $path' : '保存失败')),
        );
      }
    },
    icon: const Icon(Icons.save_alt, size: 14),
    label: Text(label, style: const TextStyle(fontSize: 12)),
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      visualDensity: VisualDensity.compact,
    ),
  );
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
                        final confirmed = await showDialog<bool>(
                          context: ctx,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('删除对话角色卡？'),
                            content: Text('确定要删除“${nameCtrl.text.trim()}”吗？'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: const Text('删除'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
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
