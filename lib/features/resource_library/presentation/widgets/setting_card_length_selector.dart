import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../domain/resources/resource_limits.dart';
import '../../../../domain/setting_cards/setting_card.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../models/generation_stage_progress.dart';
import '../resolvers/resource_presentation_resolver.dart';

/// Soft generation-length tiers shared by the create and regenerate flows.
///
/// These are prompt targets, not validation: the gateway may return a shorter
/// or longer document and it is still saved. Standard keeps the model's own
/// default so a quick card is not forced into a length. [custom] carries no
/// preset target: the number comes from the selector's free-form field.
enum SettingCardGenerationLength {
  standard(null),
  compact(3000),
  detailed(null),
  custom(null);

  const SettingCardGenerationLength(this.targetCharacters);

  final int? targetCharacters;
}

/// Resolves the prompt target for [length] given the card [kind].
///
/// The detailed tier is kind-dependent: a long worldview is built from many
/// modules, while asking for the same word count from a single character card
/// only invites padding. Character and NPC cards therefore stop at a smaller
/// detailed budget that still sits inside the 4,000–6,000 character band.
int? targetCharactersFor(
  SettingCardKind kind,
  SettingCardGenerationLength length,
) {
  switch (length) {
    case SettingCardGenerationLength.standard:
    case SettingCardGenerationLength.custom:
      return null;
    case SettingCardGenerationLength.compact:
      return 3000;
    case SettingCardGenerationLength.detailed:
      return kind == SettingCardKind.worldview ? 12000 : 5000;
  }
}

/// Formats a structured generation stage for the create / detail progress row.
///
/// Only the stage name is shown when the request had no explicit target, so a
/// concise pass does not display a misleading "0 / 0". The supplement round is
/// appended when the model is on a follow-up pass.
String formatSettingCardGenerationProgress(
  AppLocalizations l10n,
  GenerationStageProgress progress,
) {
  final stageName = progress.stageName.trim().isNotEmpty
      ? progress.stageName.trim()
      : (progress.totalStages > 0
          ? '${progress.stage} / ${progress.totalStages}'
          : '');
  final parts = <String>[
    if (stageName.isNotEmpty) stageName,
    if (progress.targetCharacters case final target?)
      l10n.settingCardGenerationProgressCount(
        progress.currentCharacters,
        target,
      ),
    if (progress.supplementRound > 0)
      l10n.settingCardGenerationSupplementRound(progress.supplementRound),
  ];
  return parts.join(' · ');
}

/// Removes protocol markers and raw JSON from a generation error before it is
/// shown. The typed exception's own message is readable Chinese, so it is kept
/// and only scrubbed; unknown failures fall back to [fallback].
String sanitizeSettingCardGenerationMessage(
  String? message, {
  required String fallback,
}) =>
    ResourcePresentationResolver.sanitize(message, fallback: fallback);

/// Compact length picker used above the instruction field.
///
/// Presets plus a free-form target, so a user is not limited to three sizes.
/// Chips wrap instead of a segmented row so all four options stay tappable at
/// 320px and with a large text scale.
final class SettingCardLengthSelector extends StatelessWidget {
  const SettingCardLengthSelector({
    super.key,
    required this.value,
    required this.onChanged,
    required this.customCharactersController,
    required this.kind,
    this.enabled = true,
    this.keyPrefix = 'setting-card-length',
  });

  /// Smallest target the generation pipeline accepts, shared with
  /// [ResourceLimits] so the field never advertises an unusable value.
  static const int minimumCharacters =
      ResourceLimits.minimumGenerationTargetCharacters;

  /// Largest target offered for [kind].
  ///
  /// Mirrors the type budget the generation coordinators clamp to, so the
  /// field cannot promise a length that would be silently reduced.
  static int maximumCharactersFor(SettingCardKind kind) => switch (kind) {
        SettingCardKind.worldview => ResourceLimits.worldviewNominalCharacters,
        SettingCardKind.character => ResourceLimits.characterNominalCharacters,
        SettingCardKind.npc => ResourceLimits.npcNominalCharacters,
      };

  /// Parses a free-form target, returning null when it is empty, not a number
  /// or outside [minimumCharacters]–[maximumCharacters].
  static int? parseCustomCharacters(
    String text, {
    required int maximumCharacters,
  }) {
    final parsed = int.tryParse(text.trim());
    if (parsed == null) {
      return null;
    }
    if (parsed < minimumCharacters || parsed > maximumCharacters) {
      return null;
    }
    return parsed;
  }

  final SettingCardGenerationLength value;
  final ValueChanged<SettingCardGenerationLength> onChanged;

  /// Owned by the page so a typed target survives rebuilds and can be read
  /// when the form is submitted.
  final TextEditingController customCharactersController;

  final SettingCardKind kind;

  /// Largest target offered for [kind]; see [maximumCharactersFor].
  int get maximumCharacters => maximumCharactersFor(kind);

  final bool enabled;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          l10n.settingCardLengthLabel,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            for (final option in SettingCardGenerationLength.values)
              ChoiceChip(
                key: Key('$keyPrefix-${option.name}'),
                label: Text(_label(l10n, option)),
                selected: value == option,
                onSelected: enabled ? (_) => _select(option) : null,
              ),
          ],
        ),
        if (value == SettingCardGenerationLength.custom) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: customCharactersController,
            builder: (context, editing, _) {
              final text = editing.text.trim();
              final valid = parseCustomCharacters(
                    text,
                    maximumCharacters: maximumCharacters,
                  ) !=
                  null;
              return AppTextField(
                key: Key('$keyPrefix-custom-characters'),
                controller: customCharactersController,
                label: l10n.settingCardLengthCustomField,
                hintText: '$minimumCharacters–$maximumCharacters',
                enabled: enabled,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                // An empty field is not flagged: the submit action explains
                // the missing target. Only a typed but unusable number shows
                // the range error.
                errorText: text.isEmpty || valid
                    ? null
                    : l10n.settingCardLengthCustomInvalid(
                        minimumCharacters,
                        maximumCharacters,
                      ),
              );
            },
          ),
        ],
      ],
    );
  }

  void _select(SettingCardGenerationLength option) {
    if (option == SettingCardGenerationLength.custom &&
        customCharactersController.text.trim().isEmpty) {
      // Seed the field with the previous preset so switching to 自定义 does not
      // force retyping a length the user just picked.
      final seed = targetCharactersFor(kind, value);
      if (seed != null) {
        customCharactersController.text = '$seed';
      }
    }
    onChanged(option);
  }

  String _label(
    AppLocalizations l10n,
    SettingCardGenerationLength option,
  ) =>
      switch (option) {
        SettingCardGenerationLength.standard => l10n.settingCardLengthDefault,
        SettingCardGenerationLength.compact => l10n.settingCardLengthCompact,
        SettingCardGenerationLength.detailed => l10n.settingCardLengthDetailed,
        SettingCardGenerationLength.custom => l10n.settingCardLengthCustom,
      };
}
