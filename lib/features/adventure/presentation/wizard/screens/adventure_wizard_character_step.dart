part of 'adventure_wizard_screen.dart';

extension _WizardCharacterStep on _AdventureWizardScreenState {
  /// Step 2: 角色设计 (多选角色、赋予身份定位 [男主、女主、男一、女一等]、标明两两角色关系)
  Widget _buildCharacterStep(BuildContext context) {
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Damaged legacy rows stay listed in the status banner but can never be
    // selected: only fully parsed cards enter the adventure roster.
    final availableCards = [
      ..._characterCardEntries.where((entry) => !entry.hasParseError),
    ]..sort((left, right) {
        final leftRank = WorldviewCharacterScopePolicy.compatibility(
          left.matchingWorldviewId,
          _selectedWorldviewId,
        ).index;
        final rightRank = WorldviewCharacterScopePolicy.compatibility(
          right.matchingWorldviewId,
          _selectedWorldviewId,
        ).index;
        return leftRank.compareTo(rightRank);
      });
    if (!_aiAssociationInitialized && _characters.isNotEmpty) {
      _aiAssociationInitialized = true;
      _aiAssociatedCharacterIds.add(_characters.first.id);
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标头与新建角色按钮
          LayoutBuilder(builder: (context, constraints) {
            final stackActions = constraints.maxWidth < 420;
            return stackActions
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        AppSvgIcon('group', size: 20, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(l10n.characterSelectionTitle,
                                style: theme.textTheme.titleMedium)),
                      ]),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () => _openCharacterEditor(),
                            icon: const AppSvgIcon('person_add', size: 16),
                            label: Text(l10n.newCharacterAction),
                          ),
                          OutlinedButton.icon(
                            onPressed: _openCharacterSelectionPage,
                            icon: const AppSvgIcon('person_search', size: 16),
                            label: Text(l10n.fullscreenSelectionAction),
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      AppSvgIcon('group', size: 20, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(l10n.characterSelectionTitle,
                            style: theme.textTheme.titleMedium),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _openCharacterEditor(),
                        icon: const AppSvgIcon('person_add', size: 16),
                        label: Text(l10n.newCharacterAction),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      OutlinedButton.icon(
                        onPressed: _openCharacterSelectionPage,
                        icon: const AppSvgIcon('person_search', size: 16),
                        label: Text(l10n.fullscreenSelectionAction),
                      ),
                    ],
                  );
          }),
          const SizedBox(height: AppSpacing.sm),

          // AI 快速自动编写角色卡片（与世界观、序章剧情风格高度统一）
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.28),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.xs + 2,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppSvgIcon(
                      'generation',
                      color: scheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.xs + 2),
                    Text(
                      l10n.characterAiAssistantCreateTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
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
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.wizardCharacterAiSummary(
                    _worldviewNameCtrl.text.trim().isNotEmpty
                        ? _worldviewNameCtrl.text.trim()
                        : l10n.currentWorldviewLabel,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _aiCharacterPromptCtrl,
                  enabled: !_aiCharacterGenerating,
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
                _buildAiCharacterAssociationSection(scheme, theme),
                if (_aiCharacterError != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
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
                        AppSvgIcon(
                          'error',
                          color: scheme.error,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            _aiCharacterError!,
                            style: TextStyle(
                              color: scheme.onErrorContainer,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _aiCharacterGenerating
                              ? null
                              : _generateCharacterWithAi,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            visualDensity: VisualDensity.compact,
                            foregroundColor: scheme.error,
                          ),
                          child: Text(l10n.retryAction,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        IconButton(
                          icon: const AppSvgIcon('close', size: 16),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              _rebuild(() => _aiCharacterError = null),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Wrap(
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
                      label: Text(l10n.conciseMode,
                          style: const TextStyle(fontSize: 12)),
                      selected: !_aiCharacterDetailed,
                      onSelected: _aiCharacterGenerating
                          ? null
                          : (v) {
                              if (v) {
                                _rebuild(() => _aiCharacterDetailed = false);
                              }
                            },
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text(l10n.detailedMode,
                          style: const TextStyle(fontSize: 12)),
                      selected: _aiCharacterDetailed,
                      onSelected: _aiCharacterGenerating
                          ? null
                          : (v) {
                              if (v) {
                                _rebuild(() => _aiCharacterDetailed = true);
                              }
                            },
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    if (_aiCharacterProgress != null) ...[
                      const SizedBox(width: 12),
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _aiCharacterProgress!,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    FilledButton.icon(
                      onPressed: _aiCharacterGenerating
                          ? null
                          : _generateCharacterWithAi,
                      icon: _aiCharacterGenerating
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
                        _aiCharacterGenerating
                            ? (_aiCharacterDetailed
                                ? l10n.wizardWorldviewGeneratingDetailed
                                : l10n.wizardWorldviewGeneratingBrief)
                            : (_characters.isEmpty
                                ? l10n.wizardGenerateMainCharacterAction
                                : l10n.wizardAddCharacterToRosterAction),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: _aiCharacterGenerating
                          ? null
                          : _openAiCharacterCreator,
                      icon: const AppSvgIcon('book', size: 16),
                      label: Text(l10n.characterAiAssistantCreateTitle),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          const SizedBox(height: AppSpacing.sm),

          // 1. 从资料库中选择角色 (若有) 或按 empty / error 分别给出提示
          if (_characterLoadError != null)
            _resourceBanner(
              context,
              icon: 'error',
              isError: true,
              message: _malformedCharacterCardCount > 0
                  ? l10n.wizardMalformedCharacterCards(
                      _malformedCharacterCardCount,
                    )
                  : l10n.resourceLoadFailedRetry,
            )
          else if (_malformedCharacterCardCount > 0)
            _resourceBanner(
              context,
              icon: 'warning',
              isError: true,
              message: l10n.wizardMalformedCharacterCards(
                _malformedCharacterCardCount,
              ),
            ),
          if (availableCards.isNotEmpty) ...[
            Text(
              l10n.characterSelectionSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: availableCards.map((card) {
                final isSelected = _characters.any((c) => c.id == card.id);
                final compatibility =
                    WorldviewCharacterScopePolicy.compatibility(
                  card.matchingWorldviewId,
                  _selectedWorldviewId,
                );
                final originLabel = switch (compatibility) {
                  CharacterWorldviewCompatibility.native =>
                    ' · ${l10n.characterCompatNative}',
                  CharacterWorldviewCompatibility.unbound =>
                    ' · ${l10n.characterCompatUnbound}',
                  CharacterWorldviewCompatibility.crossWorld =>
                    ' · ${l10n.characterCompatCrossWorld}',
                };

                return ChoiceChip(
                  avatar: isSelected
                      ? const AppSvgIcon('check', size: 14)
                      : const AppSvgIcon('person', size: 14),
                  label: Text(
                    '${card.name}${card.profession.isNotEmpty ? " (${card.profession})" : ""}$originLabel',
                  ),
                  selected: isSelected,
                  onSelected: (_) => _toggleLibraryCard(card),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.md),
          ] else if (_characterLoadError == null) ...[
            _resourceBanner(
              context,
              icon: 'info',
              isError: false,
              message: l10n.characterSelectionEmptyDesc,
            ),
          ],

          // 2. 已选角色阵容列表
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xs,
            runSpacing: 2,
            children: [
              Text(
                l10n.rosterSectionTitle(_characters.length),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_characters.isNotEmpty)
                Text(
                  l10n.rosterSectionDesc,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: scheme.outline,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (_characters.isEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                children: [
                  AppSvgIcon(
                    'group',
                    size: 36,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.noCharactersAddedYet,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.clickAboveToAddCharactersHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // 角色列表
            ..._characters.map((character) {
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: character.isProtagonist
                      ? scheme.primaryContainer.withValues(alpha: 0.15)
                      : scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: character.isProtagonist
                        ? scheme.primary.withValues(alpha: 0.5)
                        : scheme.outlineVariant.withValues(alpha: 0.6),
                    width: character.isProtagonist ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 头部：头像、姓名、主控标识与操作
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: character.isProtagonist
                              ? scheme.primary
                              : scheme.secondaryContainer,
                          child: Text(
                            character.name.isNotEmpty ? character.name[0] : '?',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: character.isProtagonist
                                  ? Colors.white
                                  : scheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            children: [
                              Text(
                                character.name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (character.profession.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    character.profession,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: scheme.onSurfaceVariant),
                                  ),
                                ),
                              if (character.gender.isNotEmpty ||
                                  character.age.isNotEmpty)
                                Text(
                                  [
                                    if (character.gender.isNotEmpty)
                                      character.gender,
                                    if (character.age.isNotEmpty)
                                      l10n.characterAgeYears(character.age),
                                  ].join(' · '),
                                  style: TextStyle(
                                      fontSize: 11, color: scheme.outline),
                                ),
                            ],
                          ),
                        ),
                        if (character.isProtagonist)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const AppSvgIcon('star',
                                    size: 14, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  l10n.mainProtagonistTitle,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: () => _setProtagonist(character.id),
                            icon: const AppSvgIcon('star', size: 14),
                            label: Text(l10n.setAsMainProtagonist,
                                style: const TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                            ),
                          ),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: () =>
                              _saveSingleCharacterToLibrary(character),
                          icon: const AppSvgIcon('bookmark', size: 18),
                          tooltip: l10n.saveToLibraryNow,
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          onPressed: () =>
                              _openCharacterEditor(existing: character),
                          icon: const AppSvgIcon('edit', size: 18),
                          tooltip: l10n.editAction,
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          onPressed: () => _removeCharacter(character.id),
                          icon: const AppSvgIcon('close', size: 18),
                          tooltip: l10n.removeRosterCharacter,
                          visualDensity: VisualDensity.compact,
                          color: scheme.error,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 身份定位赋予 (包含男主、女主、男一、女一等)
                    Row(
                      children: [
                        Text(
                          l10n.scriptRoleOrientation,
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(width: 8),
                        if (character.isProtagonist)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              l10n.mainProtagonistDescription,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.primary),
                            ),
                          )
                        else ...[
                          AppDropdown<String>.compact(
                            value: character.narrativeRole,
                            options: [
                              AdventureCharacterRole.maleLead,
                              AdventureCharacterRole.femaleLead,
                              AdventureCharacterRole.maleOne,
                              AdventureCharacterRole.femaleOne,
                              AdventureCharacterRole.maleTwo,
                              AdventureCharacterRole.femaleTwo,
                              AdventureCharacterRole.companion,
                              AdventureCharacterRole.mentor,
                              AdventureCharacterRole.family,
                              AdventureCharacterRole.supporting,
                              AdventureCharacterRole.villain,
                              AdventureCharacterRole.custom,
                            ].map((role) {
                              return AppDropdownOption(
                                value: role,
                                label: _localizedAdventureRole(role, l10n),
                              );
                            }).toList(),
                            onChanged: (newRole) {
                              if (newRole != null) {
                                _rebuild(() {
                                  character.narrativeRole = newRole;
                                });
                              }
                            },
                          ),
                          if (character.narrativeRole ==
                              AdventureCharacterRole.custom) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: SizedBox(
                                height: 32,
                                child: TextField(
                                  controller: TextEditingController(
                                      text: character.customRoleName)
                                    ..selection = TextSelection.collapsed(
                                        offset:
                                            character.customRoleName.length),
                                  decoration: InputDecoration(
                                    hintText: l10n.scriptRoleOrientation,
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 6),
                                  ),
                                  style: const TextStyle(fontSize: 12),
                                  onChanged: (val) =>
                                      character.customRoleName = val.trim(),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),

                    // 人设立体细节 (性格、背景展示)
                    if (character.personality.isNotEmpty ||
                        character.background.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest
                              .withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (character.personality.isNotEmpty)
                              Text(
                                l10n.personalityFeatureLabel(
                                  character.personality,
                                ),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (character.background.isNotEmpty)
                              Text(
                                l10n.backgroundStoryPrefix(
                                  character.background,
                                ),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],

          // 3. 角色羁绊与关系网络 (当角色数 >= 2 时呈现)
          if (_characters.length >= 2) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                AppSvgIcon('graph', size: 20, color: scheme.tertiary),
                const SizedBox(width: 8),
                Text(
                  l10n.relationshipNetworkTitle,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    l10n.characterBondsCount(_relationships.length),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.relationshipNetworkDescription,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm + 4),
            ..._relationships.map((rel) {
              final c1 = _characters
                  .where((c) => c.id == rel.sourceCharacterId)
                  .firstOrNull;
              final c2 = _characters
                  .where((c) => c.id == rel.targetCharacterId)
                  .firstOrNull;
              if (c1 == null || c2 == null) return const SizedBox.shrink();

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // 角色 A ⇄ 角色 B
                        Expanded(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 4,
                            children: [
                              Text(
                                c1.name,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              if (c1.isProtagonist)
                                Text(' (${l10n.protagonistShortTag})',
                                    style: TextStyle(
                                        fontSize: 10, color: scheme.primary)),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4),
                                child: AppSvgIcon('swap', size: 16),
                              ),
                              Text(
                                c2.name,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              if (c2.isProtagonist)
                                Text(' (${l10n.protagonistShortTag})',
                                    style: TextStyle(
                                        fontSize: 10, color: scheme.primary)),
                            ],
                          ),
                        ),
                        // 关系类型下拉选
                        AppDropdown<String>.compact(
                          value: rel.relationType,
                          options: [
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
                          ].map((type) {
                            return AppDropdownOption(
                              value: type,
                              label: _localizedAdventureRelation(type, l10n),
                            );
                          }).toList(),
                          onChanged: (newType) {
                            if (newType != null) {
                              _rebuild(() {
                                rel.relationType = newType;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    if (rel.assetSuggestion.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        l10n.relationAssetReference(rel.assetSuggestion),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (rel.relationType == AdventureRelationType.custom) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 32,
                        child: TextField(
                          controller: TextEditingController(
                              text: rel.customRelationName)
                            ..selection = TextSelection.collapsed(
                                offset: rel.customRelationName.length),
                          decoration: InputDecoration(
                            labelText: l10n.relationCustomDescLabel,
                            border: const OutlineInputBorder(),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                          ),
                          style: const TextStyle(fontSize: 12),
                          onChanged: (val) =>
                              rel.customRelationName = val.trim(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 32,
                      child: TextField(
                        controller: TextEditingController(text: rel.description)
                          ..selection = TextSelection.collapsed(
                              offset: rel.description.length),
                        decoration: InputDecoration(
                          hintText: l10n.relationDetailsHint,
                          border: OutlineInputBorder(
                            borderSide: BorderSide(
                                color: scheme.outlineVariant
                                    .withValues(alpha: 0.5)),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                        ),
                        style: const TextStyle(fontSize: 11),
                        onChanged: (val) => rel.description = val.trim(),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: AppSpacing.md),

          // ── 保存到资料库选项与快捷操作 ──
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 560;
              final childContent = Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Checkbox(
                    value: _saveCharactersToLibrary,
                    onChanged: (val) {
                      _rebuild(() {
                        _saveCharactersToLibrary = val ?? true;
                      });
                    },
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        _rebuild(() {
                          _saveCharactersToLibrary = !_saveCharactersToLibrary;
                        });
                      },
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Wrap instead of a fixed Row: on narrow phones the
                            // badge moves below the title instead of pushing
                            // the title out of the card.
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
                                    color:
                                        scheme.primary.withValues(alpha: 0.12),
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
                    FilledButton.tonalIcon(
                      onPressed: _savingCharacters
                          ? null
                          : () => _saveCurrentCharactersToLibrary(),
                      icon: _savingCharacters
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const AppSvgIcon('bookmark', size: 16),
                      label: Text(_savingCharacters
                          ? l10n.partSaving
                          : l10n.saveToLibraryNow),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
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
                              onPressed: _savingCharacters
                                  ? null
                                  : () => _saveCurrentCharactersToLibrary(),
                              icon: _savingCharacters
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const AppSvgIcon('bookmark', size: 16),
                              label: Text(_savingCharacters
                                  ? l10n.partSaving
                                  : l10n.saveToLibraryNow),
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
          ),
        ],
      ),
    );
  }
}
