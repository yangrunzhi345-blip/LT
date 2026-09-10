import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_dropdown.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../models/llm_provider.dart';
import '../../../../providers/riverpod_providers.dart';
import '../../../../services/api_error.dart';

/// 模型提供商与 API Key 安全配置卡片
class ProviderConfigSection extends ConsumerStatefulWidget {
  const ProviderConfigSection({super.key});

  @override
  ConsumerState<ProviderConfigSection> createState() =>
      _ProviderConfigSectionState();
}

class _ProviderConfigSectionState extends ConsumerState<ProviderConfigSection> {
  late final TextEditingController _keyController;
  late final TextEditingController _endpointController;
  late final TextEditingController _modelController;

  bool _isTesting = false;
  bool? _testSuccess;
  String? _testMessage;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(chatProvider).settingsProvider;
    _keyController = TextEditingController(text: settings.apiKey);
    _endpointController = TextEditingController(text: settings.apiBaseUrl);
    _modelController = TextEditingController(text: settings.modelName);
  }

  @override
  void dispose() {
    _keyController.dispose();
    _endpointController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final settings = ref.read(chatProvider).settingsProvider;
    final apiKey = _keyController.text.trim();
    if (apiKey.isEmpty) {
      setState(() {
        _isTesting = false;
        _testSuccess = false;
        _testMessage = '请先输入有效的 API 密钥';
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testSuccess = null;
      _testMessage = null;
    });

    final stopwatch = Stopwatch()..start();
    try {
      await settings.setApiKey(apiKey);
      await settings.setApiBaseUrl(_endpointController.text.trim());
      if (_modelController.text.trim().isNotEmpty) {
        await settings.setModel(_modelController.text.trim());
      }
      final success = await settings.testCurrentLlmConnection();
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _isTesting = false;
        _testSuccess = success;
        _testMessage = success
            ? '连接成功！耗时 ${stopwatch.elapsedMilliseconds}ms，服务状态极佳。'
            : '连接失败，请核对密钥是否正确及网络是否通畅。';
      });
    } catch (e) {
      stopwatch.stop();
      if (!mounted) return;
      final displayError = e is ApiError
          ? e.message
          : e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _isTesting = false;
        _testSuccess = false;
        _testMessage = '连接失败: $displayError';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final chat = ref.watch(chatProvider);
    final settings = chat.settingsProvider;

    final selectedProvider = settings.providerType;
    final models = selectedProvider.availableModels;
    final isKeyConfigured = settings.isKeyConfigured;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 顶部运行时状态概览卡片
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: isDark
                ? colorScheme.surfaceContainerLow
                : colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isKeyConfigured
                  ? colorScheme.primary.withValues(alpha: 0.35)
                  : colorScheme.outlineVariant.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isKeyConfigured
                      ? colorScheme.primary.withValues(alpha: 0.15)
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  selectedProvider == LLMProvider.deepseek
                      ? Icons.bolt_rounded
                      : Icons.alt_route_rounded,
                  color: isKeyConfigured
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          selectedProvider.displayName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs + 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: isKeyConfigured
                                ? const Color(0xFF10B981)
                                    .withValues(alpha: 0.15)
                                : colorScheme.errorContainer
                                    .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                          child: Text(
                            isKeyConfigured ? '已就绪' : '未就绪',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isKeyConfigured
                                  ? const Color(0xFF10B981)
                                  : colorScheme.error,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '模型: ${settings.modelName} · 端点: ${settings.apiBaseUrl}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _isTesting ? null : _testConnection,
                icon: _isTesting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.network_check_rounded, size: 16),
                label: Text(_isTesting ? '检测中' : '快速测通'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // 2. 核心提供商与接口配置主卡片
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(
                      Icons.api_rounded,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm + 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LLM 服务提供商',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '选择并配置场景对话与推理使用的核心语言模型服务',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              const SizedBox(height: AppSpacing.md),

              // 提供商单选分段
              Text(
                '模型提供商',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs + 2),
              SegmentedButton<LLMProvider>(
                segments: LLMProvider.values.map((p) {
                  return ButtonSegment(
                    value: p,
                    label: Text(p.displayName),
                    icon: Icon(
                      p == LLMProvider.deepseek ? Icons.bolt : Icons.tune,
                    ),
                  );
                }).toList(),
                selected: {selectedProvider},
                onSelectionChanged: (set) async {
                  final newProvider = set.first;
                  await settings.setProviderType(newProvider);
                  _endpointController.text = settings.apiBaseUrl;
                  _keyController.text = settings.apiKey;
                  _modelController.text = settings.modelName;
                  setState(() {
                    _testSuccess = null;
                    _testMessage = null;
                  });
                },
              ),
              const SizedBox(height: AppSpacing.md),

              // 模型选择
              if (selectedProvider == LLMProvider.deepseek) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '选择在服模型',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '默认推荐 deepseek-v4-flash 极速流畅交互',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs + 2),
                AppDropdown<String>.form(
                  value: models.contains(settings.modelName)
                      ? settings.modelName
                      : models.first,
                  options: models.map((m) {
                    final isFlash = m == 'deepseek-v4-flash';
                    return AppDropdownOption<String>(
                      value: m,
                      label: m,
                      leading: Icon(
                        isFlash
                            ? Icons.bolt_rounded
                            : Icons.psychology_outlined,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                      subtitle:
                          isFlash ? '(V4 极速叙事与角色卡 · 默认)' : '(V4 旗舰全能长考与推演)',
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      settings.setModel(val);
                      _modelController.text = val;
                    }
                  },
                ),
              ] else ...[
                AppTextField(
                  controller: _modelController,
                  label: '自定义模型名称',
                  hintText: '如 gpt-4o, llama-3.3-70b, qwen-max',
                  onChanged: (val) => settings.setModel(val.trim()),
                ),
              ],
              const SizedBox(height: AppSpacing.md),

              // API Endpoint
              AppTextField(
                controller: _endpointController,
                label: 'API 服务端点 (Base URL)',
                readOnly: selectedProvider != LLMProvider.custom,
                hintText: selectedProvider.defaultBaseUrl.isEmpty
                    ? 'https://api.example.com/v1'
                    : selectedProvider.defaultBaseUrl,
                prefixIcon: const Icon(Icons.link, size: 20),
                onChanged: (val) => settings.setApiBaseUrl(val.trim()),
              ),
              const SizedBox(height: AppSpacing.md),

              // API Key
              AppTextField(
                controller: _keyController,
                label: 'API 密钥 (API Key)',
                hintText: 'sk-...',
                isPassword: true,
                prefixIcon: const Icon(Icons.key_rounded, size: 20),
                onChanged: (val) => settings.setApiKey(val.trim()),
              ),
              const SizedBox(height: AppSpacing.sm),

              // 安全存储提示
              Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '密钥加密存储于本地设备 SQLite 数据库，永远不会经由中间服务器转存',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // 测试连通性按钮与结果反馈
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _isTesting ? null : _testConnection,
                    icon: _isTesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.network_check_rounded, size: 18),
                    label: Text(_isTesting ? '正在测试...' : '测试连通性'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  if (_testMessage != null)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _testSuccess == true
                              ? const Color(0xFF10B981).withValues(alpha: 0.12)
                              : colorScheme.errorContainer
                                  .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: _testSuccess == true
                                ? const Color(0xFF10B981).withValues(alpha: 0.4)
                                : colorScheme.error.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _testSuccess == true
                                  ? Icons.check_circle_rounded
                                  : Icons.error_rounded,
                              size: 18,
                              color: _testSuccess == true
                                  ? const Color(0xFF10B981)
                                  : colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _testMessage!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: _testSuccess == true
                                      ? const Color(0xFF10B981)
                                      : colorScheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
