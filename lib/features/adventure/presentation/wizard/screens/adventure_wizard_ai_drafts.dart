part of 'adventure_wizard_screen.dart';

extension _WizardAiDrafts on _AdventureWizardScreenState {
  Future<void> _openAiWorldviewCreator() async {
    final l10n = _l10n(context);
    final oldIds = _worldviews.map((w) => w['id']?.toString()).toSet();

    WorldviewTab.showAiImport(
      context,
      () async {
        await _loadData();
        if (!mounted) return;

        final newWv = _worldviews
            .where((w) => !oldIds.contains(w['id']?.toString()))
            .firstOrNull;

        if (newWv != null) {
          _rebuild(() {
            _selectedWorldviewId = newWv['id'] as String;
            _worldviewNameCtrl.text = newWv['name'] as String? ?? '';
            _worldviewDescCtrl.text = newWv['description'] as String? ?? '';
          });
          AppFeedback.success(
            context,
            l10n.worldviewSelectedSuccess(newWv['name']?.toString() ?? ''),
          );
        }
      },
      _worldviews,
      mode: ResourceLibraryMode.adventure,
    );
  }

  /// AI 自动编写世界观设定（支持简约模式与详细模式4段多轮连续生成）
  Future<void> _generateWorldviewWithAi() async {
    final l10n = _l10n(context);
    final chat = ref.read(chatProvider);
    if (!chat.isKeyConfigured) {
      AppFeedback.info(context, l10n.configureApiKeyFirstForAi);
      showApiSettings(context);
      return;
    }

    final source = _aiWorldviewPromptCtrl.text.trim().isEmpty
        ? '请规划一个适合冒险创建的世界观'
        : _aiWorldviewPromptCtrl.text.trim();
    await AppRouter.push<void>(
      context,
      pageBuilder: (_) => ResourceStudioPage(
        creationDraft: ResourceStudioCreationDraft(
          type: ResourceType.worldview,
          name: '冒险世界观',
          referenceSource: ReferenceSource.text(
            source,
            label: 'adventure wizard worldview',
          ),
          targetCharacters: _aiWorldviewDetailed ? 10000 : 4000,
          origin: 'adventure-wizard',
          libraryMode: ResourceLibraryMode.adventure.storageValue,
        ),
      ),
    );
    if (mounted) await _loadData();
  }

  /// AI 自动编写角色设定（支持简约模式与详细全维模式生成）
  Future<void> _generateCharacterWithAi() async {
    final l10n = _l10n(context);
    final chat = ref.read(chatProvider);
    if (!chat.isKeyConfigured) {
      AppFeedback.info(context, l10n.configureApiKeyFirstForAi);
      showApiSettings(context);
      return;
    }

    var source = _aiCharacterPromptCtrl.text.trim();
    if (source.isEmpty) source = '请规划一个适合当前冒险的角色';

    final relatedNames = _aiAssociatedCharacterIds
        .map(_getAssociatedCharacterShortName)
        .where((name) => name.trim().isNotEmpty)
        .toList();
    if (relatedNames.isNotEmpty) {
      final relation = _aiRelationType == '自定义'
          ? (_aiCustomRelationCtrl.text.trim().isEmpty
              ? '伙伴'
              : _aiCustomRelationCtrl.text.trim())
          : _aiRelationType;
      source += '。请与已有角色「${relatedNames.join('、')}」建立【$relation】羁绊。';
    }

    await AppRouter.push<void>(
      context,
      pageBuilder: (_) => ResourceStudioPage(
        creationDraft: ResourceStudioCreationDraft(
          type: ResourceType.character,
          name: '冒险角色',
          referenceSource: ReferenceSource.text(
            source,
            label: 'adventure wizard character',
          ),
          targetCharacters: _aiCharacterDetailed
              ? GenerationLimits.detailedCharacterDefaultCharacters
              : GenerationLimits.detailedCharacterMinimumCharacters,
          origin: 'adventure-wizard',
          libraryMode: ResourceLibraryMode.adventure.storageValue,
        ),
      ),
    );
    if (mounted) await _loadData();
  }

  /// 获取关联角色的简短显示名称
  String _getAssociatedCharacterShortName(String id) {
    final c = _characters.where((char) => char.id == id).firstOrNull;
    if (c != null) return c.name;
    final card = _characterCardEntries.where((e) => e.id == id).firstOrNull;
    if (card != null) return card.name;
    return id;
  }

