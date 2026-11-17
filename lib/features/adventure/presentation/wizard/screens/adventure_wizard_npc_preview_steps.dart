part of 'adventure_wizard_screen.dart';

extension _WizardNpcPreviewSteps on _AdventureWizardScreenState {
  Widget _buildNpcStep(BuildContext context) {
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    final orderedNpcs =
        WorldviewCharacterScopePolicy.orderByOriginCompatibility(
      _npcCards,
      _selectedWorldviewId,
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.npcSelectionTitle,
                    style: theme.textTheme.titleMedium),
              ),
              TextButton.icon(
                onPressed: _openNpcSelectionPage,
                icon: const AppSvgIcon('read_aloud', size: 16),
                label: Text(l10n.fullscreenSelectionAction),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.npcSelectionSubtitle,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          if (_npcLoadError != null)
            _resourceBanner(
              context,
              icon: 'error',
              isError: true,
              message: l10n.resourceLoadFailedRetry,
            )
          else if (orderedNpcs.isEmpty)
            _resourceBanner(
              context,
              icon: 'info',
              isError: false,
              message: l10n.npcSelectionEmptyDesc,
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final npc in orderedNpcs)
                  Builder(builder: (context) {
                    final id = npc['id']?.toString() ?? '';
                    final compatibility =
                        WorldviewCharacterScopePolicy.compatibility(
                      npc['matching_worldview_id'],
                      _selectedWorldviewId,
                    );
                    final originLabel = switch (compatibility) {
                      CharacterWorldviewCompatibility.native =>
                        l10n.characterCompatNative,
                      CharacterWorldviewCompatibility.unbound =>
                        l10n.characterCompatUnbound,
                      CharacterWorldviewCompatibility.crossWorld =>
                        l10n.characterCompatCrossWorld,
                    };
                    return FilterChip(
                      selected: _selectedNpcIds.contains(id),
                      avatar: const AppSvgIcon('read_aloud', size: 16),
                      label: Text(
                        '${npc['name']?.toString() ?? l10n.unnamedNpc} · $originLabel',
                      ),
                      onSelected: (selected) {
                        _rebuild(() {
                          if (selected) {
                            _selectedNpcIds.add(id);
                          } else {
                            _selectedNpcIds.remove(id);
                          }
                        });
                      },
                    );
                  }),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPreviewStep(BuildContext context) {
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final hasWorldSnapshot = _selectedWorldviewId != null;
    final protagonist = _characters.where((c) => c.isProtagonist).firstOrNull;
    final protagonistName = protagonist?.name ?? l10n.unnamedHero;
    final protagonistClass = (protagonist?.profession.isNotEmpty ?? false)
        ? protagonist!.profession
        : l10n.adventurerRole;

    final otherCharacters = _characters.where((c) => !c.isProtagonist).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.adventureReadyToEnterTitle,
                    style: theme.textTheme.titleMedium),
              ),
              TextButton.icon(
                onPressed: _openPreviewPage,
                icon: const AppSvgIcon('forward', size: 16),
                label: Text(l10n.fullscreenPreviewButton),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: AppSvgIcon('world', color: colorScheme.primary),
            title: Text(l10n.worldviewSettingLabel(
              _worldviewNameCtrl.text.isNotEmpty
                  ? _worldviewNameCtrl.text
                  : l10n.customUnnamedWorld,
            )),
            subtitle: Text(
              hasWorldSnapshot
                  ? l10n.worldviewSnapshotBoundSummary
                  : (_worldviewDescCtrl.text.isNotEmpty
                      ? _worldviewDescCtrl.text
                      : l10n.defaultContinentRules),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: AppSvgIcon('person', color: colorScheme.secondary),
            title: Text(
                l10n.protagonistLeadLabel(protagonistName, protagonistClass)),
            subtitle: Text(
              protagonist != null && protagonist.personality.isNotEmpty
                  ? l10n.personalityFeatureLabel(protagonist.personality)
                  : (protagonist?.libraryEntry != null
                      ? l10n.characterCardSnapshotBoundSummary
                      : l10n.characterCustomDesignedSummary),
            ),
          ),
          if (otherCharacters.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: AppSvgIcon('group', color: colorScheme.tertiary),
              title: Text(
                  l10n.accompanyingCharactersCount(otherCharacters.length)),
              subtitle: Text(
                otherCharacters.map((c) {
                  final role =
                      c.narrativeRole == AdventureCharacterRole.custom &&
                              c.customRoleName.trim().isNotEmpty
                          ? c.customRoleName.trim()
                          : localizedAdventureRole(c.narrativeRole, l10n);
                  return '${c.name} [$role${c.profession.isNotEmpty ? " · ${c.profession}" : ""}]';
                }).join('、'),
              ),
            ),
          if (_selectedNpcIds.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: AppSvgIcon('read_aloud', color: colorScheme.tertiary),
              title: Text(l10n.residentNpcsCount(_selectedNpcIds.length)),
              subtitle: Text(
                _npcCards
                    .where((npc) =>
                        _selectedNpcIds.contains(npc['id']?.toString()))
                    .map((npc) => npc['name']?.toString() ?? l10n.unnamedNpc)
                    .join('、'),
              ),
            ),
          if (_relationships.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: AppSvgIcon('graph', color: colorScheme.primary),
              title: Text(l10n.characterBondsCount(_relationships.length)),
              subtitle: Text(
                _relationships.map((r) {
                  final c1 = _characters
                      .where((c) => c.id == r.sourceCharacterId)
                      .firstOrNull;
                  final c2 = _characters
                      .where((c) => c.id == r.targetCharacterId)
                      .firstOrNull;
                  final n1 = c1?.name ?? l10n.unnamedCharacterA;
                  final n2 = c2?.name ?? l10n.unnamedCharacterB;
                  final desc =
                      r.description.isNotEmpty ? ' (${r.description})' : '';
                  final relation =
                      r.relationType == AdventureRelationType.custom &&
                              r.customRelationName.trim().isNotEmpty
                          ? r.customRelationName.trim()
                          : localizedAdventureRelation(r.relationType, l10n);
                  return '$n1 ⇄ $n2: $relation$desc';
                }).join('；'),
              ),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: AppSvgIcon('play', color: colorScheme.tertiary),
            title: Text(l10n.openingSceneTitle),
            subtitle: Text(
              _openingSceneCtrl.text.isNotEmpty
                  ? _openingSceneCtrl.text
                  : l10n.aiDynamicOpeningSummary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _savingPreview ? null : _savePreview,
              icon: _savingPreview
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const AppSvgIcon('bookmark', size: 18),
              label: Text(
                  _savingPreview ? l10n.partSaving : l10n.savePreviewAction),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.previewTemplateNoStartHint,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
