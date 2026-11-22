part of 'adventure_wizard_screen.dart';

extension _WizardLibrarySync on _AdventureWizardScreenState {
  Future<bool> _saveCurrentWorldviewToLibrary({bool silent = false}) async {
    final l10n = _l10n(context);
    final wvName = _worldviewNameCtrl.text.trim();
    if (wvName.isEmpty) {
      if (!silent) {
        AppFeedback.info(context, l10n.pleaseEnterWorldName);
      }
      return false;
    }
    final wvDesc = _worldviewDescCtrl.text.trim();
    if (mounted) _rebuild(() => _savingWorldview = true);

    try {
      final crud = ref.read(resourceCrudControllerProvider);
      final activeWvId = _getOrCreateActiveWorldviewId();

      // A generated/selected setting card is already the durable authority.
      // Writing it again through the legacy preset path would create a mirror
      // card (res_legacy_*) next to the original. Update only the editable
      // title/summary on the card and keep its body.
      final settingCards = ref.read(settingCardServiceProvider);
      final existingCard = await settingCards.find(activeWvId);
      if (existingCard != null) {
        await settingCards.save(
          id: existingCard.id,
          name: wvName,
          summary: wvDesc,
          content: existingCard.content,
        );
        await _loadData();
        if (mounted) {
          _rebuild(() {
            _selectedWorldviewId = existingCard.id;
            _savingWorldview = false;
          });
          if (!silent) {
            AppFeedback.success(context, l10n.worldviewSavedSuccess(wvName));
          }
        }
        return true;
      }

      final existingWv = _worldviews
          .where((w) => w['id']?.toString() == activeWvId)
          .firstOrNull;
      final detailJson = existingWv?['detail_json'] as String? ?? '{}';

      await crud.saveWorldviewPreset(
        id: activeWvId,
        name: wvName,
        description: wvDesc,
        entriesJson: '[]',
        now: DateTime.now().toIso8601String(),
        detailJson: detailJson,
        source: '冒险向导',
        mode: ResourceLibraryMode.adventure,
        validate: false,
      );

      await _loadData();

      if (mounted) {
        _rebuild(() {
          _selectedWorldviewId = activeWvId;
          _savingWorldview = false;
        });
        if (!silent) {
          AppFeedback.success(context, l10n.worldviewSavedSuccess(wvName));
        }
      }
      return true;
    } catch (e) {
      if (mounted) {
        _rebuild(() => _savingWorldview = false);
        if (!silent) {
          AppFeedback.error(
              context,
              l10n.saveFailedPrefix(
                  localizeAppError(l10n, asAppDomainError(e))));
        }
      }
      return false;
    }
  }

  /// 手动将当前设计的角色保存至资料库
  Future<bool> _saveCurrentCharactersToLibrary({bool silent = false}) async {
    final l10n = _l10n(context);
    if (_characters.isEmpty) {
      if (!silent && mounted) {
        AppFeedback.info(context, l10n.pleaseAddAtLeastOneCharacter);
      }
      return false;
    }

    _rebuild(() => _savingCharacters = true);
    try {
      final repo = ref.read(resourceCrudControllerProvider);
      final activeWv = _getActiveWorldviewItem();
      final activeWvId = (activeWv['id'] as String?) ?? '';

      for (final c in _characters) {
        final cardMap = c.rawJson ??
            {
              'name': c.name,
              'gender': c.gender,
              'age': c.age,
              'profession': c.profession,
              'personality': c.personality,
              'description': c.background,
            };

        final matchingWvId =
            (c.libraryEntry?.matchingWorldviewId?.isNotEmpty == true)
                ? c.libraryEntry!.matchingWorldviewId!
                : activeWvId;

        // Card-backed roster entries already live in setting_cards; saving
        // them as a legacy row would create a second mirror card. Only the
        // legacy-only entries need the old write path.
        final settingCards = ref.read(settingCardServiceProvider);
        if (await settingCards.find(c.id) != null) continue;
        await repo.saveCharacterCard(
          id: c.id,
          name: c.name,
          jsonData: jsonEncode(cardMap),
          source: '冒险向导',
          now: DateTime.now().toIso8601String(),
          matchingWorldviewId: matchingWvId,
          weight: '',
          mode: ResourceLibraryMode.adventure,
        );
      }

      await _loadData();
      ref.read(libraryProvider).loadCharacterCards();

      if (mounted) {
        _rebuild(() => _savingCharacters = false);
        if (!silent) {
          AppFeedback.success(
            context,
            l10n.charactersSavedCount(_characters.length),
          );
        }
      }
      return true;
    } catch (e) {
      if (mounted) {
        _rebuild(() => _savingCharacters = false);
        if (!silent) {
          AppFeedback.error(
              context,
              l10n.characterCardSaveFailed(
                  localizeAppError(l10n, asAppDomainError(e))));
        }
      }
      return false;
    }
  }

