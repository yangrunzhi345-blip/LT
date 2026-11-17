import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_radius.dart';
import '../../../../../../core/theme/app_spacing.dart';
import '../../../../../../core/widgets/app_svg_icon.dart';
import '../../../../../../l10n/generated/app_localizations.dart';

/// Step 2 "auto save to library" option plus its immediate save action.
///
/// Below 560 px the save button moves under the checkbox row instead of
/// competing with the label for horizontal space.
class WizardCharacterLibrarySaveOption extends StatelessWidget {
  const WizardCharacterLibrarySaveOption({
    super.key,
    required this.l10n,
    required this.value,
    required this.isSaving,
    required this.onChanged,
    required this.onSaveNow,
  });

  final AppLocalizations l10n;
  final bool value;
  final bool isSaving;
  final ValueChanged<bool> onChanged;
  final VoidCallback onSaveNow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 560;

        final saveButton = FilledButton.tonalIcon(
          onPressed: isSaving ? null : onSaveNow,
          icon: isSaving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const AppSvgIcon('bookmark', size: 16),
          label: Text(isSaving ? l10n.partSaving : l10n.saveToLibraryNow),
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        );

        final childContent = Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Checkbox(
              value: value,
              onChanged: (val) => onChanged(val ?? true),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: InkWell(
                onTap: () => onChanged(!value),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Wrap instead of a fixed Row: on narrow phones the
                      // badge moves below the title instead of pushing the
                      // title out of the card.
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            l10n.autoSaveToLibrary,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.full),
                            ),
                            child: Text(
                              l10n.wizardReusableBadge,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.wizardCharacterSaveDescription,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!isNarrow) ...[
              const SizedBox(width: AppSpacing.sm),
              saveButton,
            ],
          ],
        );

        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 2,
            vertical: AppSpacing.xs + 2,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    childContent,
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: isSaving ? null : onSaveNow,
                        icon: isSaving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const AppSvgIcon('bookmark', size: 16),
                        label: Text(
                          isSaving ? l10n.partSaving : l10n.saveToLibraryNow,
                        ),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                )
              : childContent,
        );
      },
    );
  }
}
