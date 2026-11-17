part of 'adventure_wizard_screen.dart';

extension _WizardNavigationActions on _AdventureWizardScreenState {
  Future<void> _openWorldSelectionPage() async {
    final l10n = _l10n(context);
    final selected = await AppRouter.push<Map<String, dynamic>?>(
      context,
      pageBuilder: (_) => WorldSelectionPage(
        initialSelectedId: _selectedWorldviewId,
      ),
    );
    if (selected != null && mounted) {
      _rebuild(() {
        _selectedWorldviewId = selected['id']?.toString();
        _worldviewNameCtrl.text = selected['name']?.toString() ?? '';
        _worldviewDescCtrl.text = selected['description']?.toString() ?? '';
      });
      AppFeedback.success(
        context,
        l10n.worldviewSelectedSuccess(_worldviewNameCtrl.text),
      );
    }
  }

  /// 打开全屏角色选择页面 (R02-C)
  Future<void> _openCharacterSelectionPage() async {
    final l10n = _l10n(context);
    final currentIds = _characters.map((c) => c.id).toSet();
    final selectedList = await AppRouter.push<List<CharacterCardEntry>?>(
      context,
      pageBuilder: (_) => CharacterSelectionPage(
        selectedWorldviewId: _selectedWorldviewId,
        initialSelectedIds: currentIds,
        isMultiSelect: true,
      ),
    );
    if (selectedList != null && mounted) {
      _rebuild(() {
        for (final card in selectedList) {
          if (!_characters.any((c) => c.id == card.id)) {
            _toggleLibraryCard(card);
          }
        }
      });
      AppFeedback.success(context, l10n.rosterUpdatedSuccess);
    }
  }

  /// 打开全屏 NPC 选择页面 (R02-C)
  Future<void> _openNpcSelectionPage() async {
    final l10n = _l10n(context);
    final selectedIds = await AppRouter.push<Set<String>?>(
      context,
      pageBuilder: (_) => NpcSelectionPage(
        selectedWorldviewId: _selectedWorldviewId,
        initialSelectedIds: _selectedNpcIds,
      ),
    );
    if (selectedIds != null && mounted) {
      _rebuild(() {
        _selectedNpcIds
          ..clear()
          ..addAll(selectedIds);
      });
      AppFeedback.success(
        context,
        l10n.npcsSelectedCountSuccess(_selectedNpcIds.length),
      );
    }
  }

  /// 打开全屏序章配置页面 (R02-C)
  Future<void> _openConfigPage() async {
    final l10n = _l10n(context);
    final result = await AppRouter.push<AssemblyConfigData?>(
      context,
      pageBuilder: (_) => AssemblyConfigPage(
        initialOpeningScene: _openingSceneCtrl.text,
        initialOptions: [
          _option1Ctrl.text,
          _option2Ctrl.text,
          _option3Ctrl.text,
        ],
        initialPrompt: _aiPromptCtrl.text,
        worldviewName: _worldviewNameCtrl.text,
        protagonistName:
            _characters.where((c) => c.isProtagonist).firstOrNull?.name,
        aiContext: OpeningAiContext(
          config: _composeAdventureConfig(
            worldview: _worldviewNameCtrl.text.trim(),
          ),
          worldviewDescription: _worldviewDescCtrl.text.trim(),
        ),
      ),
    );
    if (result != null && mounted) {
      _rebuild(() {
        _openingSceneCtrl.text = result.openingScene;
        _option1Ctrl.text =
            result.openingOptions.isNotEmpty ? result.openingOptions[0] : '';
        _option2Ctrl.text =
            result.openingOptions.length > 1 ? result.openingOptions[1] : '';
        _option3Ctrl.text =
            result.openingOptions.length > 2 ? result.openingOptions[2] : '';
        _aiPromptCtrl.text = result.customPrompt;
      });
      AppFeedback.success(context, l10n.openingConfigSavedSuccess);
    }
  }

