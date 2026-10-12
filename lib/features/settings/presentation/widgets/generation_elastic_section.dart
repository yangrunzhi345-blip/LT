import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../domain/resources/resource_limits.dart';
import '../../../../providers/riverpod_providers.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';

/// ADR-0003: global default AI generation elastic budget.
///
/// A quiet settings block: the live effective percent, a stepped slider
/// (0–50, step 5) and a numeric input that validates and normalizes before
/// persisting. The value only affects generation tasks created afterwards —
/// already-started tasks keep their frozen budget snapshot.
class GenerationElasticSection extends ConsumerStatefulWidget {
  const GenerationElasticSection({super.key});

  @override
  ConsumerState<GenerationElasticSection> createState() =>
      _GenerationElasticSectionState();
}

class _GenerationElasticSectionState
    extends ConsumerState<GenerationElasticSection> {
  final _percentController = TextEditingController();
  final _percentFocusNode = FocusNode();
  String? _inputError;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(chatProvider).settingsProvider;
    _percentController.text =
        settings.globalGenerationElasticPercent.toString();
    _percentFocusNode.addListener(_handleFocusLost);
  }

  @override
  void dispose() {
    _percentController.dispose();
    _percentFocusNode.removeListener(_handleFocusLost);
    _percentFocusNode.dispose();
    super.dispose();
  }

  void _handleFocusLost() {
    if (_percentFocusNode.hasFocus) return;
    _commitInput(_percentController.text);
  }

  /// Clamps a typed value into the legal 0–50 domain; an unparseable value is
  /// rejected with an inline error instead of silently falling back.
  void _commitInput(String raw) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null) {
      setState(() {
        _inputError = (AppLocalizations.of(context) ?? AppLocalizationsZh())
            .resourceTargetCharactersInputInvalid;
      });
      return;
    }
    final settings = ref.read(chatProvider).settingsProvider;
    final normalized = GenerationBudgetPolicy.normalizeElasticPercent(parsed);
    settings.setGlobalGenerationElasticPercent(normalized);
    setState(() {
      _inputError = null;
      _percentController.text = normalized.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final theme = Theme.of(context);
    final percent = ref.watch(chatProvider.select(
        (chat) => chat.settingsProvider.globalGenerationElasticPercent));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.generationElasticSettingsTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.generationElasticSettingsDescription,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.generationElasticPercentLabel,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Text(
              '$percent%',
              key: const Key('settings-elastic-percent-value'),
              style: theme.textTheme.titleSmall,
            ),
          ],
        ),
        Slider(
          key: const Key('settings-elastic-slider'),
          value: percent.toDouble(),
          min: GenerationBudgetPolicy.minimumElasticPercent.toDouble(),
          max: GenerationBudgetPolicy.maximumElasticPercent.toDouble(),
          divisions: (GenerationBudgetPolicy.maximumElasticPercent -
                  GenerationBudgetPolicy.minimumElasticPercent) ~/
              5,
          label: '$percent%',
          onChanged: (value) {
            ref
                .read(chatProvider)
                .settingsProvider
                .setGlobalGenerationElasticPercent(value.round());
            _percentController.text = value.round().toString();
          },
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('settings-elastic-input'),
                controller: _percentController,
                focusNode: _percentFocusNode,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l10n.generationElasticPercentLabel,
                  errorText: _inputError,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: _commitInput,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.generationElasticSnapshotNotice,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
