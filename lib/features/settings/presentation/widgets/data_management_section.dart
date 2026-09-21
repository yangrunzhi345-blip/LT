import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/diagnostics/diagnostic_session_export_use_case.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../providers/riverpod_providers.dart';

/// 数据用量统计、TTS 与持久化管理卡片
class DataManagementSection extends ConsumerStatefulWidget {
  const DataManagementSection({super.key});

  @override
  ConsumerState<DataManagementSection> createState() =>
      _DataManagementSectionState();
}

class _DataManagementSectionState extends ConsumerState<DataManagementSection> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chat = ref.watch(chatProvider);
    // 朗读状态由全局 Authority 驱动；这里直接监听它，避免本页维护伪状态。
    final readAloud = ref.watch(readAloudControllerProvider);

    final tokenSummary = chat.getTokenSummary();
    final sessionTokens = tokenSummary['sessionTokens'] as int? ?? 0;
    final totalTokens = tokenSummary['totalTokens'] as int? ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 数据管理与用量统计主卡片
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
                      Icons.storage_rounded,
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
                          '数据管理与用量统计',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '查看 Token 消耗、语音 TTS 播报设置与存储管理',
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

              // Token 用量统计卡片组
              Text(
                '本地 Token 消耗估算',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs + 4),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: colorScheme.outlineVariant
                              .withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.bolt_rounded,
                                size: 14,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text('本次会话', style: theme.textTheme.bodySmall),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$sessionTokens',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '当前场景消耗 Tokens',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: colorScheme.outlineVariant
                              .withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.all_inclusive_rounded,
                                size: 14,
                                color: colorScheme.secondary,
                              ),
                              const SizedBox(width: 4),
                              Text('累计总量', style: theme.textTheme.bodySmall),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$totalTokens',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: colorScheme.secondary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '本地记录历史累计 Tokens',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // 语音 TTS 播报设置（全局唯一朗读 Authority 的偏好）
              Text(
                '语音消息朗读 (TTS)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs + 2),
              Row(
                children: [
                  Icon(
                    readAloud.capability.supported
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    size: 16,
                    color: readAloud.capability.supported
                        ? colorScheme.primary
                        : colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      readAloud.capability.supported
                          ? '当前平台支持系统语音朗读，可在对话与创作工作台中使用。'
                          : (readAloud.capability.message ?? '当前平台不支持朗读'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    Icons.volume_up_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                ),
                title: const Text('启用语音朗读'),
                subtitle: const Text('支持在对话、创作工作台与组装预览中朗读正文'),
                value: readAloud.enabled,
                onChanged: (val) {
                  unawaited(readAloud.setEnabled(val));
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 18,
                    color: colorScheme.secondary,
                  ),
                ),
                title: const Text('完成时自动朗读'),
                subtitle: const Text('当 AI 生成完完整剧情后自动进行语音播报'),
                value: readAloud.autoRead,
                onChanged: (val) {
                  unawaited(readAloud.setAutoRead(val));
                },
              ),
              _ReadAloudSlider(
                label: '语速',
                value: readAloud.rate,
                min: 0.0,
                max: 1.0,
                enabled: readAloud.enabled,
                onChanged: (value) => unawaited(readAloud.setRate(value)),
              ),
              _ReadAloudSlider(
                label: '音调',
                value: readAloud.pitch,
                min: 0.5,
                max: 2.0,
                enabled: readAloud.enabled,
                onChanged: (value) => unawaited(readAloud.setPitch(value)),
              ),
              const SizedBox(height: AppSpacing.lg),

              Text(
                '诊断数据导出',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs + 2),
              Text(
                '仅导出当前冒险分支最近 30 回合；API 凭证与隐藏推理不会写入文件。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.icon(
                onPressed: chat.currentAdventureId == null
                    ? null
                    : _showDiagnosticExportConfirmation,
                icon: const Icon(Icons.download_rounded),
                label: const Text('导出诊断会话 JSON'),
              ),
              const SizedBox(height: AppSpacing.lg),

              // 缓存清理与重置
              Text(
                '缓存与存储管理',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs + 4),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已清空会话临时缓存与重置计数器'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                    label: const Text('清空临时缓存'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _confirmClearHistory(context),
                    icon: Icon(
                      Icons.delete_sweep_rounded,
                      size: 18,
                      color: colorScheme.error,
                    ),
                    label: Text(
                      '清空历史对话',
                      style: TextStyle(color: colorScheme.error),
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

  Future<void> _showDiagnosticExportConfirmation() async {
    final confirmed = await AppConfirmDialog.show(
      context: context,
      title: '导出诊断会话',
      message: '将导出当前冒险分支最近 30 回合。对话正文会保留，API 凭证和隐藏推理会被排除。',
      confirmLabel: '导出',
    );
    if (confirmed && mounted) {
      await _exportDiagnosticSession();
    }
  }

  Future<void> _exportDiagnosticSession() async {
    final chat = ref.read(chatProvider);
    final adventureId = chat.currentAdventureId;
    if (adventureId == null) return;

    Map<String, dynamic>? adventure;
    for (final item in chat.adventureList) {
      if (item['id'] == adventureId) {
        adventure = item;
        break;
      }
    }
    final path = await DiagnosticSessionExportUseCase(
      repository: ref.read(adventureRepoProvider),
    ).saveToFile(
      adventureId: adventureId,
      branchId: chat.currentBranchId,
      title: adventure?['title']?.toString(),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          path == null ? '诊断导出失败，请稍后重试。' : '诊断会话已导出：$path',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _confirmClearHistory(BuildContext context) async {
    final confirmed = await AppConfirmDialog.show(
      context: context,
      title: '清空历史对话记录',
      message: '确定要清空所有过去的对话存档吗？\n世界观与角色卡资产将保留，但场景聊天历史将无法恢复。',
      confirmLabel: '确认清空',
      isDanger: true,
    );

    if (confirmed == true && mounted) {
      final chat = ref.read(chatProvider);
      final list = List<Map<String, dynamic>>.from(chat.adventureList);
      for (final item in list) {
        final id = item['id'] as int?;
        if (id != null) {
          await chat.deleteAdventure(id);
        }
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已成功清理所有历史会话记录'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}

/// 朗读偏好数值滑杆（语速/音调）。
///
/// 用 [Expanded] 让标签占据剩余宽度，保证 320px 窄屏与放大字体下不溢出。
class _ReadAloudSlider extends StatelessWidget {
  const _ReadAloudSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: theme.textTheme.bodyMedium),
            ),
            Text(
              value.toStringAsFixed(2),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }
}
