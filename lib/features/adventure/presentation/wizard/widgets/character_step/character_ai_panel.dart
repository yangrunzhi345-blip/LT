import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_radius.dart';
import '../../../../../../core/theme/app_spacing.dart';
import '../../../../../../core/widgets/app_dropdown.dart';
import '../../../../../../core/widgets/app_svg_icon.dart';
import '../../../../../../l10n/generated/app_localizations.dart';

/// Step 2 AI character assistant card: prompt, related-character association,
/// generation mode and the generation entry point.
///
/// The wizard owns every piece of state; this panel receives it as plain props
/// and reports intent through callbacks.
class WizardCharacterAiPanel extends StatelessWidget {
  const WizardCharacterAiPanel({
    super.key,
    required this.l10n,
    required this.worldviewName,
    required this.promptController,
    required this.isGenerating,
    required this.isDetailed,
    required this.progressText,
    required this.errorText,
    required this.hasRoster,
    required this.associationOptions,
    required this.associationIds,
    required this.associationNames,
    required this.relationType,
    required this.customRelationController,
    required this.onGenerate,
    required this.onRetry,
    required this.onDismissError,
    required this.onDetailedChanged,
    required this.onAssociationsChanged,
    required this.onClearAssociations,
    required this.onRelationTypeChanged,
  });

  final AppLocalizations l10n;

