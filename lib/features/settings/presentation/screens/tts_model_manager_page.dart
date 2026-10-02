import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/tts_error_localizer.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../domain/tts/tts_models.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_en.dart';
import '../../../../providers/riverpod_providers.dart';

/// Voice model manager: the only place a neural model download is started.
///
/// It never shows raw URLs, filesystem paths or ONNX file names to the user.
class TtsModelManagerPage extends ConsumerWidget {
  const TtsModelManagerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsEn();
    final theme = Theme.of(context);
    final catalog = ref.watch(ttsModelCatalogProvider);
    final models = catalog.models;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.ttsModelManagerTitle)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: <Widget>[
              Text(
                l10n.ttsModelManagerIntro,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (models.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                  child: Text(
                    l10n.ttsModelEmpty,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              else
                for (final model in models) ...<Widget>[
                  _ModelTile(model: model),
                  const SizedBox(height: AppSpacing.lg),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelTile extends ConsumerWidget {
  const _ModelTile({required this.model});

  final TtsModelDescriptor model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsEn();
    final manager = ref.watch(ttsModelManagerProvider);
    final status = manager.statusOf(model.modelId);
    final installed = manager.isModelInstalled(model.modelId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(model.displayName, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            _MetaText(model.languages.join(', ')),
            _MetaText(l10n.ttsModelSpeakerCount(model.speakerCount)),
            _MetaText('${l10n.ttsModelVersion} ${model.version}'),
            _MetaText('${l10n.ttsModelLicense} ${model.license}'),
            _MetaText(
              '${l10n.ttsModelDownloadSize} '
              '${formatBytes(model.downloadSizeBytes)}',
            ),
            if (installed)
              _MetaText(
                '${l10n.ttsModelInstalledSize} '
                '${formatBytes(manager.installedBytesFor(model.modelId))}',
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _stateLabel(l10n, status.state),
          key: ValueKey('tts-model-state-${model.modelId}'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: status.state == TtsModelInstallState.failed
                ? scheme.error
                : scheme.onSurfaceVariant,
          ),
        ),
        if (status.state == TtsModelInstallState.failed &&
            status.errorCode != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              localizeTtsError(l10n, status.errorCode),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
        if (status.state == TtsModelInstallState.downloading) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(
            value: status.progress,
            borderRadius: AppRadius.borderXs,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${formatBytes(status.downloadedBytes)} / '
            '${formatBytes(status.totalBytes)}',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: _actions(context, ref, l10n, status.state),
        ),
      ],
    );
  }

  List<Widget> _actions(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    TtsModelInstallState state,
  ) {
    final manager = ref.read(ttsModelManagerProvider);
    void download() {
      manager.download(model.modelId).catchError((_) {});
    }

    switch (state) {
      case TtsModelInstallState.notInstalled:
        return <Widget>[
          FilledButton.tonal(
            key: ValueKey('tts-model-download-${model.modelId}'),
            onPressed: download,
            child: Text(l10n.ttsModelDownload),
          ),
        ];
      case TtsModelInstallState.failed:
        return <Widget>[
          FilledButton.tonal(
            key: ValueKey('tts-model-retry-${model.modelId}'),
            onPressed: download,
            child: Text(l10n.ttsModelRetry),
          ),
        ];
      case TtsModelInstallState.paused:
        return <Widget>[
          FilledButton.tonal(
            key: ValueKey('tts-model-resume-${model.modelId}'),
            onPressed: download,
            child: Text(l10n.ttsModelResume),
          ),
          TextButton(
            key: ValueKey('tts-model-cancel-${model.modelId}'),
            onPressed: () => manager.cancel(model.modelId),
            child: Text(l10n.ttsModelCancel),
          ),
        ];
      case TtsModelInstallState.downloading:
        return <Widget>[
          OutlinedButton(
            key: ValueKey('tts-model-pause-${model.modelId}'),
            onPressed: () => manager.pause(model.modelId),
            child: Text(l10n.ttsModelPause),
          ),
          TextButton(
            key: ValueKey('tts-model-cancel-${model.modelId}'),
            onPressed: () => manager.cancel(model.modelId),
            child: Text(l10n.ttsModelCancel),
          ),
        ];
      case TtsModelInstallState.verifying:
      case TtsModelInstallState.installing:
        return <Widget>[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ];
      case TtsModelInstallState.installed:
        return <Widget>[
          OutlinedButton(
            key: ValueKey('tts-model-delete-${model.modelId}'),
            onPressed: () => _confirmDelete(context, ref, l10n),
            child: Text(l10n.ttsModelDelete),
          ),
        ];
      case TtsModelInstallState.updateAvailable:
        return <Widget>[
          FilledButton.tonal(
              onPressed: download, child: Text(l10n.ttsModelDownload)),
        ];
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.ttsModelDeleteConfirmTitle),
        content: Text(l10n.ttsModelDeleteConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.ttsModelCancel),
          ),
          FilledButton(
            key: const ValueKey('tts-model-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.ttsModelDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(ttsModelManagerProvider).delete(model.modelId);
    }
  }

  String _stateLabel(AppLocalizations l10n, TtsModelInstallState state) {
    switch (state) {
      case TtsModelInstallState.notInstalled:
        return l10n.ttsModelNotInstalled;
      case TtsModelInstallState.downloading:
        return l10n.ttsModelDownloading;
      case TtsModelInstallState.paused:
        return l10n.ttsModelPaused;
      case TtsModelInstallState.verifying:
        return l10n.ttsModelVerifying;
      case TtsModelInstallState.installing:
        return l10n.ttsModelInstalling;
      case TtsModelInstallState.installed:
        return l10n.ttsModelInstalled;
      case TtsModelInstallState.failed:
        return l10n.ttsModelFailed;
      case TtsModelInstallState.updateAvailable:
        return l10n.ttsModelDownload;
    }
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      value,
      style: theme.textTheme.labelSmall
          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }
}
