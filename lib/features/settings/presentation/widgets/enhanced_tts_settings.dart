import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/tts_error_localizer.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_svg_icon.dart';
import '../../../../core/widgets/workbench_section.dart';
import '../../../../domain/tts/tts_models.dart';
import '../../../../domain/tts/tts_voices.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_en.dart';
import '../../../../providers/riverpod_providers.dart';
import '../screens/tts_model_manager_page.dart';
import 'tts_voice_picker.dart';

/// Enhanced (neural) read-aloud settings: mode, model status, narrator voice
/// and default character voice.
class EnhancedTtsSettingsSection extends ConsumerWidget {
  const EnhancedTtsSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsEn();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bindings = ref.watch(ttsVoiceBindingsProvider);
    final manager = ref.watch(ttsModelManagerProvider);
    final catalog = ref.watch(ttsModelCatalogProvider);
    final controller = ref.watch(readAloudControllerProvider);
    final preferences = bindings.preferences;
    final systemAvailable = controller.capability.supported;
    final installedCount = manager.installedModels.length;

    String voiceLabel(String? voiceId) {
      if (voiceId == null || voiceId.isEmpty) return l10n.readAloudVoiceSystem;
      return catalog.voiceById(voiceId)?.displayName ?? voiceId;
    }

    ReadAloudVoiceTarget? targetFor(String? voiceId) {
      if (voiceId == null || voiceId.isEmpty) return null;
      final voice = catalog.voiceById(voiceId);
      final model = catalog.modelForVoice(
        voiceId,
        isInstalled: (m) => manager.isModelInstalled(m.modelId),
      );
      if (voice == null ||
          model == null ||
          !manager.isModelInstalled(model.modelId)) {
        return null;
      }
      return ReadAloudVoiceTarget(
        backend: TtsBackendKind.neural,
        capabilities: model.capabilities,
        voiceId: voiceId,
        modelId: model.modelId,
        speakerId: voice.speakerId,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        WorkbenchSection(
          title: l10n.readAloudModeTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<TtsBackendKind>(
                  showSelectedIcon: false,
                  segments: <ButtonSegment<TtsBackendKind>>[
                    ButtonSegment<TtsBackendKind>(
                      value: TtsBackendKind.system,
                      label: Text(l10n.readAloudModeSystem),
                    ),
                    ButtonSegment<TtsBackendKind>(
                      value: TtsBackendKind.neural,
                      label: Text(l10n.readAloudModeNeural),
                    ),
                  ],
                  selected: <TtsBackendKind>{preferences.mode},
                  onSelectionChanged: (selection) =>
                      bindings.setMode(selection.first),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                preferences.isNeuralEnabled
                    ? l10n.readAloudModeNeuralSubtitle
                    : l10n.readAloudModeSystemSubtitle,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              _StatusRow(
                icon: systemAvailable ? 'check_circle' : 'error',
                color: systemAvailable ? scheme.primary : scheme.error,
                text: systemAvailable
                    ? l10n.readAloudSystemStatusAvailable
                    : l10n.readAloudSystemStatusUnavailable,
              ),
              const SizedBox(height: AppSpacing.xs),
              _StatusRow(
                icon: installedCount > 0 ? 'check_circle' : 'info',
                color: scheme.onSurfaceVariant,
                text: l10n.readAloudNeuralStatusInstalled(
                  installedCount,
                  formatBytes(manager.installedBytes),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('tts-manage-models'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TtsModelManagerPage(),
                    ),
                  ),
                  icon: const AppSvgIcon('download', size: 18),
                  label: Text(l10n.readAloudManageModels),
                ),
              ),
            ],
          ),
        ),
        if (preferences.isNeuralEnabled) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          WorkbenchSection(
            title: l10n.readAloudNarratorVoice,
            child: _VoiceRow(
              display: voiceLabel(preferences.narratorVoiceId),
              onChoose: () async {
                final selected = await showTtsVoicePicker(
                  context,
                  title: l10n.readAloudNarratorVoice,
                );
                if (selected != null) await bindings.setNarratorVoice(selected);
              },
              onPreview: () => _preview(
                ref,
                targetFor(preferences.narratorVoiceId),
                l10n.ttsVoicePreviewSentence,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          WorkbenchSection(
            title: l10n.readAloudDefaultCharacterVoice,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _VoiceRow(
                  display: preferences.defaultCharacterVoiceId == null
                      ? l10n.readAloudVoiceAutoAssign
                      : voiceLabel(preferences.defaultCharacterVoiceId),
                  onChoose: () async {
                    final selected = await showTtsVoicePicker(
                      context,
                      title: l10n.readAloudDefaultCharacterVoice,
                      showAutoOption: true,
                    );
                    if (selected != null) {
                      await bindings.setDefaultCharacterVoice(selected);
                    }
                  },
                  onPreview: () => _preview(
                    ref,
                    targetFor(preferences.defaultCharacterVoiceId),
                    l10n.ttsVoicePreviewSentence,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text(l10n.readAloudVoiceAutoAssign),
                  value: preferences.autoAssignVoices,
                  onChanged: (value) => bindings.setAutoAssignVoices(value),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static Future<void> _preview(
    WidgetRef ref,
    ReadAloudVoiceTarget? target,
    String sentence,
  ) {
    return ref.read(readAloudControllerProvider).playText(
          sentence,
          sourceId: 'tts-voice-preview',
          voiceOverride: target,
        );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.color,
    required this.text,
  });

  final String icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppSvgIcon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
      ],
    );
  }
}

class _VoiceRow extends StatelessWidget {
  const _VoiceRow({
    required this.display,
    required this.onChoose,
    required this.onPreview,
  });

  final String display;
  final VoidCallback onChoose;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsEn();
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            display,
            style: theme.textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          key: const ValueKey('tts-voice-choose'),
          onPressed: onChoose,
          child: Text(l10n.readAloudVoiceChoose),
        ),
        IconButton(
          onPressed: onPreview,
          visualDensity: VisualDensity.compact,
          tooltip: l10n.readAloudVoicePreview,
          icon: const AppSvgIcon('play', size: 18),
        ),
      ],
    );
  }
}
