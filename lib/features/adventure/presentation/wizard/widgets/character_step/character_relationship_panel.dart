import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_radius.dart';
import '../../../../../../core/theme/app_spacing.dart';
import '../../../../../../core/widgets/app_dropdown.dart';
import '../../../../../../core/widgets/app_svg_icon.dart';
import '../../../../../../l10n/generated/app_localizations.dart';
import '../../../../../../models/adventure_config.dart';
import '../../adventure_label_formatters.dart';
import '../../models/wizard_character_item.dart';

/// Step 2 bond editor. Rendered only when the roster holds at least two
/// characters, mirroring the original inline section.
class WizardCharacterRelationshipPanel extends StatelessWidget {
  const WizardCharacterRelationshipPanel({
    super.key,
    required this.l10n,
    required this.characters,
    required this.relationships,
    required this.onRelationTypeChanged,
    required this.onCustomRelationNameChanged,
    required this.onDescriptionChanged,
  });

  final AppLocalizations l10n;
  final List<WizardCharacterItem> characters;
  final List<WizardRelationshipItem> relationships;
  final void Function(WizardRelationshipItem relationship, String type)
      onRelationTypeChanged;
  final void Function(WizardRelationshipItem relationship, String customName)
      onCustomRelationNameChanged;
  final void Function(WizardRelationshipItem relationship, String description)
      onDescriptionChanged;

  static const List<String> _relationTypes = [
    AdventureRelationType.unset,
    AdventureRelationType.companion,
    AdventureRelationType.friend,
    AdventureRelationType.family,
    AdventureRelationType.mentor,
    AdventureRelationType.lover,
    AdventureRelationType.rival,
    AdventureRelationType.enemy,
    AdventureRelationType.employer,
    AdventureRelationType.stranger,
    AdventureRelationType.custom,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        const Divider(),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final title = Row(
              children: [
                AppSvgIcon('graph', size: 20, color: scheme.tertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.relationshipNetworkTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            );
            final countBadge = Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                l10n.characterBondsCount(relationships.length),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onTertiaryContainer,
                ),
              ),
            );
            // At the 320 px minimum width the title and the bond counter no
            // longer share a line, so the counter moves below the title.
            if (constraints.maxWidth < 360) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  const SizedBox(height: 6),
                  countBadge,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: 6),
                countBadge,
              ],
            );
          },
        ),
        const SizedBox(height: 4),
        Text(
          l10n.relationshipNetworkDescription,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm + 4),
        ...relationships.map((rel) {
          final source = characters
              .where((c) => c.id == rel.sourceCharacterId)
              .firstOrNull;
          final target = characters
              .where((c) => c.id == rel.targetCharacterId)
              .firstOrNull;
          if (source == null || target == null) {
            return const SizedBox.shrink();
          }
          return _RelationshipCard(
            l10n: l10n,
            relationship: rel,
            source: source,
            target: target,
            onRelationTypeChanged: onRelationTypeChanged,
            onCustomRelationNameChanged: onCustomRelationNameChanged,
            onDescriptionChanged: onDescriptionChanged,
          );
        }),
      ],
    );
  }
}

class _RelationshipCard extends StatelessWidget {
  const _RelationshipCard({
    required this.l10n,
    required this.relationship,
    required this.source,
    required this.target,
    required this.onRelationTypeChanged,
    required this.onCustomRelationNameChanged,
    required this.onDescriptionChanged,
  });

  final AppLocalizations l10n;
  final WizardRelationshipItem relationship;
  final WizardCharacterItem source;
  final WizardCharacterItem target;
  final void Function(WizardRelationshipItem relationship, String type)
      onRelationTypeChanged;
  final void Function(WizardRelationshipItem relationship, String customName)
      onCustomRelationNameChanged;
  final void Function(WizardRelationshipItem relationship, String description)
      onDescriptionChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: [
                    Text(
                      source.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (source.isProtagonist)
                      Text(
                        ' (${l10n.protagonistShortTag})',
                        style: TextStyle(fontSize: 10, color: scheme.primary),
                      ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: AppSvgIcon('swap', size: 16),
                    ),
                    Text(
                      target.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (target.isProtagonist)
                      Text(
                        ' (${l10n.protagonistShortTag})',
                        style: TextStyle(fontSize: 10, color: scheme.primary),
                      ),
                  ],
                ),
              ),
              AppDropdown<String>.compact(
                value: relationship.relationType,
                options: WizardCharacterRelationshipPanel._relationTypes
                    .map(
                      (type) => AppDropdownOption(
                        value: type,
                        label: localizedAdventureRelation(type, l10n),
                      ),
                    )
                    .toList(),
                onChanged: (newType) {
                  if (newType != null) {
                    onRelationTypeChanged(relationship, newType);
                  }
                },
              ),
            ],
          ),
          if (relationship.assetSuggestion.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              l10n.relationAssetReference(relationship.assetSuggestion),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (relationship.relationType == AdventureRelationType.custom) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
              child: TextField(
                controller:
                    TextEditingController(text: relationship.customRelationName)
                      ..selection = TextSelection.collapsed(
                        offset: relationship.customRelationName.length,
                      ),
                decoration: InputDecoration(
                  labelText: l10n.relationCustomDescLabel,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
                style: const TextStyle(fontSize: 12),
                onChanged: (val) =>
                    onCustomRelationNameChanged(relationship, val.trim()),
              ),
            ),
          ],
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: TextField(
              controller: TextEditingController(text: relationship.description)
                ..selection = TextSelection.collapsed(
                  offset: relationship.description.length,
                ),
              decoration: InputDecoration(
                hintText: l10n.relationDetailsHint,
                border: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              style: const TextStyle(fontSize: 11),
              onChanged: (val) =>
                  onDescriptionChanged(relationship, val.trim()),
            ),
          ),
        ],
      ),
    );
  }
}
