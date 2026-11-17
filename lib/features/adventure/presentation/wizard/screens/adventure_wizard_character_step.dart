part of 'adventure_wizard_screen.dart';

extension _WizardCharacterStep on _AdventureWizardScreenState {
  /// Step 2: 角色设计 (多选角色、赋予身份定位 [男主、女主、男一等]、标明两两角色关系)
  ///
  /// Composition root only: every visual block lives in its own widget under
  /// `widgets/character_step/` and receives explicit props plus callbacks. The
  /// wizard state stays here so step navigation and persistence keep one owner.
  Widget _buildCharacterStep(BuildContext context) {
    final l10n = _l10n(context);
    final scheme = Theme.of(context).colorScheme;

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
          WizardCharacterStepHeader(
            l10n: l10n,
            onNewCharacter: () => _openCharacterEditor(),
            onOpenSelection: _openCharacterSelectionPage,
          ),
          const SizedBox(height: AppSpacing.sm),
          WizardCharacterAiPanel(
            l10n: l10n,
            worldviewName: _worldviewNameCtrl.text.trim(),
            promptController: _aiCharacterPromptCtrl,
            isGenerating: _aiCharacterGenerating,
            isDetailed: _aiCharacterDetailed,
            progressText: _aiCharacterProgress,
            errorText: _aiCharacterError,
            hasRoster: _characters.isNotEmpty,
            associationOptions: _buildAiAssociatedOptions(),
            associationIds: _aiAssociatedCharacterIds,
            associationNames: {
              for (final id in _aiAssociatedCharacterIds)
                id: _getAssociatedCharacterShortName(id),
            },
            relationType: _aiRelationType,
            customRelationController: _aiCustomRelationCtrl,
            onGenerate: _generateCharacterWithAi,
            onOpenCreator: _openAiCharacterCreator,
            onRetry: _generateCharacterWithAi,
            onDismissError: () => _rebuild(() => _aiCharacterError = null),
            onDetailedChanged: (detailed) =>
                _rebuild(() => _aiCharacterDetailed = detailed),
            onAssociationsChanged: (ids) => _rebuild(() {
              _aiAssociatedCharacterIds
                ..clear()
                ..addAll(ids);
            }),
            onClearAssociations: () =>
                _rebuild(() => _aiAssociatedCharacterIds.clear()),
            onRelationTypeChanged: (type) =>
                _rebuild(() => _aiRelationType = type),
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          const SizedBox(height: AppSpacing.sm),

          // 1. 从资料库中选择角色 (若有) 或按 empty / error 分别给出提示
          WizardCharacterLibraryPanel(
            l10n: l10n,
            availableCards: availableCards,
            selectedIds: {for (final c in _characters) c.id},
            selectedWorldviewId: _selectedWorldviewId,
            hasLoadError: _characterLoadError != null,
            malformedCount: _malformedCharacterCardCount,
            onToggleCard: _toggleLibraryCard,
          ),

          // 2. 已选角色阵容列表
          WizardCharacterRosterPanel(
            l10n: l10n,
            characters: _characters,
            onSetProtagonist: _setProtagonist,
            onRemove: _removeCharacter,
            onEdit: (character) => _openCharacterEditor(existing: character),
            onSaveToLibrary: _saveSingleCharacterToLibrary,
            onRoleChanged: (character, role) =>
                _rebuild(() => character.narrativeRole = role),
            onCustomRoleNameChanged: (character, name) =>
                character.customRoleName = name,
          ),

          // 3. 角色羁绊与关系网络 (当角色数 >= 2 时呈现)
          if (_characters.length >= 2)
            WizardCharacterRelationshipPanel(
              l10n: l10n,
              characters: _characters,
              relationships: _relationships,
              onRelationTypeChanged: (relationship, type) =>
                  _rebuild(() => relationship.relationType = type),
              onCustomRelationNameChanged: (relationship, name) =>
                  relationship.customRelationName = name,
              onDescriptionChanged: (relationship, description) =>
                  relationship.description = description,
            ),

          const SizedBox(height: AppSpacing.md),

          // ── 保存到资料库选项与快捷操作 ──
          WizardCharacterLibrarySaveOption(
            l10n: l10n,
            value: _saveCharactersToLibrary,
            isSaving: _savingCharacters,
            onChanged: (value) =>
                _rebuild(() => _saveCharactersToLibrary = value),
            onSaveNow: () => _saveCurrentCharactersToLibrary(),
          ),
        ],
      ),
    );
  }
}