  /// 构建关联已有角色下拉选项（优先队伍成员，其次资料库中尚未加入队伍的角色）
  List<AppDropdownOption<String>> _buildAiAssociatedOptions() {
    final l10n = _l10n(context);
    final options = <AppDropdownOption<String>>[];
    for (final c in _characters) {
      final roleTag =
          c.isProtagonist ? l10n.mainProtagonistTitle : l10n.relationCompanion;
      final subList = <String>[
        roleTag,
        if (c.gender.isNotEmpty) c.gender,
        if (c.profession.isNotEmpty) c.profession,
      ];
      options.add(AppDropdownOption(
        value: c.id,
        label: '${c.name} ($roleTag)',
        subtitle: subList.join(' · '),
      ));
    }
    final partyIds = _characters.map((c) => c.id).toSet();
    final partyNames = _characters.map((c) => c.name.trim()).toSet();
    for (final card in _characterCardEntries) {
      if (partyIds.contains(card.id) || partyNames.contains(card.name.trim())) {
        continue;
      }
      final subList = <String>[
        l10n.resourceLibraryTitle,
        if (card.gender.isNotEmpty) card.gender,
        if (card.profession.isNotEmpty) card.profession,
      ];
      options.add(AppDropdownOption(
        value: card.id,
        label: '${card.name} (${l10n.resourceLibraryTitle})',
        subtitle: subList.join(' · '),
      ));
    }
    return options;
  }

  /// 打开资料库 AI 创作角色卡并直接加入当前向导队伍
  Future<void> _openAiCharacterCreator() async {
    final l10n = _l10n(context);
    final detailMode = await showSceneImportDetailModePicker(context);
    if (!mounted || detailMode == null) return;

    final oldIds = _characterCardEntries.map((c) => c.id).toSet();
    final effectiveWorldviews = _buildEffectiveWorldviews();
    final activeId = _getOrCreateActiveWorldviewId();

    CharacterCardTab.showAiImport(
      context,
      () async {
        await _loadData();
        if (!mounted) return;

        final newCards =
            _characterCardEntries.where((c) => !oldIds.contains(c.id)).toList();

        if (newCards.isNotEmpty) {
          _rebuild(() {
            for (final card in newCards) {
              if (!_characters.any((c) => c.id == card.id)) {
                final isFirst = _characters.isEmpty;
                _characters.add(WizardCharacterItem(
                  id: card.id,
                  name: card.name,
                  gender: card.gender,
                  age: card.age,
                  profession: card.profession,
                  personality: card.personality,
                  background: card.background,
                  isProtagonist: isFirst,
                  narrativeRole: isFirst
                      ? AdventureCharacterRole.protagonist
                      : AdventureCharacterRole.companion,
                  libraryEntry: card,
                  rawJson: card.rawData,
                ));
              }
            }
            _syncRelationships();
          });
          AppFeedback.success(
              context, l10n.charactersAddedToRoster(newCards.length));
        }
      },
      effectiveWorldviews,
      characterCards: _characterCardEntries.map((c) => c.rawData).toList(),
      detailInstruction: detailMode.instruction,
      aiDepth: detailMode == SceneImportDetailMode.detailed
          ? AiGenerationDepth.detailed
          : AiGenerationDepth.simple,
      initialWorldviewId: activeId,
      mode: ResourceLibraryMode.adventure,
    );
  }

  /// AI 自动编写序章与初始行动分支
  ///
  /// 与装配流水线共用同一套生成逻辑 ([generateOpeningWithAi])，避免出现第二套
  /// 序章生成实现。
  Future<void> _generateOpeningWithAi() async {
    final l10n = _l10n(context);
    final chat = ref.read(chatProvider);
    if (!chat.isKeyConfigured) {
      AppFeedback.info(context, l10n.configureApiKeyFirstForAi);
      showApiSettings(context);
      return;
    }

    _rebuild(() {
      _aiGenerating = true;
      _aiGenError = null;
    });

    try {
      final outcome = await generateOpeningWithAi(
        ref: ref,
        prompt: _aiPromptCtrl.text.trim(),
        context: OpeningAiContext(
          config: _composeAdventureConfig(
            worldview: _worldviewNameCtrl.text.trim(),
          ),
          worldviewDescription: _worldviewDescCtrl.text.trim(),
        ),
      );

      if (!mounted) return;

      if (outcome == null) {
        _rebuild(() {
          _aiGenerating = false;
          _aiGenError = ref.read(adventureAiControllerProvider).errorMessage ??
              l10n.aiGenerationNoValidContent;
        });
        return;
      }

      _rebuild(() {
        _aiGenerating = false;
        if (outcome.scene.isNotEmpty) {
          _openingSceneCtrl.text = outcome.scene;
        }
        if (outcome.options.isNotEmpty) {
          _option1Ctrl.text = outcome.options[0];
          _option2Ctrl.text =
              outcome.options.length > 1 ? outcome.options[1] : '';
          _option3Ctrl.text =
              outcome.options.length > 2 ? outcome.options[2] : '';
        }
      });

      AppFeedback.success(context, l10n.aiOpeningGeneratedSuccess);
    } catch (e) {
      if (!mounted) return;
      _rebuild(() {
        _aiGenerating = false;
        _aiGenError = l10n.aiGenerationFailed(
          localizeAppError(l10n, asAppDomainError(e)),
        );
      });
    }
  }
}
