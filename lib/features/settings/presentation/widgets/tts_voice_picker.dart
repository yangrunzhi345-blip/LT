import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/feedback/app_feedback.dart';
import '../../../../core/localization/tts_error_localizer.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_svg_icon.dart';
import '../../../../domain/tts/tts_models.dart';
import '../../../../domain/tts/tts_voices.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_en.dart';
import '../../../../providers/riverpod_providers.dart';

/// Shows the unified voice picker.
///
/// Returns:
/// - a non-null voice id when a voice is chosen (already installed or queued
///   for an explicit download),
/// - an empty string when the user chose "system voice" / "auto assign",
/// - null when dismissed.
Future<String?> showTtsVoicePicker(
  BuildContext context, {
  required String title,
  bool showSystemOption = true,
  bool showAutoOption = false,
}) {
  return showDialog<String?>(
    context: context,
    builder: (_) => _TtsVoicePickerDialog(
      title: title,
      showSystemOption: showSystemOption,
      showAutoOption: showAutoOption,
    ),
  );
}

class _TtsVoicePickerDialog extends ConsumerStatefulWidget {
  const _TtsVoicePickerDialog({
    required this.title,
    required this.showSystemOption,
    required this.showAutoOption,
  });

  final String title;
  final bool showSystemOption;
  final bool showAutoOption;

  @override
  ConsumerState<_TtsVoicePickerDialog> createState() =>
      _TtsVoicePickerDialogState();
}

class _TtsVoicePickerDialogState extends ConsumerState<_TtsVoicePickerDialog> {
  String? _languageFilter;
  String? _previewingVoiceId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsEn();
    final theme = Theme.of(context);
    final catalog = ref.watch(ttsModelCatalogProvider);
    final manager = ref.watch(ttsModelManagerProvider);
    final voices = catalog.allVoices();
    final languages = <String>{
      for (final voice in voices) ...voice.languages,
    }.toList()
      ..sort();
    final filtered = _languageFilter == null
        ? voices
        : voices
            .where((v) => v.languages.contains(_languageFilter))
            .toList(growable: false);

    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.borderLg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(widget.title, style: theme.textTheme.titleMedium),
            ),
            if (voices.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  l10n.ttsVoicePickerEmpty,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              )
            else ...[
              if (languages.length > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: <Widget>[
                      ChoiceChip(
                        key: const ValueKey('tts-voice-filter-all'),
                        label: Text(l10n.ttsVoiceFilterAll),
                        selected: _languageFilter == null,
                        onSelected: (_) =>
                            setState(() => _languageFilter = null),
                      ),
                      for (final language in languages)
                        ChoiceChip(
                          key: ValueKey('tts-voice-filter-$language'),
                          label: Text(language),
                          selected: _languageFilter == language,
                          onSelected: (_) =>
                              setState(() => _languageFilter = language),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              Flexible(
                child: ListView.builder(
                  key: const ValueKey('tts-voice-list'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final voice = filtered[index];
                    final model = catalog.modelForVoice(
                      voice.voiceId,
                      isInstalled: (m) => manager.isModelInstalled(m.modelId),
                    );
                    final installed = model != null &&
                        manager.isModelInstalled(model.modelId);
                    return _VoiceRow(
                      voice: voice,
                      installed: installed,
                      previewing: _previewingVoiceId == voice.voiceId,
                      onSelect: () => _select(voice, model, installed),
                      onPreview: () => _preview(voice, model, installed),
                    );
                  },
                ),
              ),
            ],
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                alignment: WrapAlignment.end,
                children: <Widget>[
                  if (widget.showSystemOption)
                    TextButton(
                      key: const ValueKey('tts-voice-system'),
                      onPressed: () => Navigator.of(context).pop(''),
                      child: Text(l10n.ttsVoicePickerUseSystem),
                    ),
                  if (widget.showAutoOption)
                    TextButton(
                      key: const ValueKey('tts-voice-auto'),
                      onPressed: () => Navigator.of(context).pop(''),
                      child: Text(l10n.readAloudVoiceAutoAssign),
                    ),
                  TextButton(
                    key: const ValueKey('tts-voice-cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.ttsModelCancel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _select(
    TtsVoiceDescriptor voice,
    TtsModelDescriptor? model,
    bool installed,
  ) async {
    if (installed) {
      Navigator.of(context).pop(voice.voiceId);
      return;
    }
    if (model == null) return;
    final confirmed = await _confirmDownload(model);
    if (confirmed != true) return;
    // Explicit user action: this is the only place a model download starts.
    unawaitedDownload(ref, model.modelId);
    if (!mounted) return;
    AppFeedback.success(
      context,
      (AppLocalizations.of(context) ?? AppLocalizationsEn())
          .ttsModelDownloadStarted,
    );
    Navigator.of(context).pop(voice.voiceId);
  }

  Future<bool?> _confirmDownload(TtsModelDescriptor model) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsEn();
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.ttsVoicePickerNeedsDownload),
        content: Text(
          '${model.displayName}\n'
          '${l10n.ttsModelDownloadSize}: ${formatBytes(model.downloadSizeBytes)}\n'
          '${l10n.ttsModelLanguages}: ${model.languages.join(', ')}',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.ttsVoicePickerUseSystem),
          ),
          FilledButton(
            key: const ValueKey('tts-voice-download-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.ttsVoicePickerDownloadAndUse),
          ),
        ],
      ),
    );
  }

  Future<void> _preview(
    TtsVoiceDescriptor voice,
    TtsModelDescriptor? model,
    bool installed,
  ) async {
    final controller = ref.read(readAloudControllerProvider);
    final sentence = (AppLocalizations.of(context) ?? AppLocalizationsEn())
        .ttsVoicePreviewSentence;
    if (!installed || model == null) {
      // Uninstalled voice: preview the system voice instead of silently doing
      // nothing, without downloading anything.
      await controller.playText(
        sentence,
        sourceId: 'tts-voice-preview',
      );
      return;
    }
    setState(() => _previewingVoiceId = voice.voiceId);
    await controller.playText(
      sentence,
      sourceId: 'tts-voice-preview',
      voiceOverride: ReadAloudVoiceTarget(
        backend: TtsBackendKind.neural,
        capabilities: model.capabilities,
        voiceId: voice.voiceId,
        modelId: model.modelId,
        speakerId: voice.speakerId,
      ),
    );
    if (mounted) setState(() => _previewingVoiceId = null);
  }
}

void unawaitedDownload(WidgetRef ref, String modelId) {
  // Fire-and-forget: the model manager owns progress/state and the settings
  // page reflects it. This is always triggered by an explicit user action.
  ref.read(ttsModelManagerProvider).download(modelId).catchError((_) {});
}

class _VoiceRow extends StatelessWidget {
  const _VoiceRow({
    required this.voice,
    required this.installed,
    required this.previewing,
    required this.onSelect,
    required this.onPreview,
  });

  final TtsVoiceDescriptor voice;
  final bool installed;
  final bool previewing;
  final VoidCallback onSelect;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsEn();
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      title: Text(voice.displayName, style: theme.textTheme.bodyMedium),
      subtitle: Text(
        '${voice.languages.join(', ')} · '
        '${installed ? l10n.ttsVoicePickerInstalled : l10n.ttsVoicePickerRequiresDownload}',
        style: theme.textTheme.labelSmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            onPressed: onPreview,
            visualDensity: VisualDensity.compact,
            tooltip: l10n.readAloudVoicePreview,
            icon: previewing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const AppSvgIcon('play', size: 18),
          ),
        ],
      ),
      onTap: onSelect,
    );
  }
}
