part of 'adventure_wizard_screen.dart';

/// Soft length target for one detailed generation pass.
///
/// The prompt asks the model for roughly this many characters. Nothing
/// validates or trims the result afterwards, so a shorter or longer answer is
/// still saved as-is.
const int _aiDetailedTargetCharacters = 12000;

/// Fallback titles used when a generated card comes back without a name.
///
/// The wizard creates the draft card with an empty name so that
/// `SettingCardService.generate` can promote the model's title into the card;
/// these labels only cover a model answer that carried no title at all.
const String _fallbackWorldviewName = '冒险世界观';
const String _fallbackCharacterName = '冒险角色';

extension _WizardAiDrafts on _AdventureWizardScreenState {
  /// AI 自动编写世界观设定（支持简约模式与详细模式4段多轮连续生成）
  ///
  /// 生成结束后把卡片回填到当前步骤：选中该卡片，并写入标题与描述，用户无需
  /// 再从资料库列表里手动挑选刚生成的这一张。
  Future<void> _generateWorldviewWithAi() async {
    // The button is disabled while generating; the guard also covers a second
    // tap that lands before the disabled rebuild is painted.
    if (_aiWorldviewGenerating) return;
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

    _rebuild(() {
      _aiWorldviewGenerating = true;
      _aiWorldviewProgress = null;
      _aiWorldviewError = null;
    });

    final service = ref.read(settingCardServiceProvider);
    String? createdId;
    try {
      // A worldview has no parent card, so it never carries an origin id. The
      // empty name lets the generated title win instead of being discarded.
      final card = await service.createFromType(
        type: ResourceType.worldview.storageValue,
        name: '',
        mode: ResourceLibraryMode.adventure.storageValue,
        originWorldviewId: '',
      );
      createdId = card.id;
      final generated = await service.generate(
        id: card.id,
        instruction: source,
        targetTotalCharacters:
            _aiWorldviewDetailed ? _aiDetailedTargetCharacters : null,
        onProgress: (current, total, _) {
          if (!mounted) return;
          _rebuild(() => _aiWorldviewProgress = '$current / $total');
        },
      );
      if (!mounted) return;
      // Reload first: the chip list has to contain the card before selecting it,
      // and the reload also publishes the card's structured detail payload.
      await _loadData();
      if (!mounted) return;
      _rebuild(() => _applyGeneratedWorldview(generated));
    } catch (e) {
      // A failed first pass must not leave an unnamed empty card behind.
      if (createdId != null) await service.discardEmptyDraft(createdId);
      if (!mounted) return;
      AppFeedback.error(
        context,
        l10n.aiGenerationFailed(localizeAppError(l10n, asAppDomainError(e))),
      );
    } finally {
      if (mounted) {
        _rebuild(() {
          _aiWorldviewGenerating = false;
          _aiWorldviewProgress = null;
        });
      }
    }
  }

  /// Selects a freshly generated worldview card and fills the step's fields.
  void _applyGeneratedWorldview(SettingCard card) {
    _selectedWorldviewId = card.id;
    final name = card.name.trim();
    _worldviewNameCtrl.text = name.isEmpty ? _fallbackWorldviewName : name;
    final summary = card.summary.trim();
    _worldviewDescCtrl.text =
        summary.isNotEmpty ? summary : _firstProseParagraph(card.content);
  }

  /// First prose block of a generated markdown document.
  ///
  /// Generated cards start with headings (`## description`) and may contain
  /// JSON fences, none of which belong in the single-line description field.
  String _firstProseParagraph(String content) {
    var inFence = false;
    final paragraph = <String>[];
    for (final line in const LineSplitter().convert(content)) {
      final trimmed = line.trim();
      if (trimmed.startsWith('```')) {
        if (paragraph.isNotEmpty) break;
        inFence = !inFence;
        continue;
      }
      if (inFence) continue;
      if (trimmed.startsWith('#')) {
        if (paragraph.isNotEmpty) break;
        continue;
      }
      if (trimmed.isEmpty) {
        if (paragraph.isNotEmpty) break;
        continue;
      }
      paragraph.add(trimmed);
    }
    return paragraph.join('\n');
  }

