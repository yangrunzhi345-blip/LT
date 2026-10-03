import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/narrative/context_weighting.dart';
import '../../../../core/feedback/app_feedback.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/workbench_section.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../providers/riverpod_providers.dart';

String contextPresetLabel(AppLocalizations l10n, String preset) =>
    switch (preset) {
      'highControl' => l10n.contextWeightsHighControl,
      'immersive' => l10n.contextWeightsImmersive,
      'custom' => l10n.contextWeightsCustom,
      _ => l10n.contextWeightsBalanced,
    };

String _sourceLabel(AppLocalizations l10n, ContextSourceId source) =>
    switch (source) {
      ContextSourceId.userControl => l10n.contextSourceUserControl,
      ContextSourceId.currentScene => l10n.contextSourceCurrentScene,
      ContextSourceId.characterProfile => l10n.contextSourceCharacterProfile,
      ContextSourceId.runtimeCharacterState =>
        l10n.contextSourceRuntimeCharacterState,
      ContextSourceId.worldview => l10n.contextSourceWorldview,
      ContextSourceId.runtimeWorldState => l10n.contextSourceRuntimeWorldState,
      ContextSourceId.relationship => l10n.relationshipNetworkTitle,
      ContextSourceId.recentDialogue => l10n.contextSourceRecentDialogue,
      ContextSourceId.historicalSummary => l10n.contextSourceHistoricalSummary,
      ContextSourceId.archiveRetrieval => l10n.contextSourceArchiveRetrieval,
    };

/// Presets are directly selectable; Custom exposes all weights without expansion.
class ContextWeightControls extends ConsumerStatefulWidget {
  const ContextWeightControls({super.key});

  @override
  ConsumerState<ContextWeightControls> createState() =>
      _ContextWeightControlsState();
}

class _ContextWeightControlsState extends ConsumerState<ContextWeightControls> {
  // Only the active gesture is local. Persisted settings remain the authority.
  ContextWeightProfile? _gestureProfile;
  bool _saving = false;

  Future<void> _save(ContextWeightProfile profile) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(chatProvider)
          .settingsProvider
          .setContextWeightProfile(profile);
    } catch (_) {
      if (mounted) {
        AppFeedback.error(
            context,
            (AppLocalizations.of(context) ?? AppLocalizationsZh())
                .pageLoadError);
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _gestureProfile = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(chatProvider
        .select((chat) => chat.settingsProvider.contextWeightProfile));
    final visible = _gestureProfile ?? profile;
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    return WorkbenchSection(
      title: l10n.contextWeightsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final preset in ContextWeightPresets.ids)
                ChoiceChip(
                  key: ValueKey('context-preset-$preset'),
                  showCheckmark: false,
                  selected: visible.presetId == preset,
                  label: Text(contextPresetLabel(l10n, preset)),
                  onSelected: _saving
                      ? null
                      : (_) => _save(switch (preset) {
                            'highControl' => ContextWeightPresets.highControl,
                            'immersive' => ContextWeightPresets.immersive,
                            'custom' => profile.copyWith(presetId: 'custom'),
                            _ => ContextWeightPresets.balanced,
                          }),
                ),
            ],
          ),
          if (visible.presetId == 'custom') ...[
            const SizedBox(height: AppSpacing.md),
            for (final source in ContextSourceId.values)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${_sourceLabel(l10n, source)}  ${visible[source]}',
                      style: Theme.of(context).textTheme.bodyMedium),
                  Slider(
                    key: ValueKey('context-weight-${source.value}'),
                    semanticFormatterCallback: (value) =>
                        '${_sourceLabel(l10n, source)} ${value.round()}',
                    value: visible[source].toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: '${visible[source]}',
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _gestureProfile = visible
                                .copyWith(weights: {
                              ...visible.weights,
                              source: value.round()
                            })),
                    onChangeEnd: _saving
                        ? null
                        : (value) => _save(visible.copyWith(weights: {
                              ...visible.weights,
                              source: value.round()
                            })),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
