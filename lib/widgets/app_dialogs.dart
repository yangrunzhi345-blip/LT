import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import '../providers/riverpod_providers.dart';
import '../models/llm_provider.dart';
import '../application/resource_library/edit_drafts.dart';
import '../core/feedback/app_feedback.dart';
import '../models/completion_params.dart';
import '../models/resource_library_mode.dart';
import '../core/theme/app_colors.dart';
import '../core/widgets/form_sub_page_scaffold.dart';
import '../core/widgets/narr_aitor_dropdown.dart';
import 'narr_aitor_loading.dart';

void showApiSettings(BuildContext context) {
  final provider =
      ProviderScope.containerOf(context, listen: false).read(chatProvider);
  // 保留当前选择。自定义接口是唯一允许编辑端点的类型，不能因打开旧版
  // 快捷设置而被静默切回 DeepSeek。
  LLMProvider selectedProvider = provider.providerType;
  String selectedModel = provider.modelName;
  final draftModels = <LLMProvider, String>{
    for (final p in LLMProvider.values)
      p: provider.settingsProvider.getProviderModel(p) ?? '',
  };
  // 按提供商加载对应 Key（而非始终读取当前 provider 的 Key）
  final draftKeys = <LLMProvider, String>{
    for (final p in LLMProvider.values)
      p: provider.settingsProvider.getProviderKey(p) ?? '',
  };
  final draftEndpoints = <LLMProvider, String>{
    for (final p in LLMProvider.values)
      p: provider.settingsProvider.getProviderBaseUrl(p),
  };
  draftEndpoints[selectedProvider] =
      provider.settingsProvider.getProviderBaseUrl(selectedProvider);
  final keyController = TextEditingController(
    text: draftKeys[selectedProvider] ?? '',
  );
  final endpointController = TextEditingController(
    text: draftEndpoints[selectedProvider] ?? selectedProvider.defaultBaseUrl,
  );
  final modelController = TextEditingController(
    text: draftModels[selectedProvider] ?? selectedModel,
  );
  var keyControllerDisposed = false;
  void disposeKeyController() {
    if (keyControllerDisposed) return;
    keyController.dispose();
    endpointController.dispose();
    modelController.dispose();
    keyControllerDisposed = true;
  }

  bool obscureKey = true;
  bool testing = false;
  String? testResult;
  CompletionParams params = provider.completionParams;

  void captureDraftForCurrentProvider() {
    draftKeys[selectedProvider] = keyController.text;
    draftEndpoints[selectedProvider] = endpointController.text;
    draftModels[selectedProvider] = modelController.text;
  }

  void switchProvider(LLMProvider nextProvider) {
    captureDraftForCurrentProvider();
    selectedProvider = nextProvider;
    final savedModel = draftModels[nextProvider] ?? '';
    selectedModel = nextProvider.availableModels.contains(savedModel)
        ? savedModel
        : (nextProvider.availableModels.contains(nextProvider.defaultModel)
            ? nextProvider.defaultModel
            : savedModel.isNotEmpty
                ? savedModel
                : nextProvider.defaultModel);
    modelController.text = selectedModel;
    keyController.text = draftKeys[nextProvider] ?? '';
    endpointController.text = nextProvider == LLMProvider.custom
        ? (draftEndpoints[nextProvider] ?? nextProvider.defaultBaseUrl)
        : nextProvider.defaultBaseUrl;
    testResult = null;
  }

  Future<void> doTest() async {
    try {
      final effectiveModel = selectedProvider == LLMProvider.custom
          ? modelController.text.trim()
          : selectedModel;
      final ok = await ProviderScope.containerOf(context, listen: false)
          .read(modelSettingsControllerProvider)
          .testConnection(
            provider: selectedProvider,
            apiKey: keyController.text.trim(),
            model: effectiveModel,
            endpoint: endpointController.text.trim(),
          );
      testResult = ok ? '连接成功' : '连接失败';
    } catch (e) {
      testResult = e.toString().split('\n').first;
    }
  }

  // 确保 selectedModel 在当前 provider 的列表中
  if (!selectedProvider.availableModels.contains(selectedModel)) {
    selectedModel = selectedProvider.defaultModel;
  }

  final page = showFormSubPage<void>(
    context: context,
    title: '⚙ 设置',
    maxWidth: 760,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(ctx).brightness == Brightness.dark
                  ? AppColors.darkSurface.withValues(alpha: 0.86)
                  : Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(ctx).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFE5EAF2),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6F7D92).withValues(alpha: 0.10),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProviderSegmentedControl(
                  selectedProvider: selectedProvider,
                  onChanged: (provider) {
                    setDialogState(() => switchProvider(provider));
                  },
                ),
                const SizedBox(height: 16),
                Divider(
                  height: 1,
                  color: Theme.of(ctx).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.10)
                      : const Color(0xFFE5EAF2),
                ),
                const SizedBox(height: 16),

                if (selectedProvider == LLMProvider.deepseek) ...[
                  _buildLabel('DeepSeek 官方在服模型'),
                  const SizedBox(height: 8),
                  NarrAItorDropdown<String>(
                    value: selectedModel.isEmpty ? null : selectedModel,
                    hintText: selectedProvider.defaultModel,
                    options: selectedProvider.availableModels
                        .map((model) => NarrAItorDropdownOption(
                              value: model,
                              label: model,
                              subtitle: model == 'deepseek-v4-flash'
                                  ? '284B MoE 极速主力推荐 (低延迟/高性价比/支持深度思考)'
                                  : model == 'deepseek-v4-pro'
                                      ? '1.6T MoE 旗舰全能长考 (多步逻辑推演/复杂任务/支持深度思考)'
                                      : '多模态实验模型 (支持图文多模态理解与分析)',
                              leading: Icon(
                                model == selectedProvider.defaultModel
                                    ? Icons.star_rounded
                                    : model == 'deepseek-v4-flash-vision-exp'
                                        ? Icons.image_search_rounded
                                        : Icons.psychology_rounded,
                                size: 16,
                                color: const Color(0xFF3C5DFF),
                              ),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        selectedModel = value;
                        modelController.text = value;
                        draftModels[selectedProvider] = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  // DeepSeek 思考与推理调优卡片
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).brightness == Brightness.dark
                          ? const Color(0xFF1B2436)
                          : const Color(0xFFF3F6FD),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF3C5DFF).withValues(alpha: 0.28),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.psychology,
                                size: 18, color: Color(0xFF3C5DFF)),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                '深度思考模式 (Thinking Mode)',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w700),
                              ),
                            ),
                            Switch(
                              value: params.enableThinking,
                              onChanged: (v) => setDialogState(() {
                                params = params.copyWith(enableThinking: v);
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text('推理强度 (Reasoning Effort)：',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children:
                              ['low', 'medium', 'high', 'max'].map((effort) {
                            final sel = params.reasoningEffort == effort;
                            return ChoiceChip(
                              label: Text(
                                effort == 'high'
                                    ? 'high (推荐)'
                                    : effort == 'max'
                                        ? 'max (极限)'
                                        : effort,
                                style: const TextStyle(fontSize: 11),
                              ),
                              selected: sel,
                              onSelected: (_) => setDialogState(() {
                                params =
                                    params.copyWith(reasoningEffort: effort);
                              }),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.bolt,
                                size: 14, color: Color(0xFF3C5DFF)),
                            SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Prompt Cache 原生支持 (省高达90%资费)；思考模式下温度自适应。',
                                style: TextStyle(
                                    fontSize: 11, color: Color(0xFF6F7D92)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── API Key ──
                Row(
                  children: [
                    const Text(
                      'API Key',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Text(
                      keyController.text.trim().isEmpty ? '未设置' : '已设置',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF4B73FF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: keyController,
                  scrollPadding: const EdgeInsets.only(bottom: 120),
                  obscureText: obscureKey,
                  onChanged: (_) => setDialogState(() {
                    draftKeys[selectedProvider] = keyController.text;
                  }),
                  decoration: _settingsFieldDecoration(
                    hintText: 'sk-...',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureKey ? Icons.visibility_off : Icons.visibility,
                        size: 18,
                      ),
                      onPressed: () =>
                          setDialogState(() => obscureKey = !obscureKey),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── API 端点 ──
                _buildLabel('API 端点'),
                const SizedBox(height: 8),
                TextField(
                  controller: endpointController,
                  scrollPadding: const EdgeInsets.only(bottom: 120),
                  readOnly: selectedProvider != LLMProvider.custom,
                  onChanged: selectedProvider == LLMProvider.custom
                      ? (_) => draftEndpoints[selectedProvider] =
                          endpointController.text
                      : null,
                  decoration: _settingsFieldDecoration(
                    hintText: selectedProvider.defaultBaseUrl.isEmpty
                        ? 'https://...'
                        : selectedProvider.defaultBaseUrl,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.copy, size: 16),
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: endpointController.text));
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('已复制 API 端点'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                if (selectedProvider == LLMProvider.custom) ...[
                  const SizedBox(height: 16),
                  _buildLabel('模型标识'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: modelController,
                    scrollPadding: const EdgeInsets.only(bottom: 120),
                    onChanged: (value) {
                      selectedModel = value;
                      draftModels[selectedProvider] = value;
                    },
                    decoration: _settingsFieldDecoration(
                      hintText: 'gpt-4.1-mini / claude-sonnet-5',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: modelController.text));
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('已复制模型标识'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),

                // ── 高级参数 ──
                const Text(
                  '高级参数',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                _ParamSlider(
                  label: 'Temperature',
                  value: params.temperature,
                  min: 0,
                  max: 2,
                  divisions: 40,
                  valueLabel: params.temperature.toStringAsFixed(2),
                  onChanged: (value) => setDialogState(() {
                    params = params.copyWith(temperature: value);
                  }),
                ),
                _ParamSlider(
                  label: 'Max Tokens',
                  value: params.maxTokens.toDouble(),
                  min: 512,
                  max: 32768,
                  divisions: 63,
                  valueLabel: params.maxTokens.toString(),
                  onChanged: (value) => setDialogState(() {
                    params = params.copyWith(maxTokens: value.round());
                  }),
                ),
                if (testResult != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [
                      Icon(
                        testResult == '连接成功'
                            ? Icons.check_circle
                            : Icons.error_outline,
                        size: 16,
                        color: testResult == '连接成功'
                            ? AppColors.success
                            : AppColors.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          testResult!,
                          style: TextStyle(
                            fontSize: 12,
                            color: testResult == '连接成功'
                                ? AppColors.success
                                : AppColors.error,
                          ),
                        ),
                      ),
                    ]),
                  ),
                const SizedBox(height: 18),

                // ── 按钮行 ──
                Row(children: [
                  TextButton.icon(
                    onPressed: testing
                        ? null
                        : () async {
                            setDialogState(() {
                              testing = true;
                              testResult = null;
                            });
                            await doTest();
                            setDialogState(() => testing = false);
                          },
                    icon: testing
                        ? const NarrAItorLoading.mini()
                        : const Icon(Icons.wifi_find, size: 18),
                    label: Text(testing ? '测试中...' : '测试连接'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      captureDraftForCurrentProvider();
                      final effectiveModel =
                          selectedProvider == LLMProvider.custom
                              ? modelController.text.trim()
                              : selectedModel;
                      Navigator.pop(ctx);
                      final prov =
                          ProviderScope.containerOf(context, listen: false)
                              .read(chatProvider);
                      prov.setProvider(selectedProvider);
                      prov.settingsProvider.setApiBaseUrl(
                        (draftEndpoints[selectedProvider] ?? '').trim(),
                      );
                      if (effectiveModel.isNotEmpty) {
                        prov.setModel(effectiveModel);
                      }
                      prov.settingsProvider.setApiKey(
                        (draftKeys[selectedProvider] ?? '').trim(),
                      );
                      prov.settingsProvider.setCompletionParams(params);
                    },
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('保存'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  unawaited(page.whenComplete(disposeKeyController));
}

class _ProviderSegmentedControl extends StatelessWidget {
  final LLMProvider selectedProvider;
  final ValueChanged<LLMProvider> onChanged;

  const _ProviderSegmentedControl({
    required this.selectedProvider,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFFE1E1E1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _tab(context, LLMProvider.deepseek, 'DeepSeek 官方 API'),
          _tab(context, LLMProvider.custom, '自定义 (OpenAI 兼容)'),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, LLMProvider provider, String label) {
    final selected = selectedProvider == provider;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onChanged(provider),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? AppColors.darkSurfaceElevated : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              providerBrandIcon(provider, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? const Color(0xFF4B73FF)
                      : (isDark ? Colors.white54 : const Color(0xFF6F7D92)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

InputDecoration _settingsFieldDecoration({
  required String hintText,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    hintText: hintText,
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.70),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE5EAF2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE5EAF2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF4B73FF)),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    isDense: true,
    suffixIcon: suffixIcon,
  );
}

class _ParamSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  const _ParamSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6F7D92),
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              valueLabel,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF4B73FF),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFF4B73FF),
            inactiveTrackColor: const Color(0xFFE5EAF2),
            thumbColor: const Color(0xFF4B73FF),
            overlayColor: const Color(0xFF4B73FF).withValues(alpha: 0.12),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// 字段标签
Widget _buildLabel(String text) {
  return Text(text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600));
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
                              )
                                  .read(aiImportServiceProvider)
                                  .importChat(
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
Future<void> showCreateCharacterCardDialog(BuildContext context,
    {Map<String, dynamic>? existingCard,
    String? existingId,
    ResourceLibraryMode mode = ResourceLibraryMode.adventure}) async {
  final isEdit = existingCard != null;
  final draft =
      CharacterCardEditDraft.fromExisting(existingCard, existingId: existingId);
  final nameCtrl = TextEditingController(text: draft.name);
  final ageCtrl = TextEditingController(text: draft.age);
  final profCtrl = TextEditingController(text: draft.profession);
  final persCtrl = TextEditingController(text: draft.personality);
  final bgCtrl = TextEditingController(text: draft.description);
  final appearCtrl = TextEditingController(text: draft.appearance);
  final factionCtrl = TextEditingController(text: draft.faction);
  final locationCtrl = TextEditingController(text: draft.homeLocation);
  final goalCtrl = TextEditingController(text: draft.publicGoal);
  final motivationCtrl = TextEditingController(text: draft.hiddenMotivation);
  final abilitySourceCtrl = TextEditingController(text: draft.abilitySource);
  final abilityCostCtrl = TextEditingController(text: draft.abilityCost);
  final tabooCtrl = TextEditingController(text: draft.taboosText);
  final relationshipCtrl = TextEditingController(text: draft.relationshipNotes);
  String gender = draft.gender;
  final customGenderCtrl = TextEditingController(text: draft.customGender);
  bool isCustomGender = draft.isCustomGender;

  // 在打开编辑页前加载，避免已有绑定因下拉选项尚未刷新而显示为“无”。
  List<Map<String, dynamic>> worldviewList = [];
  String matchingWorldviewId =
      existingCard?['matching_worldview_id'] as String? ?? '';
  try {
    final crud = ProviderScope.containerOf(context, listen: false)
        .read(resourceCrudControllerProvider);
    worldviewList = await crud.loadWorldviewPresets(mode: mode);
  } catch (_) {}
  if (!context.mounted) return;

  final sheet = showFormSubPage<void>(
    context: context,
    title: isEdit ? '编辑角色卡' : '新建角色卡',
    maxWidth: 760,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => Padding(
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
            // Header
            Row(children: [
              Icon(isEdit ? Icons.edit : Icons.person_add,
                  size: 20, color: AppColors.accent),
              const SizedBox(width: 8),
              const Text('角色卡信息',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 16),
            // Form fields
            Flexible(
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  NarrAItorDropdown<String>(
                    value: matchingWorldviewId.isEmpty
                        ? null
                        : matchingWorldviewId,
                    label: '契合世界观（可选）',
                    options: [
                      const NarrAItorDropdownOption<String>(
                          value: null, label: '无'),
                      ...worldviewList
                          .map((wv) => NarrAItorDropdownOption<String>(
                                value: wv['id'] as String?,
                                label: wv['name'] as String? ?? '',
                              )),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => matchingWorldviewId = v ?? ''),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameCtrl,
                    scrollPadding: const EdgeInsets.only(bottom: 120),
                    decoration: const InputDecoration(
                        labelText: '姓名 *',
                        border: OutlineInputBorder(),
                        isDense: true),
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: NarrAItorDropdown<String>(
                        value: gender,
                        label: '性别',
                        options: ['男', '女', '其他']
                            .map((g) =>
                                NarrAItorDropdownOption(value: g, label: g))
                            .toList(),
                        onChanged: (v) => setDialogState(() {
                          gender = v ?? '男';
                          isCustomGender = gender == '其他';
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('年龄',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: ageCtrl,
                            scrollPadding: const EdgeInsets.only(bottom: 120),
                            decoration: const InputDecoration(
                                hintText: '年龄',
                                border: OutlineInputBorder(),
                                isDense: true),
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      ),
                    ),
                  ]),
                  if (isCustomGender) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: customGenderCtrl,
                      decoration: const InputDecoration(
                          labelText: '自定义性别',
                          border: OutlineInputBorder(),
                          isDense: true),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: profCtrl,
                    scrollPadding: const EdgeInsets.only(bottom: 120),
                    decoration: const InputDecoration(
                        labelText: '职业/身份',
                        border: OutlineInputBorder(),
                        isDense: true),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: persCtrl,
                    scrollPadding: const EdgeInsets.only(bottom: 120),
                    decoration: const InputDecoration(
                        labelText: '性格',
                        border: OutlineInputBorder(),
                        isDense: true),
                    maxLines: 3,
                    minLines: 2,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: bgCtrl,
                    scrollPadding: const EdgeInsets.only(bottom: 120),
                    decoration: const InputDecoration(
                        labelText: '背景故事',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                        isDense: true),
                    maxLines: 6,
                    minLines: 3,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: appearCtrl,
                    scrollPadding: const EdgeInsets.only(bottom: 120),
                    decoration: const InputDecoration(
                        labelText: '外貌描述',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                        isDense: true),
                    maxLines: 3,
                    minLines: 2,
                  ),
                  const SizedBox(height: 10),
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('世界内设定',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                      controller: factionCtrl,
                      decoration: const InputDecoration(
                          labelText: '所属势力',
                          border: OutlineInputBorder(),
                          isDense: true)),
                  const SizedBox(height: 10),
                  TextField(
                      controller: locationCtrl,
                      decoration: const InputDecoration(
                          labelText: '活动地点 / 家乡',
                          border: OutlineInputBorder(),
                          isDense: true)),
                  const SizedBox(height: 10),
                  TextField(
                      controller: goalCtrl,
                      decoration: const InputDecoration(
                          labelText: '公开目标',
                          border: OutlineInputBorder(),
                          isDense: true)),
                  const SizedBox(height: 10),
                  TextField(
                      controller: motivationCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: '隐藏动机（供叙事使用）',
                          border: OutlineInputBorder(),
                          isDense: true)),
                  const SizedBox(height: 10),
                  TextField(
                      controller: abilitySourceCtrl,
                      decoration: const InputDecoration(
                          labelText: '能力来源',
                          border: OutlineInputBorder(),
                          isDense: true)),
                  const SizedBox(height: 10),
                  TextField(
                      controller: abilityCostCtrl,
                      decoration: const InputDecoration(
                          labelText: '能力代价 / 限制',
                          border: OutlineInputBorder(),
                          isDense: true)),
                  const SizedBox(height: 10),
                  TextField(
                      controller: tabooCtrl,
                      decoration: const InputDecoration(
                          labelText: '禁忌（用“、”分隔）',
                          border: OutlineInputBorder(),
                          isDense: true)),
                  const SizedBox(height: 10),
                  TextField(
                      controller: relationshipCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: '关系网络备注',
                          border: OutlineInputBorder(),
                          isDense: true)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            // Bottom buttons
            Row(children: [
              if (isEdit)
                TextButton(
                  onPressed: () async {
                    final crudController = ProviderScope.containerOf(
                      context,
                      listen: false,
                    ).read(resourceCrudControllerProvider);
                    final confirm = await showDialog<bool>(
                      context: ctx,
                      builder: (c) => AlertDialog(
                        title: const Text('确认删除'),
                        content: Text('确定要删除角色卡「${nameCtrl.text.trim()}」吗？'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('取消')),
                          TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('删除',
                                  style: TextStyle(color: AppColors.error))),
                        ],
                      ),
                    );
                    if (confirm != true) return;
                    final result = await crudController.deleteCharacterCard(
                      existingId!,
                      mode: mode,
                    );
                    if (!result.success) {
                      debugPrint(
                          '[CreateCardDialog] 删除失败: ${result.errorMessage}');
                      if (ctx.mounted) {
                        AppFeedback.error(
                            ctx, '删除角色卡失败: ${result.errorMessage}');
                      }
                      return;
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('删除',
                      style: TextStyle(color: AppColors.error)),
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
                      const SnackBar(content: Text('请至少填写姓名')),
                    );
                    return;
                  }
                  draft.name = name;
                  draft.gender = gender;
                  draft.customGender = customGenderCtrl.text.trim();
                  draft.age = ageCtrl.text.trim();
                  draft.profession = profCtrl.text.trim();
                  draft.personality = persCtrl.text.trim();
                  draft.description = bgCtrl.text.trim();
                  draft.appearance = appearCtrl.text.trim();
                  draft.faction = factionCtrl.text.trim();
                  draft.homeLocation = locationCtrl.text.trim();
                  draft.publicGoal = goalCtrl.text.trim();
                  draft.hiddenMotivation = motivationCtrl.text.trim();
                  draft.abilitySource = abilitySourceCtrl.text.trim();
                  draft.abilityCost = abilityCostCtrl.text.trim();
                  draft.taboosText = tabooCtrl.text;
                  draft.relationshipNotes = relationshipCtrl.text.trim();
                  draft.worldviewId = matchingWorldviewId;
                  final result = await ProviderScope.containerOf(
                    context,
                    listen: false,
                  ).read(resourceCrudControllerProvider).saveCharacterCardDraft(
                        draft,
                        mode: mode,
                      );
                  if (!result.success) {
                    final message = result.errorMessage ?? '未知错误';
                    debugPrint('[CreateCardDialog] 保存失败: $message');
                    if (ctx.mounted) {
                      AppFeedback.error(ctx, '保存失败：$message');
                    }
                    return;
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(isEdit ? '保存' : '创建'),
              ),
            ]),
          ],
        ),
      ),
    ),
  );

  unawaited(sheet.whenComplete(() {
    for (final c in [
      nameCtrl,
      ageCtrl,
      profCtrl,
      persCtrl,
      bgCtrl,
      appearCtrl,
      factionCtrl,
      locationCtrl,
      goalCtrl,
      motivationCtrl,
      abilitySourceCtrl,
      abilityCostCtrl,
      tabooCtrl,
      relationshipCtrl,
      customGenderCtrl,
    ]) {
      c.dispose();
    }
  }));
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