  /// AI 自动编写角色设定（支持简约模式与详细全维模式生成）
  ///
  /// 生成结束后把新卡片加入当前阵容，避免用户生成完还要去资料库里再找一次。
  Future<void> _generateCharacterWithAi() async {
    if (_aiCharacterGenerating) return;
    final l10n = _l10n(context);
    final chat = ref.read(chatProvider);
    if (!chat.isKeyConfigured) {
      AppFeedback.info(context, l10n.configureApiKeyFirstForAi);
      showApiSettings(context);
      return;
    }

    var source = _aiCharacterPromptCtrl.text.trim();
    if (source.isEmpty) source = '请规划一个适合当前冒险的角色';

    final relation = _aiRelationType == '自定义'
        ? (_aiCustomRelationCtrl.text.trim().isEmpty
            ? '伙伴'
            : _aiCustomRelationCtrl.text.trim())
        : _aiRelationType;
    final associatedCharacters = _buildAssociatedCharacterContext(relation);

    _rebuild(() {
      _aiCharacterGenerating = true;
      _aiCharacterProgress = null;
      _aiCharacterError = null;
    });

    final service = ref.read(settingCardServiceProvider);
    String? createdId;
    try {
      final activeWorldviewId = _getOrCreateActiveWorldviewId();
      // Empty name: the generated character title wins over a placeholder.
      final card = await service.createFromType(
        type: ResourceType.character.storageValue,
        name: '',
        mode: ResourceLibraryMode.adventure.storageValue,
        originWorldviewId: activeWorldviewId,
      );
      createdId = card.id;
      // Prefer the persisted worldview body: it still carries the structured
      // detail modules that the single description field does not expose.
      // Unsaved or not-yet-mirrored worldviews fall back to the editor text.
      var worldviewBody = _worldviewDescCtrl.text.trim();
      final worldviewCard = await service.find(activeWorldviewId);
      if (worldviewCard != null &&
          !worldviewCard.isDeleted &&
          worldviewCard.content.trim().isNotEmpty) {
        worldviewBody = worldviewCard.content;
      }
      final generated = await service.generate(
        id: card.id,
        instruction: source,
        worldview: worldviewBody,
        associatedCharacters: associatedCharacters,
        targetTotalCharacters:
            _aiCharacterDetailed ? _aiDetailedTargetCharacters : null,
        onProgress: (stage, total, stageName) {
          if (!mounted) return;
          final label = stageName.trim();
          _rebuild(() => _aiCharacterProgress =
              label.isEmpty ? '$stage / $total' : '$stage / $total · $label');
        },
      );
      if (!mounted) return;
      // Reload so the roster entry carries the card's persisted payload, then
      // add it to the party.
      await _loadData();
      if (!mounted) return;
      _rebuild(() => _addGeneratedCharacter(generated));
    } catch (e) {
      if (createdId != null) await service.discardEmptyDraft(createdId);
      if (!mounted) return;
      AppFeedback.error(
        context,
        l10n.aiGenerationFailed(localizeAppError(l10n, asAppDomainError(e))),
      );
    } finally {
      if (mounted) {
        _rebuild(() {
          _aiCharacterGenerating = false;
          _aiCharacterProgress = null;
        });
      }
    }
  }

  /// Adds a freshly generated character card to the roster.
  ///
  /// Reuses [_bindCharacterFromLibrary] so a generated card behaves exactly like
  /// one the user picked from the library: the first roster member becomes the
  /// protagonist and an already-present id is never added twice.
  void _addGeneratedCharacter(SettingCard card) {
    if (_characters.any((c) => c.id == card.id)) return;
    final entry =
        _characterCardEntries.where((e) => e.id == card.id).firstOrNull;
    if (entry != null && !entry.hasParseError) {
      _bindCharacterFromLibrary(entry);
      return;
    }
    // The refreshed library list does not carry this card (or its row is
    // malformed), so build the roster entry straight from the card body.
    final isFirst = _characters.isEmpty;
    final name =
        card.name.trim().isEmpty ? _fallbackCharacterName : card.name.trim();
    final prose = _firstProseParagraph(card.content);
    final background = prose.isEmpty ? card.content : prose;
    _characters.add(WizardCharacterItem(
      id: card.id,
      name: name,
      background: background,
      isProtagonist: isFirst,
      narrativeRole: isFirst
          ? AdventureCharacterRole.protagonist
          : AdventureCharacterRole.companion,
      rawJson: <String, dynamic>{
        'data': <String, dynamic>{
          'name': name,
          'description': background,
        },
      },
    ));
    _syncRelationships();
  }

  /// 获取关联角色的简短显示名称
  String _getAssociatedCharacterShortName(String id) {
    final c = _characters.where((char) => char.id == id).firstOrNull;
    if (c != null) return c.name;
    final card = _characterCardEntries.where((e) => e.id == id).firstOrNull;
    if (card != null) return card.name;
    return id;
  }

  /// 将关联角色 id 转为结构化生成上下文。
  ///
  /// roster 里的角色是会话内的当前值，优先使用；尚未加入队伍但已从资料库选中
  /// 的角色回退到角色卡数据。relation 是用户为*新*角色选择的羁绊，会复制到
  /// 每个关联项，裁剪由 service 的 budgeter 负责。
  List<Map<String, String>> _buildAssociatedCharacterContext(String relation) {
    final context = <Map<String, String>>[];
    for (final id in _aiAssociatedCharacterIds) {
      final character = _characters.where((c) => c.id == id).firstOrNull;
      if (character != null) {
        context.add(<String, String>{
          'name': character.name,
          'profession': character.profession,
          'personality': character.personality,
          'background': character.background,
          'relation': relation,
        });
        continue;
      }
      final card = _characterCardEntries.where((e) => e.id == id).firstOrNull;
      if (card == null) continue;
      context.add(<String, String>{
        ...card.toAssociatedMap(),
        'relation': relation,
      });
    }
    return context;
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
