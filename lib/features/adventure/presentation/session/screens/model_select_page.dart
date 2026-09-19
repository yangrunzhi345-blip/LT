import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../core/feedback/app_feedback.dart';
import '../../../../../../core/theme/app_radius.dart';
import '../../../../../../core/theme/app_spacing.dart';
import '../../../../../../core/widgets/ui_foundation.dart';
import '../../../../../../models/llm_provider.dart';
import '../../../../../../models/model_capabilities.dart';
import '../../../../../../models/message.dart';
import '../../../../../../providers/riverpod_providers.dart';
import '../../../../../../screens/chat/widgets/chat_dialogs.dart';

/// 模型选择返回结果
class ModelSelectionResult {
  final LLMProvider provider;
  final String model;

  const ModelSelectionResult({
    required this.provider,
    required this.model,
  });
}

/// Navigation-first 统一语言模型选择页面
///
/// 替代原 session_app_bar 的 BottomSheet、showModelSwitchMenu 与 showRegenerateWithModelMenu
class ModelSelectPage extends ConsumerStatefulWidget {
  /// 是否为重新生成模式
  final bool isRegenerate;

  /// 重新生成对应的消息对象（若为重新生成模式）
  final Message? message;

  /// 初始指定的提供商（若未指定则从 chatProvider 读取）
  final LLMProvider? initialProvider;

  /// 初始指定的模型名称
  final String? initialModel;

  /// 模型选定回调
  final void Function(LLMProvider provider, String model)? onModelSelected;

  const ModelSelectPage({
    super.key,
    this.isRegenerate = false,
    this.message,
    this.initialProvider,
    this.initialModel,
    this.onModelSelected,
  });

  @override
  ConsumerState<ModelSelectPage> createState() => _ModelSelectPageState();
}