  /// Trimmed worldview name; empty falls back to the generic label.
  final String worldviewName;
  final TextEditingController promptController;
  final bool isGenerating;
  final bool isDetailed;
  final String? progressText;
  final String? errorText;
  final bool hasRoster;
  final List<AppDropdownOption<String>> associationOptions;
  final Set<String> associationIds;
  final Map<String, String> associationNames;
  final String relationType;
  final TextEditingController customRelationController;
  final VoidCallback onGenerate;
  final VoidCallback onRetry;
  final VoidCallback onDismissError;
  final ValueChanged<bool> onDetailedChanged;
  final ValueChanged<Set<String>> onAssociationsChanged;
  final VoidCallback onClearAssociations;
  final ValueChanged<String> onRelationTypeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(scheme, theme),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.wizardCharacterAiSummary(
              worldviewName.isNotEmpty
                  ? worldviewName
                  : l10n.currentWorldviewLabel,
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: promptController,
            enabled: !isGenerating,
            maxLines: 2,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: l10n.wizardCharacterPromptLabel,
              hintText: l10n.wizardCharacterPromptHint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.all(AppSpacing.sm),
            ),
          ),
          if (associationOptions.isNotEmpty) _associationSection(scheme, theme),
          if (errorText != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _errorBox(scheme, errorText!),
          ],
          const SizedBox(height: AppSpacing.sm),
          _modeRow(scheme),
          const SizedBox(height: AppSpacing.sm),
          _actions(),
        ],
      ),
    );
  }

  Widget _title(ColorScheme scheme, ThemeData theme) {
    return Wrap(
      spacing: AppSpacing.xs + 2,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppSvgIcon('generation', color: scheme.primary, size: 20),
        const SizedBox(width: AppSpacing.xs + 2),
        Text(
          l10n.characterAiAssistantCreateTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: scheme.primary,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            l10n.wizardWorldviewQuickBadge,
            style: TextStyle(
              fontSize: 11,
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorBox(ColorScheme scheme, String message) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          AppSvgIcon('error', color: scheme.error, size: 18),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: isGenerating ? null : onRetry,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
              foregroundColor: scheme.error,
            ),
            child: Text(
              l10n.retryAction,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const AppSvgIcon('close', size: 16),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: onDismissError,
          ),
        ],
      ),
    );
  }

  Widget _modeRow(ColorScheme scheme) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          l10n.generationModeLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 4),
        ChoiceChip(
          label: Text(l10n.conciseMode, style: const TextStyle(fontSize: 12)),
          selected: !isDetailed,
          onSelected: isGenerating
              ? null
              : (v) {
                  if (v) onDetailedChanged(false);
                },
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        const SizedBox(width: 6),
        ChoiceChip(
          label: Text(l10n.detailedMode, style: const TextStyle(fontSize: 12)),
          selected: isDetailed,
          onSelected: isGenerating
              ? null
              : (v) {
                  if (v) onDetailedChanged(true);
                },
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        if (progressText != null) ...[
          const SizedBox(width: 12),
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 6),
          Text(
            progressText!,
            style: TextStyle(
              fontSize: 11,
              color: scheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _actions() {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        FilledButton.icon(
          onPressed: isGenerating ? null : onGenerate,
          icon: isGenerating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const AppSvgIcon('generation', size: 18),
          label: Text(
            isGenerating
                ? (isDetailed
                    ? l10n.wizardWorldviewGeneratingDetailed
                    : l10n.wizardWorldviewGeneratingBrief)
                : (hasRoster
                    ? l10n.wizardAddCharacterToRosterAction
                    : l10n.wizardGenerateMainCharacterAction),
          ),
        ),
      ],
    );
  }

  Widget _associationSection(ColorScheme scheme, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: associationIds.isNotEmpty
              ? scheme.primary.withValues(alpha: 0.35)
              : scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppSvgIcon(
                'graph',
                size: 16,
                color: associationIds.isNotEmpty
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              // The title flexes instead of forcing the hint text off-screen
              // on narrow phones: both texts wrap/ellipsize inside one Row.
              Flexible(
                child: Text(
                  l10n.characterCardRelateCharacterOptional,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: associationIds.isNotEmpty
                        ? scheme.primary
                        : scheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.wizardRelationAssociationSummary,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (associationIds.isNotEmpty)
                InkWell(
                  onTap: isGenerating ? null : onClearAssociations,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      l10n.clearRelatedCharacters,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs + 2),
          AppMultiSelectDropdown<String>(
            values: associationIds,
            label: l10n.selectRelatedCharacters,
            hintText: l10n.characterCardRelateCharacterHint,
            emptyText: l10n.characterCardNoOtherCharacters,
            options: associationOptions,
            direction: AppDropdownDirection.down,
            triggerHeight: 38,
            triggerPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            selectedBuilder: (values) {
              if (values.isEmpty) return l10n.characterCardIndependentRole;
              final names =
                  values.map((id) => associationNames[id] ?? id).toList();
              return l10n.wizardRelatedCharactersSummary(
                values.length,
                names.join(', '),
              );
            },
            onChanged: isGenerating
                ? null
                : (newVals) => onAssociationsChanged(newVals.toSet()),
          ),
          if (associationIds.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs + 2),
            LayoutBuilder(
              builder: (context, constraints) {
                final label = Text(
                  l10n.characterCardBondRelation,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                );
                final picker = AppDropdown<String>.compact(
                  value: relationType,
                  direction: AppDropdownDirection.down,
                  options: _relationOptions(),
                  onChanged: isGenerating
                      ? null
                      : (val) {
                          if (val != null) onRelationTypeChanged(val);
                        },
                );
                final presets = SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: _presetChips()),
                );
                // Below 360 logical px the bond label, the picker and the
                // preset strip cannot share one line; the presets move to
                // their own scrollable row instead of clipping the picker.
                if (constraints.maxWidth < 360) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 4,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [label, picker],
                      ),
                      const SizedBox(height: 6),
                      presets,
                    ],
                  );
                }
                return Row(
                  children: [
                    label,
                    const SizedBox(width: 4),
                    picker,
                    const SizedBox(width: 8),
                    Expanded(child: presets),
                  ],
                );
              },
            ),
            if (relationType == '自定义') ...[
              const SizedBox(height: 6),
              SizedBox(
                height: 34,
                child: TextField(
                  controller: customRelationController,
                  enabled: !isGenerating,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    labelText: l10n.relationCustomDescLabel,
                    hintText: l10n.relationCustomDescHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  List<AppDropdownOption<String>> _relationOptions() {
    return [
      AppDropdownOption(value: '同伴', label: l10n.relationCompanion),
      AppDropdownOption(value: '青梅竹马', label: l10n.relationChildhoodFriend),
      AppDropdownOption(value: '恋人', label: l10n.relationLover),
      AppDropdownOption(value: '师徒', label: l10n.relationMentor),
      AppDropdownOption(value: '宿敌', label: l10n.relationRival),
      AppDropdownOption(value: '亲人', label: l10n.relationKin),
      AppDropdownOption(value: '救命恩人', label: l10n.relationBenefactor),
      AppDropdownOption(value: '雇佣关系', label: l10n.relationEmployment),
      AppDropdownOption(value: '自定义', label: l10n.relationCustom),
    ];
  }

  List<Widget> _presetChips() {
    final labels = <String, String>{
      '同伴': l10n.relationCompanion,
      '青梅竹马': l10n.relationChildhoodFriend,
      '恋人': l10n.relationLover,
      '师徒': l10n.relationMentor,
      '宿敌': l10n.relationRival,
      '救命恩人': l10n.relationBenefactor,
    };
    return labels.entries.map((entry) {
      final preset = entry.key;
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: ChoiceChip(
          label: Text(entry.value, style: const TextStyle(fontSize: 11)),
          selected: relationType == preset,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onSelected: isGenerating
              ? null
              : (selected) {
                  if (selected) onRelationTypeChanged(preset);
                },
        ),
      );
    }).toList();
  }
}
