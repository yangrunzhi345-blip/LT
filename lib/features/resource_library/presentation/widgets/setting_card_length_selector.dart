import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';

/// Soft generation-length tiers shared by the create and regenerate flows.
///
/// These are prompt targets, not validation: the gateway may return a shorter
/// or longer document and it is still saved. Standard keeps the model's own
/// default so a quick card is not forced into a length.
enum SettingCardGenerationLength {
  standard(null),
  compact(3000),
  detailed(12000);

  const SettingCardGenerationLength(this.targetCharacters);

  final int? targetCharacters;
}

/// Compact length picker used above the instruction field.
///
/// Chips wrap instead of a segmented row so the three options stay tappable at
/// 320px and with a large text scale.
final class SettingCardLengthSelector extends StatelessWidget {
  const SettingCardLengthSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.keyPrefix = 'setting-card-length',
  });

  final SettingCardGenerationLength value;
  final ValueChanged<SettingCardGenerationLength> onChanged;
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
                onSelected: enabled ? (_) => onChanged(option) : null,
              ),
          ],
        ),
      ],
    );
  }

  String _label(
    AppLocalizations l10n,
    SettingCardGenerationLength option,
  ) =>
      switch (option) {
        SettingCardGenerationLength.standard => l10n.settingCardLengthDefault,
        SettingCardGenerationLength.compact => l10n.settingCardLengthCompact,
        SettingCardGenerationLength.detailed => l10n.settingCardLengthDetailed,
      };
}