  /// 打开全屏预览页面 (R02-C)
  Future<void> _openPreviewPage() async {
    final snapshot = _selectedWorldviewId != null
        ? ref.read(adventureSetupControllerProvider).buildWorldviewSnapshot(
              id: _selectedWorldviewId!,
              worldview: _worldviewDescCtrl.text.trim(),
            )
        : null;
    final config = _composeAdventureConfig(
      worldview: _worldviewNameCtrl.text.trim(),
      worldviewSnapshot: snapshot,
    );
    await AppRouter.push<void>(
      context,
      pageBuilder: (_) => AssemblyPreviewPage(
        config: config,
        worldviewDesc: _worldviewDescCtrl.text,
        onStartAdventure: widget.onStartAdventure,
      ),
    );
  }

  /// 进入角色创建/编辑界面（直接复用资料库的新建/编辑角色卡）
  Future<void> _openCharacterEditor({WizardCharacterItem? existing}) async {
    final activeWv = _getActiveWorldviewItem();
    final effectivePresets = _buildEffectiveWorldviews();

    final savedDraft = await showCreateCharacterCardDialog(
      context,
      existingCard:
          existing?.libraryEntry?.rawData ?? existing?.toLibraryRecordMap(),
      existingId: existing?.id,
      defaultMatchingWorldviewId: activeWv['id'] as String,
      worldviewPresets: effectivePresets,
      activeWorldviewDescription: _worldviewDescCtrl.text.trim(),
      mode: ResourceLibraryMode.adventure,
    );

    if (savedDraft != null && mounted) {
      // 重新加载资料库，保持同步
      await _loadData();

      _rebuild(() {
        final id = savedDraft.id ??
            existing?.id ??
            DateTime.now().millisecondsSinceEpoch.toString();
        Map<String, dynamic> rawMap = {};
        try {
          rawMap =
              jsonDecode(savedDraft.toStoredJson()) as Map<String, dynamic>;
        } catch (_) {}

        final libEntry =
            _characterCardEntries.where((c) => c.id == id).firstOrNull;
        final existingIndex = _characters.indexWhere((c) => c.id == id);
        final isFirst = _characters.isEmpty;

        final newItem = WizardCharacterItem(
          id: id,
          name: savedDraft.name,
          gender: savedDraft.isCustomGender
              ? savedDraft.customGender
              : savedDraft.gender,
          age: savedDraft.age,
          profession: savedDraft.profession,
          personality: savedDraft.personality,
          background: savedDraft.description,
          isProtagonist: existing != null ? existing.isProtagonist : isFirst,
          narrativeRole: existing != null
              ? existing.narrativeRole
              : (isFirst
                  ? AdventureCharacterRole.protagonist
                  : AdventureCharacterRole.companion),
          customRoleName: existing?.customRoleName ?? '',
          libraryEntry: libEntry,
          rawJson: rawMap,
        );

        if (existingIndex >= 0) {
          _characters[existingIndex] = newItem;
        } else {
          _characters.add(newItem);
        }

        if (!_characters.any((c) => c.isProtagonist) &&
            _characters.isNotEmpty) {
          _characters.first.isProtagonist = true;
          _characters.first.narrativeRole = AdventureCharacterRole.protagonist;
        }

        _syncRelationships();
      });
    } else if (existing != null && mounted) {
      // 检查角色是否在编辑页面中被删除
      await _loadData();
      final stillExists = _characterCardEntries.any((c) => c.id == existing.id);
      if (!stillExists) {
        _rebuild(() {
          _characters.removeWhere((c) => c.id == existing.id);
          if (!_characters.any((c) => c.isProtagonist) &&
              _characters.isNotEmpty) {
            _characters.first.isProtagonist = true;
            _characters.first.narrativeRole =
                AdventureCharacterRole.protagonist;
          }
          _syncRelationships();
        });
      }
    }
  }

  /// 打开资料库 AI 创作世界观界面
}