  /// 保存单个角色到资料库
  Future<void> _saveSingleCharacterToLibrary(
      WizardCharacterItem character) async {
    final l10n = _l10n(context);
    try {
      final repo = ref.read(resourceCrudControllerProvider);
      final activeWv = _getActiveWorldviewItem();
      final activeWvId = (activeWv['id'] as String?) ?? '';

      final cardMap = character.rawJson ??
          {
            'name': character.name,
            'gender': character.gender,
            'age': character.age,
            'profession': character.profession,
            'personality': character.personality,
            'description': character.background,
          };

      final matchingWvId =
          (character.libraryEntry?.matchingWorldviewId?.isNotEmpty == true)
              ? character.libraryEntry!.matchingWorldviewId!
              : activeWvId;

      // Card-backed characters are already persisted; a legacy write would
      // duplicate them as mirror rows.
      if (await ref.read(settingCardServiceProvider).find(character.id) ==
          null) {
        await repo.saveCharacterCard(
          id: character.id,
          name: character.name,
          jsonData: jsonEncode(cardMap),
          source: '冒险向导',
          now: DateTime.now().toIso8601String(),
          matchingWorldviewId: matchingWvId,
          weight: '',
          mode: ResourceLibraryMode.adventure,
        );
      }

      await _loadData();
      ref.read(libraryProvider).loadCharacterCards();

      if (mounted) {
        AppFeedback.success(
          context,
          l10n.characterCardSavedSuccess(character.name),
        );
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.error(
            context,
            l10n.characterCardSaveFailed(
                localizeAppError(l10n, asAppDomainError(e))));
      }
    }
  }

  /// 打开全屏世界观选择页面 (R02-C)
  Future<void> _savePreview() async {
    if (_savingPreview) return;
    final l10n = _l10n(context);
    if (_characters.isEmpty) {
      AppFeedback.info(context, l10n.pleaseAddAtLeastOneCharacter);
      return;
    }
    _rebuild(() => _savingPreview = true);
    try {
      final wvName = _worldviewNameCtrl.text.trim().isNotEmpty
          ? _worldviewNameCtrl.text.trim()
          : l10n.unnamedWorldview;
      final wvDesc = _worldviewDescCtrl.text.trim();
      final config = _composeAdventureConfig(worldview: wvName);
      final outcome = await AdventurePreviewSaver.save(
        ref: ref,
        config: config,
        l10n: l10n,
        worldviewName: wvName,
        worldviewDesc: wvDesc,
        idPrefix: 'wizard_preview',
      );
      if (!mounted) return;
      if (outcome == AdventurePreviewSaveOutcome.saved) {
        AppFeedback.success(
          context,
          l10n.adventurePreviewSavedMessage(l10n.adventurePreviewName(wvName)),
        );
      } else {
        AppFeedback.info(context, l10n.adventurePreviewExistsMessage);
      }
    } catch (e) {
      debugPrint('Adventure preview save failed: $e');
      if (mounted) {
        AppFeedback.error(
          context,
          l10n.adventurePreviewSaveFailed(
              localizeAppError(l10n, asAppDomainError(e))),
        );
      }
    } finally {
      if (mounted) _rebuild(() => _savingPreview = false);
    }
  }
}
