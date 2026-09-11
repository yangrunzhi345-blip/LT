import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../models/completion_params.dart';
import '../../../../providers/riverpod_providers.dart';

/// 模型生成参数与推理超参调节卡片
class ModelParamsSection extends ConsumerWidget {
  const ModelParamsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final chat = ref.watch(chatProvider);
    final settings = chat.settingsProvider;
    final params = settings.completionParams;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 深度思考 (Deep Thinking) 特性专区卡片
        Material(
          color: isDark
              ? colorScheme.surfaceContainerLow
              : colorScheme.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(
              color: params.enableThinking
                  ? colorScheme.primary.withValues(alpha: 0.4)
                  : colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: params.enableThinking ? 1.5 : 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
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
                        Icons.psychology_rounded,
                        color: colorScheme.primary,
                        size: 22,
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
                                '深度思考引擎',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary
                                      .withValues(alpha: 0.15),
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.full),
                                ),
                                child: Text(
                                  'V4.1 原生思考',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.primary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '针对复杂多支线冒险与世界观逻辑推演，开启前置内心独白与逻辑规划 (DeepSeek V4.1 原生思维链)',
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
                const SizedBox(height: AppSpacing.sm),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('世界观深度推演生成'),
                  subtitle: const Text(
                    '世界观 AI 导入允许使用 V4.1 深度推演；默认关闭以降低首 Token 延迟',
                  ),
                  value: settings.worldviewDeepThinkingGeneration,
                  onChanged: settings.setWorldviewDeepThinkingGeneration,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('角色卡深度推演生成'),
                  subtitle: const Text(
                    '角色卡 AI 导入允许使用 V4.1 深度推演；默认关闭以优先快速生成',
                  ),
                  value: settings.characterCardDeepThinkingGeneration,
                  onChanged: settings.setCharacterCardDeepThinkingGeneration,
                ),

                const SizedBox(height: AppSpacing.sm),

                // 深度思考开关 (保持测试用例关键词)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '启用深度思考模式 (Deep Thinking)',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '开启后模型在生成剧情前输出可折叠的思维链推演过程',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: params.enableThinking,
                  onChanged: (val) {
                    settings.setCompletionParams(
                      params.copyWith(enableThinking: val),
                    );
                  },
                ),

                if (params.enableThinking) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '思考强度 (Reasoning Effort)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _effortDescription(params.reasoningEffort),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs + 4),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'low',
                        label: Text('轻度'),
                        icon: Icon(Icons.flash_on_rounded, size: 16),
                      ),
                      ButtonSegment(
                        value: 'medium',
                        label: Text('适中'),
                        icon: Icon(Icons.bolt_rounded, size: 16),
                      ),
                      ButtonSegment(
                        value: 'high',
                        label: Text('深度'),
                        icon: Icon(Icons.auto_awesome_rounded, size: 16),
                      ),
                      ButtonSegment(
                        value: 'max',
                        label: Text('极强'),
                        icon: Icon(Icons.all_inclusive_rounded, size: 16),
                      ),
                    ],
                    selected: {params.reasoningEffort},
                    onSelectionChanged: (set) {
                      settings.setCompletionParams(
                        params.copyWith(reasoningEffort: set.first),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // 2. 核心推理超参数调节主卡片
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
                      Icons.tune_rounded,
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
                          '推理超参与采样调节',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '调整温度、采样阈值与深度思考强度以平衡文采与逻辑一致性',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (params.enableThinking) ...[
                          const SizedBox(height: 4),
                          Text(
                            '💡 提示：DeepSeek V4.1 思考模式下采样超参由模型自适应管理；非思考模式固定 top_p=1.0，仅温度可调。',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
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

              // 温度 Temperature 滑块
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '生成温度 (Temperature)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '0.0 绝对严谨精确 ↔ 2.0 天马行空丰富',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      params.temperature.toStringAsFixed(2),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Slider(
                value: params.temperature,
                min: 0.0,
                max: 2.0,
                divisions: 40,
                label: params.temperature.toStringAsFixed(2),
                onChanged: (val) {
                  settings.setCompletionParams(
                    params.copyWith(temperature: val),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.sm),

              // Top-P 滑块
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '核采样概率 (Top-P)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '累积概率截断阈值，推荐保持 0.90 ~ 0.95',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      params.topP.toStringAsFixed(2),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Slider(
                value: params.topP,
                min: 0.1,
                max: 1.0,
                divisions: 18,
                label: params.topP.toStringAsFixed(2),
                onChanged: (val) {
                  settings.setCompletionParams(params.copyWith(topP: val));
                },
              ),
              const SizedBox(height: AppSpacing.sm),

              // 最大输出 Token
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '单次最大生成长度 (Max Tokens)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '限制单回合对话的最大 Token 预算',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      '${params.maxTokens} T',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Slider(
                value: params.maxTokens.toDouble(),
                min: 512,
                max: 8192,
                divisions: 15,
                label: '${params.maxTokens}',
                onChanged: (val) {
                  settings.setCompletionParams(
                    params.copyWith(maxTokens: val.toInt()),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),

              // 底部工具栏
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '提示：参数变动实时生效，无需手动保存',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      settings.setCompletionParams(const CompletionParams());
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已恢复官方推荐默认参数'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.restore_rounded, size: 16),
                    label: const Text('恢复默认推荐'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
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

  static String _effortDescription(String effort) => switch (effort) {
        'low' => '轻度推演 · 极速响应',
        'medium' => '平衡推演 · 推荐日常',
        'max' => '极致演算 · 严谨逻辑',
        _ => '深度思考 · 丰富细节',
      };
}
