import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/diagnostics/diagnostic_session_export_use_case.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../domain/read_aloud/read_aloud_contracts.dart';
import '../../../../providers/riverpod_providers.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// 数据用量统计、TTS 与持久化管理卡片
class DataManagementSection extends ConsumerStatefulWidget {
  const DataManagementSection({super.key});

  @override
  ConsumerState<DataManagementSection> createState() =>
      _DataManagementSectionState();
}

class _DataManagementSectionState extends ConsumerState<DataManagementSection> {
  @override
  void initState() {
    super.initState();
    // 可用语言必须来自系统真实能力：进入设置页时查询一次（幂等，不可用平台
    // 或后端不提供枚举时安全收敛为空集合）。
    unawaited(ref.read(readAloudControllerProvider).refreshLanguages());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
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
                          l10n.dataManagementTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          l10n.dataManagementSubtitle,
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
                l10n.tokenUsageTitle,
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
                              Text(l10n.tokenCurrentScene,
                                  style: theme.textTheme.bodySmall),
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
                            l10n.tokenCurrentSceneDescription,
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
                              Text(l10n.tokenHistoryTotal,
                                  style: theme.textTheme.bodySmall),
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
                            l10n.tokenHistoryDescription,
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
                l10n.readAloudSectionTitle,
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
                          ? l10n.readAloudPlatformSupportedMessage
                          : (readAloud.capability.message ??
                              l10n.readAloudUnsupportedPlatform),
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
                title: Text(l10n.readAloudEnable),
                subtitle: Text(l10n.readAloudEnableSubtitle),
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
                title: Text(l10n.readAloudAutoRead),
                subtitle: Text(l10n.readAloudAutoReadSubtitle),
                value: readAloud.autoRead,
                onChanged: (val) {
                  unawaited(readAloud.setAutoRead(val));
                },
              ),
              _ReadAloudSlider(
                label: l10n.readAloudRateLabel,
                value: readAloud.rate,
                min: 0.0,
                max: 1.0,
                enabled: readAloud.enabled,
                onChanged: (value) => unawaited(readAloud.setRate(value)),
              ),
              _ReadAloudSlider(
                label: l10n.readAloudPitchLabel,
                value: readAloud.pitch,
                min: 0.5,
                max: 2.0,
                enabled: readAloud.enabled,
                onChanged: (value) => unawaited(readAloud.setPitch(value)),
              ),
              const SizedBox(height: AppSpacing.md),
              const _ReadAloudLanguagePicker(),
              const SizedBox(height: AppSpacing.lg),

              Text(
                l10n.diagnosticExportTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs + 2),
              Text(
                l10n.diagnosticExportSubtitle,
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
                label: Text(l10n.exportDiagnosticJson),
              ),
              const SizedBox(height: AppSpacing.lg),

              // 缓存清理与重置
              Text(
                l10n.cacheStorageTitle,
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
                        SnackBar(
                          content: Text(l10n.clearCacheSuccess),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                    label: Text(l10n.clearCache),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _confirmClearHistory(context),
                    icon: Icon(
                      Icons.delete_sweep_rounded,
                      size: 18,
                      color: colorScheme.error,
                    ),
                    label: Text(
                      l10n.clearAllData,
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
      title: AppLocalizations.of(context)!.diagnosticExportTitle,
      message: AppLocalizations.of(context)!.diagnosticExportSubtitle,
      confirmLabel: AppLocalizations.of(context)!.exportDiagnosticJson,
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
          path == null
              ? AppLocalizations.of(context)!.diagnosticExportFailed
              : AppLocalizations.of(context)!.diagnosticExported(path),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _confirmClearHistory(BuildContext context) async {
    final confirmed = await AppConfirmDialog.show(
      context: context,
      title: AppLocalizations.of(context)!.clearHistoryTitle,
      message: AppLocalizations.of(context)!.clearHistoryMessage,
      confirmLabel: AppLocalizations.of(context)!.clearHistoryConfirm,
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
        SnackBar(
          content: Text(AppLocalizations.of(context)!.clearHistorySuccess),
          duration: const Duration(seconds: 2),
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

/// 朗读语言选择器。
///
/// 内联 [Wrap] + [ChoiceChip]，遵守 Navigation-first：不使用 Dialog /
/// BottomSheet 作为核心设置流程。窄屏自动换行，不横向溢出；只展示精选语言，
/// 架构本身仍支持任意 BCP-47 tag。
class _ReadAloudLanguagePicker extends ConsumerWidget {
  const _ReadAloudLanguagePicker();

  /// 精选语言；扩展新语言只需在此追加一行（底层不写死语言集合）。
  static const List<(String, String)> _options = <(String, String)>[
    ('zh-CN', '简体中文'),
    ('zh-TW', '繁体中文'),
    ('en-US', 'English'),
    ('ja-JP', '日本語'),
    ('ko-KR', '한국어'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readAloud = ref.watch(readAloudControllerProvider);
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isAuto = readAloud.languageMode == ReadAloudLanguageMode.auto;

    Widget languageChip(String tag, String label) {
      // 系统能力未知时 isLanguageAvailable 返回 true：拿不到证据就不禁用。
      final available = readAloud.isLanguageAvailable(tag);
      final selected = !isAuto && readAloud.languageTag == tag;
      return ChoiceChip(
        label: Text(available ? label : '$label（不支持）'),
        selected: selected,
        onSelected: (available || selected)
            ? (_) => unawaited(readAloud.setFixedLanguage(tag))
            : null,
      );
    }

    final supportedCount = readAloud.availableLanguages.length;
    final hint = isAuto
        ? l10n.readAloudLanguageHintAuto
        : l10n.readAloudLanguageHintFixed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.readAloudLanguage, style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            ChoiceChip(
              label: Text(l10n.readAloudAutoDetect),
              selected: isAuto,
              onSelected: (_) => unawaited(readAloud.setAutoLanguageMode()),
            ),
            for (final option in _options) languageChip(option.$1, option.$2),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          hint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (supportedCount > 0)
          Text(
            l10n.readAloudSupportedCount(supportedCount),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