class _ModelSelectPageState extends ConsumerState<ModelSelectPage> {
  late LLMProvider _selectedProvider;
  late String _selectedModel;
  late TextEditingController _customModelCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final chat = ref.read(chatProvider);
    _selectedProvider = widget.initialProvider ?? chat.providerType;
    _selectedModel = widget.initialModel ?? chat.modelName;
    if (_selectedModel.isEmpty) {
      _selectedModel = _selectedProvider.defaultModel;
    }
    _customModelCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _customModelCtrl.dispose();
    super.dispose();
  }

  void _onProviderChanged(LLMProvider? provider) {
    if (provider == null || provider == _selectedProvider) return;
    final saved =
        ref.read(chatProvider).settingsProvider.getProviderModel(provider);
    setState(() {
      _selectedProvider = provider;
      _selectedModel = saved ?? provider.defaultModel;
      _customModelCtrl.clear();
    });
  }

  Future<void> _handleConfirm() async {
    if (_isSaving) return;
    final finalModel = _selectedModel.trim().isNotEmpty
        ? _selectedModel.trim()
        : _selectedProvider.defaultModel;

    if (finalModel.isEmpty) {
      AppFeedback.error(context, '请选择或输入有效的模型名称');
      return;
    }

    if (widget.isRegenerate &&
        (widget.message == null ||
            !ref.read(chatProvider).messages.contains(widget.message))) {
      AppFeedback.error(context, '消息已不在当前对话中，请返回刷新');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final chat = ref.read(chatProvider);
      await chat.setProvider(_selectedProvider);
      await chat.setModel(finalModel);

      if (widget.onModelSelected != null) {
        widget.onModelSelected!(_selectedProvider, finalModel);
      }

      if (!mounted) return;
      if (widget.isRegenerate && widget.message != null) {
        regenerateMessage(widget.message!, chat);
      }

      if (mounted) {
        AppFeedback.success(
          context,
          widget.isRegenerate ? '正在重新生成...' : '已切换至模型: $finalModel',
        );
        Navigator.of(context).pop(
          ModelSelectionResult(
            provider: _selectedProvider,
            model: finalModel,
          ),
        );
      }
    } catch (e, st) {
      debugPrint('[ModelSelectPage] _handleConfirm error: $e\n$st');
      if (mounted) AppFeedback.error(context, '模型切换失败，请重试');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chat = ref.watch(chatProvider);
    final recents = chat.settingsProvider.recentModels;

    final recommendedCaps = ModelCapabilityRegistry.pickerModels();

    return AppPageScaffold(
      title: widget.isRegenerate ? '选择模型重新生成' : '选择语言模型',
      titleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isRegenerate ? '选择模型重新生成' : '选择语言模型',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '当前: ${chat.modelName} (${chat.providerType.displayName})',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      bottomBar: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '已选模型',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _selectedModel.isNotEmpty ? _selectedModel : '未选定（使用默认）',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppPrimaryButton(
                key: const Key('model-select-confirm-button'),
                label: widget.isRegenerate ? '重新生成' : '确认应用',
                icon: widget.isRegenerate ? Icons.refresh_rounded : Icons.check,
                onPressed: _isSaving ? null : _handleConfirm,
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // 1. 提供商选择
          AppFormSection(
            title: '服务提供商',
            description: '选择官方 API 服务商或本地/第三方兼容服务',
            child: AppSelect<LLMProvider>(
              label: 'LLM 提供商',
              value: _selectedProvider,
              items: [
                for (final p in LLMProvider.values)
                  AppSelectItem(
                    value: p,
                    label: p.displayName,
                    subtitle: p.defaultBaseUrl.isNotEmpty
                        ? p.defaultBaseUrl
                        : '自定义端点 URL',
                  ),
              ],
              onChanged: _onProviderChanged,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 2. 最近使用的模型
          if (recents.isNotEmpty) ...[
            AppFormSection(
              title: '最近使用',
              description: '快速切换此前在此设备使用过的模型',
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: recents
                    .where((m) =>
                        _selectedProvider.knownModels.isEmpty ||
                        _selectedProvider.knownModels.contains(m))
                    .map((m) {
                  final isSelected = m == _selectedModel;
                  return ChoiceChip(
                    avatar: Icon(
                      Icons.history_rounded,
                      size: 16,
                      color: isSelected ? scheme.onPrimary : scheme.primary,
                    ),
                    label: Text(m),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedModel = m;
                        });
                      }
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // 3. 官方推荐模型（DeepSeek 模式下）
          if (_selectedProvider == LLMProvider.deepseek) ...[
            AppFormSection(
              title: '推荐在服模型',
              description: '针对文学创作与角色扮演优化的核心在服模型',
              child: Column(
                children: recommendedCaps.map((caps) {
                  final isSelected = _selectedModel == caps.modelId;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: () {
                        setState(() {
                          _selectedModel = caps.modelId;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? scheme.primaryContainer.withValues(alpha: 0.25)
                              : scheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: isSelected
                                ? scheme.primary
                                : scheme.outlineVariant.withValues(alpha: 0.5),
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color:
                                  isSelected ? scheme.primary : scheme.outline,
                              size: 20,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      Text(
                                        caps.modelId,
                                        softWrap: true,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (caps.supportsThinking)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: scheme.tertiaryContainer,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '深度思考',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              fontSize: 10,
                                              color: scheme.onTertiaryContainer,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (caps.pickerSubtitle != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      caps.pickerSubtitle!,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // 4. 自定义模型输入
          AppFormSection(
            title: '自定义模型名称',
            description: _selectedProvider == LLMProvider.deepseek
                ? '若需要调用 DeepSeek 其他专属模型，可在此手动输入'
                : '输入第三方兼容端点支持的模型标识（例如 gpt-4o, claude-3-5-sonnet 等）',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppTextField(
                    key: const Key('custom-model-input'),
                    controller: _customModelCtrl,
                    hintText: _selectedProvider.defaultModel.isNotEmpty
                        ? _selectedProvider.defaultModel
                        : '请输入模型名称...',
                    onChanged: (val) {
                      setState(() {
                        _selectedModel = val.trim();
                      });
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                FilledButton.tonal(
                  onPressed: () {
                    final text = _customModelCtrl.text.trim();
                    if (text.isNotEmpty) {
                      setState(() {
                        _selectedModel = text;
                      });
                      AppFeedback.info(context, '已选定自定义模型: $text');
                    }
                  },
                  child: const Text('应用'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
