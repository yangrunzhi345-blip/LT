import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/feedback/app_feedback.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_dropdown.dart';
import '../../../../core/widgets/app_svg_icon.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../domain/resources/character_relationship.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../domain/setting_cards/setting_card.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../providers/riverpod_providers.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// Roles the repository requires for directional relationship types.
const Map<CharacterRelationshipType, (String, String)> _directionalRoles =
    <CharacterRelationshipType, (String, String)>{
  CharacterRelationshipType.mentorStudent: ('mentor', 'student'),
  CharacterRelationshipType.parentChild: ('parent', 'child'),
  CharacterRelationshipType.employerEmployee: ('employer', 'employee'),
  CharacterRelationshipType.guardianWard: ('guardian', 'ward'),
};

String _relationshipTypeLabel(
  AppLocalizations l10n,
  CharacterRelationshipType type,
) =>
    switch (type) {
      CharacterRelationshipType.friend =>
        l10n.settingCardRelationshipTypeFriend,
      CharacterRelationshipType.family =>
        l10n.settingCardRelationshipTypeFamily,
      CharacterRelationshipType.enemy => l10n.settingCardRelationshipTypeEnemy,
      CharacterRelationshipType.companion =>
        l10n.settingCardRelationshipTypeCompanion,
      CharacterRelationshipType.lover => l10n.settingCardRelationshipTypeLover,
      CharacterRelationshipType.mentorStudent =>
        l10n.settingCardRelationshipTypeMentorStudent,
      CharacterRelationshipType.parentChild =>
        l10n.settingCardRelationshipTypeParentChild,
      CharacterRelationshipType.employerEmployee =>
        l10n.settingCardRelationshipTypeEmployerEmployee,
      CharacterRelationshipType.guardianWard =>
        l10n.settingCardRelationshipTypeGuardianWard,
      CharacterRelationshipType.rival => l10n.settingCardRelationshipTypeRival,
      CharacterRelationshipType.sibling =>
        l10n.settingCardRelationshipTypeSibling,
      CharacterRelationshipType.stranger =>
        l10n.settingCardRelationshipTypeStranger,
      CharacterRelationshipType.custom =>
        l10n.settingCardRelationshipTypeCustom,
    };

/// Relationship editor for one character / NPC setting card.
///
/// Renders nothing for a worldview card: relationships are character metadata,
/// and a worldview has no characters of its own. The list and the add form live
/// in the card's inspector rather than a separate page, so the document stays
/// the visual focus.
final class SettingCardRelationshipsSection extends ConsumerStatefulWidget {
  const SettingCardRelationshipsSection({super.key, required this.card});

  final SettingCard card;

  @override
  ConsumerState<SettingCardRelationshipsSection> createState() =>
      _SettingCardRelationshipsSectionState();
}

