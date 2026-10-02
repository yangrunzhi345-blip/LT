import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/diagnostics/diagnostic_session_export_use_case.dart';
import '../../../../core/feedback/app_feedback.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/localization/app_error_localizer.dart';
import '../../../../core/widgets/workbench_section.dart';
import '../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../domain/read_aloud/read_aloud_contracts.dart';
import '../../../../providers/riverpod_providers.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

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
    final l10n = _l10n(context);
    final colorScheme = theme.colorScheme;
    final chat = ref.watch(chatProvider);

    final tokenSummary = chat.getTokenSummary();
    final sessionTokens = tokenSummary['sessionTokens'] as int? ?? 0;
    final totalTokens = tokenSummary['totalTokens'] as int? ?? 0;

    return WorkbenchSection(
      title: l10n.dataManagementTitle,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${l10n.sessionTokensLabel}: $sessionTokens'),
        Text('${l10n.tokenHistoryTotal}: $totalTokens'),
        const SizedBox(height: 24),
        Text(l10n.diagnosticExportTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(l10n.diagnosticExportSubtitle),
        const SizedBox(height: 8),
        Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
                onPressed: chat.currentAdventureId == null
                    ? null
                    : _showDiagnosticExportConfirmation,
                child: Text(l10n.exportDiagnosticJson))),
        const SizedBox(height: 24),
        Text(l10n.cacheStorageTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
                onPressed: () => _confirmClearHistory(context),
                child: Text(l10n.clearAllData,
                    style: TextStyle(color: colorScheme.error)))),
      ]),
    );
  }

  Future<void> _showDiagnosticExportConfirmation() async {
    final confirmed = await AppConfirmDialog.show(
      context: context,
      title: _l10n(context).diagnosticExportTitle,
      message: _l10n(context).diagnosticExportSubtitle,
      confirmLabel: _l10n(context).exportDiagnosticJson,
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
    if (path == null) {
      AppFeedback.error(context, _l10n(context).diagnosticExportFailed);
    } else {
      AppFeedback.success(context, _l10n(context).diagnosticExported(path));
    }
  }

  Future<void> _confirmClearHistory(BuildContext context) async {
    final confirmed = await AppConfirmDialog.show(
      context: context,
      title: _l10n(context).clearHistoryTitle,
      message: _l10n(context).clearHistoryMessage,
      confirmLabel: _l10n(context).clearHistoryConfirm,
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
      AppFeedback.success(
        context,
        _l10n(context).clearHistorySuccess,
        duration: const Duration(seconds: 2),
      );
    }
  }
}

/// Playback preferences use the application's existing read-aloud authority.
class ReadAloudSettingsSection extends ConsumerStatefulWidget {
  const ReadAloudSettingsSection({super.key});
  @override
  ConsumerState<ReadAloudSettingsSection> createState() =>
      _ReadAloudSettingsSectionState();
}

class _ReadAloudSettingsSectionState
    extends ConsumerState<ReadAloudSettingsSection> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(readAloudControllerProvider).refreshLanguages());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final controller = ref.watch(readAloudControllerProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(l10n.readAloudSectionTitle,
          style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 12),
      Text(controller.capability.supported
          ? l10n.readAloudPlatformSupportedMessage
          : localizeReadAloudCapability(l10n, controller.capability)),
      SwitchListTile(
          contentPadding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          title: Text(l10n.readAloudEnable),
          subtitle: Text(l10n.readAloudEnableSubtitle),
          value: controller.enabled,
          onChanged: (value) => unawaited(controller.setEnabled(value))),
      SwitchListTile(
          contentPadding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          title: Text(l10n.readAloudAutoRead),
          subtitle: Text(l10n.readAloudAutoReadSubtitle),
          value: controller.autoRead,
          onChanged: (value) => unawaited(controller.setAutoRead(value))),
      _ReadAloudSlider(
          label: l10n.readAloudRateLabel,
          value: controller.rate,
          min: 0,
          max: 1,
          enabled: controller.enabled,
          onChanged: (value) => unawaited(controller.setRate(value))),
      _ReadAloudSlider(
          label: l10n.readAloudPitchLabel,
          value: controller.pitch,
          min: 0.5,
          max: 2,
          enabled: controller.enabled,
          onChanged: (value) => unawaited(controller.setPitch(value))),
      const SizedBox(height: AppSpacing.md),
      const _ReadAloudLanguagePicker(),
    ]);
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
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isAuto = readAloud.languageMode == ReadAloudLanguageMode.auto;

    Widget languageChip(String tag, String label) {
      // 系统能力未知时 isLanguageAvailable 返回 true：拿不到证据就不禁用。
      final available = readAloud.isLanguageAvailable(tag);
      final selected = !isAuto && readAloud.languageTag == tag;
      return ChoiceChip(
        showCheckmark: false,
        label: Text(
          available ? label : '$label${l10n.readAloudUnsupportedLanguage}',
        ),
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
              showCheckmark: false,
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