final class _SettingCardRelationshipsSectionState
    extends ConsumerState<SettingCardRelationshipsSection> {
  final _subjectRole = TextEditingController();
  final _counterpartRole = TextEditingController();
  final _description = TextEditingController();

  List<CharacterRelationshipPerspective> _relationships =
      const <CharacterRelationshipPerspective>[];
  List<SettingCard> _cards = const <SettingCard>[];
  String? _counterpartId;
  CharacterRelationshipType _relationType = CharacterRelationshipType.friend;
  String? _error;
  bool _loading = true;
  bool _saving = false;

  bool get _supported =>
      widget.card.kind == SettingCardKind.character ||
      widget.card.kind == SettingCardKind.npc;

  @override
  void initState() {
    super.initState();
    if (_supported) Future<void>.microtask(_load);
  }

  @override
  void dispose() {
    _subjectRole.dispose();
    _counterpartRole.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SettingCardRelationshipsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.id != widget.card.id && _supported) {
      _loading = true;
      Future<void>.microtask(_load);
    }
  }

  Future<void> _load() async {
    try {
      final management = ref.read(characterRelationshipManagementProvider);
      final service = ref.read(settingCardServiceProvider);
      final relationships =
          await management.listFor(ResourceId(widget.card.id));
      final cards = await service.list();
      if (!mounted) return;
      setState(() {
        _relationships = relationships;
        _cards = cards;
        _loading = false;
      });
    } catch (_) {
      // Relationships are supplementary metadata; a storage failure must not
      // break the document editor.
      if (!mounted) return;
      setState(() {
        _relationships = const <CharacterRelationshipPerspective>[];
        _loading = false;
      });
    }
  }

  SettingCard? get _counterpartCard {
    final id = _counterpartId;
    if (id == null) return null;
    for (final card in _cards) {
      if (card.id == id) return card;
    }
    return null;
  }

  bool get _isCrossWorld {
    final counterpart = _counterpartCard;
    if (counterpart == null) return false;
    final subject = _normalizedOrigin(widget.card.originWorldviewId);
    final other = _normalizedOrigin(counterpart.originWorldviewId);
    // Unbound means "no native world", so it can never be another world.
    // Comparing raw ids would also split legacy ids from card ids that point to
    // the same worldview, so both sides are normalized first.
    if (subject.isEmpty || other.isEmpty) return false;
    return subject != other;
  }

  String _normalizedOrigin(String raw) {
    final id = raw.trim();
    if (id.isEmpty) return '';
    for (final card in _cards) {
      if (card.kind != SettingCardKind.worldview) continue;
      if (card.id == id) return card.id;
      if (card.legacyId != null && card.legacyId == id) return card.id;
    }
    return id;
  }

  bool get _canSave =>
      !_saving &&
      !_isCrossWorld &&
      _counterpartId != null &&
      _subjectRole.text.trim().isNotEmpty &&
      _counterpartRole.text.trim().isNotEmpty;

  String _nameOf(String cardId) {
    for (final card in _cards) {
      if (card.id == cardId) {
        final name = card.name.trim();
        if (name.isNotEmpty) return name;
      }
    }
    return cardId;
  }

  List<AppDropdownOption<String>> get _counterpartOptions =>
      <AppDropdownOption<String>>[
        for (final card in _cards)
          if (card.id != widget.card.id &&
              (card.kind == SettingCardKind.character ||
                  card.kind == SettingCardKind.npc))
            AppDropdownOption<String>(
              value: card.id,
              label: card.name.trim().isEmpty ? card.id : card.name.trim(),
            ),
      ];

  List<AppDropdownOption<CharacterRelationshipType>> _typeOptions(
    AppLocalizations l10n,
  ) =>
      <AppDropdownOption<CharacterRelationshipType>>[
        for (final type in CharacterRelationshipType.values)
          AppDropdownOption<CharacterRelationshipType>(
            value: type,
            label: _relationshipTypeLabel(l10n, type),
          ),
      ];

  void _onTypeChanged(CharacterRelationshipType? type) {
    if (type == null) return;
    setState(() {
      _relationType = type;
      final roles = _directionalRoles[type];
      if (roles != null) {
        _subjectRole.text = roles.$1;
        _counterpartRole.text = roles.$2;
      }
      _error = null;
    });
  }

  Future<void> _save() async {
    final counterpartId = _counterpartId;
    if (counterpartId == null || _isCrossWorld) return;
    if (_subjectRole.text.trim().isEmpty ||
        _counterpartRole.text.trim().isEmpty) {
      setState(() =>
          _error = _l10n(context).settingCardRelationshipMissingFieldsError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(characterRelationshipManagementProvider)
          .createFromPerspective(
            subjectResourceId: ResourceId(widget.card.id),
            counterpartResourceId: ResourceId(counterpartId),
            relationType: _relationType,
            subjectRole: _subjectRole.text.trim(),
            counterpartRole: _counterpartRole.text.trim(),
            description: _description.text.trim(),
          );
      _description.clear();
      _subjectRole.clear();
      _counterpartRole.clear();
      _counterpartId = null;
      _relationType = CharacterRelationshipType.friend;
      await _reloadRelationships();
    } catch (_) {
      if (!mounted) return;
      final message = _l10n(context).settingCardRelationshipSaveFailed;
      setState(() => _error = message);
      AppFeedback.error(context, message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(CharacterRelationshipPerspective relationship) async {
    final management = ref.read(characterRelationshipManagementProvider);
    try {
      await management.delete(relationship.relationshipId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = _l10n(context).settingCardRelationshipSaveFailed);
      return;
    }
    await _reloadRelationships();
  }

  Future<void> _reloadRelationships() async {
    if (!mounted) return;
    final relationships = await ref
        .read(characterRelationshipManagementProvider)
        .listFor(ResourceId(widget.card.id));
    if (!mounted) return;
    setState(() => _relationships = relationships);
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.settingCardRelationshipsTitle,
            style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_relationships.isEmpty)
          Text(
            l10n.settingCardRelationshipsEmpty,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          )
        else
          for (final relationship in _relationships)
            _RelationshipRow(
              key: ValueKey(
                  'setting-card-relationship-${relationship.relationshipId}'),
              relationship: relationship,
              counterpartName:
                  _nameOf(relationship.counterpartResourceId.value),
              deleteTooltip: l10n.deleteAction,
              onDelete: () => _delete(relationship),
            ),
        const SizedBox(height: AppSpacing.lg),
        Text(l10n.settingCardRelationshipAddTitle,
            style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        AppDropdown<String>.form(
          key: const Key('setting-card-relationship-counterpart'),
          label: l10n.settingCardRelationshipCounterpartLabel,
          value: _counterpartId,
          options: _counterpartOptions,
          onChanged: (value) => setState(() {
            _counterpartId = value;
            _error = null;
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        AppDropdown<CharacterRelationshipType>.form(
          key: const Key('setting-card-relationship-type'),
          label: l10n.settingCardRelationshipTypeLabel,
          value: _relationType,
          options: _typeOptions(l10n),
          onChanged: _onTypeChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          key: const Key('setting-card-relationship-subject-role'),
          controller: _subjectRole,
          label: l10n.settingCardRelationshipSubjectRoleLabel,
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          key: const Key('setting-card-relationship-counterpart-role'),
          controller: _counterpartRole,
          label: l10n.settingCardRelationshipCounterpartRoleLabel,
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          key: const Key('setting-card-relationship-description'),
          controller: _description,
          label: l10n.settingCardRelationshipDescriptionLabel,
          maxLines: 2,
          minLines: 1,
        ),
        if (_isCrossWorld) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.settingCardRelationshipCrossWorldError,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ] else if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: const Key('setting-card-relationship-save'),
            onPressed: _canSave ? _save : null,
            child: Text(l10n.saveAction),
          ),
        ),
      ],
    );
  }
}

final class _RelationshipRow extends StatelessWidget {
  const _RelationshipRow({
    super.key,
    required this.relationship,
    required this.counterpartName,
    required this.deleteTooltip,
    required this.onDelete,
  });

  final CharacterRelationshipPerspective relationship;
  final String counterpartName;
  final String deleteTooltip;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final typeLabel = _relationshipTypeLabel(
      _l10n(context),
      relationship.relationType,
    );
    final roles =
        '${relationship.subjectRole} / ${relationship.counterpartRole}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  counterpartName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  '$typeLabel · $roles',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                if (relationship.description.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      relationship.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey(
                'setting-card-relationship-delete-${relationship.relationshipId}'),
            tooltip: deleteTooltip,
            icon: const AppSvgIcon('delete'),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
