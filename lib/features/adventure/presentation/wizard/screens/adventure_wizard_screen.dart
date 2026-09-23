import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/feedback/app_feedback.dart';
import '../../../../../core/config/generation_limits.dart';
import '../../../../../core/responsive/responsive.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/worldview_character_scope_policy.dart';
import '../../../../../core/widgets/app_card.dart';
import '../../../../../core/widgets/app_dropdown.dart';
import '../../../../../core/widgets/app_text_field.dart';
import '../../../../../models/adventure_config.dart';
import '../../../../../models/character_card.dart';
import '../../../../../models/character_card_entry.dart';
import '../../../../../models/custom_attribute_item.dart';
import '../../../../../models/resource_library_mode.dart';
import '../../../../../models/resource_provenance.dart';
import '../../../../../models/supporting_character.dart';
import '../../../../../models/worldview_details.dart';
import '../../../../../models/worldview_preset.dart';
import '../../../../../application/adventure/adventure_readiness_gate.dart';
import '../../../../../application/resources/resource_creation_contracts.dart';
import '../../../../../domain/resources/resource_contracts.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../resource_studio/presentation/pages/resource_studio_page.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../widgets/assembly_readiness_dialogs.dart';
import '../../../../../screens/resource_library/character_card_tab.dart';
import '../../../../../screens/resource_library/scene_batch_import_page.dart';
import '../../../../../screens/resource_library/worldview_tab.dart';
import '../../../../../services/worldview_snapshot_service.dart';
import '../../../../../widgets/app_dialogs.dart';
import '../../../../../core/router/app_router.dart';
import '../models/wizard_character_item.dart';
import '../widgets/assembly_opening_ai.dart';
import 'assembly_config_page.dart';
import 'assembly_preview_page.dart';
import 'character_selection_page.dart';
import 'npc_selection_page.dart';
import 'world_selection_page.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

String _localizedAdventureRole(String value, AppLocalizations l10n) =>
    switch (value) {
      AdventureCharacterRole.protagonist => l10n.mainProtagonistTitle,
      AdventureCharacterRole.maleLead => l10n.roleMaleLead,
      AdventureCharacterRole.femaleLead => l10n.roleFemaleLead,
      AdventureCharacterRole.maleOne => l10n.roleMaleOne,
      AdventureCharacterRole.femaleOne => l10n.roleFemaleOne,
      AdventureCharacterRole.maleTwo => l10n.roleMaleTwo,
      AdventureCharacterRole.femaleTwo => l10n.roleFemaleTwo,
      AdventureCharacterRole.supporting => l10n.roleSupporting,
      AdventureCharacterRole.companion => l10n.relationCompanion,
      AdventureCharacterRole.villain => l10n.roleVillain,
      AdventureCharacterRole.mentor => l10n.roleMentor,
      AdventureCharacterRole.family => l10n.roleFamily,
      _ => value,
    };

String _localizedAdventureRelation(String value, AppLocalizations l10n) =>
    switch (value) {
      AdventureRelationType.unset => l10n.notSpecifiedOption,
      AdventureRelationType.friend => l10n.relationFriend,
      AdventureRelationType.family => l10n.relationKin,
      AdventureRelationType.enemy => l10n.relationEnemy,
      AdventureRelationType.companion => l10n.relationCompanion,
      AdventureRelationType.lover => l10n.relationLover,
      AdventureRelationType.mentor => l10n.relationMentor,
      AdventureRelationType.rival => l10n.relationRival,
      AdventureRelationType.employer => l10n.relationEmployment,
      AdventureRelationType.stranger => l10n.relationStranger,
      AdventureRelationType.custom => l10n.relationCustom,
      _ => value,
    };

/// 现代化流式场景创建向导 (Adventure Wizard)
/// 全面联动资料库：支持世界观快照绑定、多角色选择与身份赋予 (男主/女主/同伴等)、角色间羁绊关系网设定
class AdventureWizardScreen extends ConsumerStatefulWidget {
  final Future<void> Function(AdventureConfig config) onStartAdventure;
  final AdventureConfig? initialConfig;
  final String? initialWorldviewId;
  final String? initialCharacterId;
  final int reloadTrigger;

  /// Worldview description restored from a saved preview template.  The
  /// worldview name travels through [initialConfig].worldview.
  final String? initialWorldviewDesc;

  const AdventureWizardScreen({
    super.key,
    required this.onStartAdventure,
    this.initialConfig,
    this.initialWorldviewId,
    this.initialCharacterId,
    this.reloadTrigger = 0,
    this.initialWorldviewDesc,
  });

  @override
  ConsumerState<AdventureWizardScreen> createState() =>
      _AdventureWizardScreenState();
}

class _AdventureWizardScreenState extends ConsumerState<AdventureWizardScreen> {
  int _currentStep = 0;
  bool _loading = true;
  bool _submitting = false;
  bool _savingPreview = false;

  List<Map<String, dynamic>> _worldviews = [];
  List<CharacterCardEntry> _characterCardEntries = [];
  List<Map<String, dynamic>> _npcCards = [];
  final Set<String> _selectedNpcIds = {};

  // Per-asset-type load failures. They are kept apart from the loaded lists so
  // one broken resource can still be reported while the others stay usable.
  String? _worldviewLoadError;
  String? _characterLoadError;
  String? _npcLoadError;
  int _malformedCharacterCardCount = 0;

  // Step 1: 世界观
  String? _selectedWorldviewId;
  late final TextEditingController _worldviewNameCtrl;
  late final TextEditingController _worldviewDescCtrl;
  late final TextEditingController _aiWorldviewPromptCtrl;
  final bool _aiWorldviewGenerating = false;
  String? _aiWorldviewError;
  bool _aiWorldviewDetailed = false;
  String? _aiWorldviewProgress;
  bool _saveWorldviewToLibrary = true;
  bool _savingWorldview = false;

  // Step 2: 角色设计 (多角色选择、身份赋予、关系网络)
  final List<WizardCharacterItem> _characters = [];
  final List<WizardRelationshipItem> _relationships = [];
  late final TextEditingController _aiCharacterPromptCtrl;
  final bool _aiCharacterGenerating = false;
  String? _aiCharacterError;
  bool _aiCharacterDetailed = false;
  String? _aiCharacterProgress;
  bool _saveCharactersToLibrary = true;
  bool _savingCharacters = false;

  // AI 角色生成时关联已有角色设定
  final Set<String> _aiAssociatedCharacterIds = {};
  String _aiRelationType = '同伴';
  late final TextEditingController _aiCustomRelationCtrl;
  bool _aiAssociationInitialized = false;

  // Step 3: 开场剧情与行动分支
  late final TextEditingController _openingSceneCtrl;
  late final TextEditingController _option1Ctrl;
  late final TextEditingController _option2Ctrl;
  late final TextEditingController _option3Ctrl;
  late final TextEditingController _aiPromptCtrl;
  bool _aiGenerating = false;
  String? _aiGenError;

  @override
  void initState() {
    super.initState();
    final cfg = widget.initialConfig;

    _worldviewNameCtrl = TextEditingController(text: cfg?.worldview ?? '');
    _worldviewDescCtrl =
        TextEditingController(text: widget.initialWorldviewDesc ?? '');
    _aiWorldviewPromptCtrl = TextEditingController();
    _aiCharacterPromptCtrl = TextEditingController();
    _aiCustomRelationCtrl = TextEditingController();

    final openingOptions = cfg?.openingOptions ?? const <String>[];
    _openingSceneCtrl = TextEditingController(text: cfg?.openingScene ?? '');
    _option1Ctrl = TextEditingController(
        text: openingOptions.isNotEmpty ? openingOptions[0] : '');
    _option2Ctrl = TextEditingController(
        text: openingOptions.length > 1 ? openingOptions[1] : '');
    _option3Ctrl = TextEditingController(
        text: openingOptions.length > 2 ? openingOptions[2] : '');
    _aiPromptCtrl = TextEditingController();

    // 从初始配置中恢复角色与关系 (若有)
    if (cfg != null) {
      _selectedNpcIds.addAll(cfg.npcSnapshots.map((npc) => npc.assetId));
      if (cfg.selectedCharacters.isNotEmpty) {
        for (final sc in cfg.selectedCharacters) {
          final card = sc.characterCardJson ?? const <String, dynamic>{};
          _characters.add(WizardCharacterItem(
            id: sc.characterId,
            name: sc.characterName.isNotEmpty
                ? sc.characterName
                : (card['name']?.toString() ?? ''),
            gender: card['gender']?.toString() ?? '',
            age: card['age']?.toString() ?? '',
            profession:
                (card['profession'] ?? card['occupation'] ?? card['role'])
                        ?.toString() ??
                    '',
            personality: card['personality']?.toString() ?? '',
            background:
                (card['description'] ?? card['background'])?.toString() ?? '',
            isProtagonist: sc.isProtagonist,
            narrativeRole: sc.narrativeRole,
            customRoleName: sc.customRoleName,
            rawJson: sc.characterCardJson,
          ));
        }
      } else if (cfg.name.isNotEmpty) {
        _characters.add(WizardCharacterItem(
          id: 'protagonist',
          name: cfg.name,
          gender: cfg.gender,
          age: cfg.age,
          profession: cfg.protagonistClass,
          personality: cfg.personality,
          background: cfg.protagonistBackground,
          isProtagonist: true,
          narrativeRole: AdventureCharacterRole.protagonist,
        ));
      }

      if (cfg.characterRelationships.isNotEmpty) {
        for (final rel in cfg.characterRelationships) {
          _relationships.add(WizardRelationshipItem(
            id: rel.id,
            sourceCharacterId: rel.sourceCharacterId,
            targetCharacterId: rel.targetCharacterId,
            relationType: rel.relationType,
            customRelationName: rel.customRelationName,
            description: rel.description,
          ));
        }
      }

      if (cfg.supportingCharacters.isNotEmpty) {
        for (final sc in cfg.supportingCharacters) {
          final id = sc.id.isNotEmpty ? sc.id : sc.name;
          // NPC assets are restored through _selectedNpcIds, not as characters.
          if (_selectedNpcIds.contains(id)) continue;
          if (!_characters.any((c) => c.id == id || c.name == sc.name)) {
            _characters.add(WizardCharacterItem(
              id: id,
              name: sc.name,
              gender: sc.gender,
              profession: sc.role,
              personality: sc.personality,
              isProtagonist: false,
              narrativeRole: AdventureCharacterRole.supporting,
            ));
          }
        }
      }
    }

    _syncRelationships();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _worldviewNameCtrl.dispose();
    _worldviewDescCtrl.dispose();
    _aiWorldviewPromptCtrl.dispose();
    _aiCharacterPromptCtrl.dispose();
    _aiCustomRelationCtrl.dispose();
    _openingSceneCtrl.dispose();
    _option1Ctrl.dispose();
    _option2Ctrl.dispose();
    _option3Ctrl.dispose();
    _aiPromptCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    // One failing asset type must never be swallowed together with the rest:
    // the controller reports every type independently and this method carries
    // each error through to its own empty/error banner.
    try {
      final setupController = ref.read(adventureSetupControllerProvider);
      await setupController.loadInitialData();
      final wvList = setupController.worldviewPresets;
      final cardEntries = setupController.characterCardEntries;
      final npcCards = setupController.npcCards;
      final wvError = setupController.worldviewError;
      final charError = setupController.characterError;
      final npcError = setupController.npcError;
      final malformed = setupController.malformedCharacterCardCount;

      if (mounted) {
        setState(() {
          _worldviews = wvList;
          _characterCardEntries = cardEntries;
          _npcCards = npcCards;
          _worldviewLoadError = wvError;
          _characterLoadError = charError;
          _npcLoadError = npcError;
          _malformedCharacterCardCount = malformed;

          // 显式 ID 匹配世界观
          if (widget.initialWorldviewId != null) {
            final matchedWv = _worldviews
                .where(
                  (w) => w['id'] == widget.initialWorldviewId,
                )
                .firstOrNull;
            if (matchedWv != null) {
              _selectedWorldviewId = matchedWv['id'] as String?;
              _worldviewNameCtrl.text = matchedWv['name'] as String? ?? '';
              _worldviewDescCtrl.text =
                  matchedWv['description'] as String? ?? '';
            }
          }

          // 显式 ID 匹配角色卡
          if (widget.initialCharacterId != null) {
            final matchedCard = _characterCardEntries
                .where(
                  (c) => c.id == widget.initialCharacterId,
                )
                .firstOrNull;
            if (matchedCard != null) {
              _bindCharacterFromLibrary(matchedCard, asProtagonist: true);
            }
          }

          _syncRelationships();
          _loading = false;
        });
      }
    } catch (e) {
      // `loadInitialData` already isolates each asset type; reaching here means
      // even the controller itself could not run, so surface one shared banner
      // rather than silently pretending everything loaded.
      if (mounted) {
        setState(() {
          _worldviewLoadError ??= e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Shared empty / error banner for one asset type.
  ///
  /// Uses a `Row` + `Expanded` text so long error messages wrap instead of
  /// overflowing at the 320 px minimum width.
  Widget _resourceBanner(
    BuildContext context, {
    required IconData icon,
    required String message,
    required bool isError,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: isError
            ? scheme.errorContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: isError ? scheme.error : scheme.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// 将角色卡从资料库选入或设为主控主角
  void _bindCharacterFromLibrary(CharacterCardEntry card,
      {bool asProtagonist = false}) {
    final existingIndex = _characters.indexWhere((c) => c.id == card.id);
    if (existingIndex >= 0) {
      if (asProtagonist) {
        _setProtagonist(card.id);
      }
      return;
    }

    final isFirst = _characters.isEmpty || asProtagonist;
    if (isFirst) {
      for (final c in _characters) {
        c.isProtagonist = false;
        if (c.narrativeRole == AdventureCharacterRole.protagonist) {
          c.narrativeRole = AdventureCharacterRole.companion;
        }
      }
    }

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

    _syncRelationships();
  }

  /// 切换资料库角色的加入/移除
  void _toggleLibraryCard(CharacterCardEntry card) {
    setState(() {
      final existingIndex = _characters.indexWhere((c) => c.id == card.id);
      if (existingIndex >= 0) {
        final wasProtagonist = _characters[existingIndex].isProtagonist;
        _characters.removeAt(existingIndex);
        if (wasProtagonist && _characters.isNotEmpty) {
          _characters.first.isProtagonist = true;
          _characters.first.narrativeRole = AdventureCharacterRole.protagonist;
        }
      } else {
        _bindCharacterFromLibrary(card);
      }
      _syncRelationships();
    });
  }

  /// 设为主角 (唯一主控主角)
  void _setProtagonist(String id) {
    setState(() {
      for (final c in _characters) {
        if (c.id == id) {
          c.isProtagonist = true;
          c.narrativeRole = AdventureCharacterRole.protagonist;
        } else if (c.isProtagonist) {
          c.isProtagonist = false;
          c.narrativeRole = AdventureCharacterRole.companion;
        }
      }
      _syncRelationships();
    });
  }

  /// 移除已选角色
  void _removeCharacter(String id) {
    setState(() {
      final wasProtagonist =
          _characters.where((c) => c.id == id).any((c) => c.isProtagonist);
      _characters.removeWhere((c) => c.id == id);
      _aiAssociatedCharacterIds.remove(id);
      if (wasProtagonist && _characters.isNotEmpty) {
        _characters.first.isProtagonist = true;
        _characters.first.narrativeRole = AdventureCharacterRole.protagonist;
      }
      _syncRelationships();
    });
  }

  /// 自动同步所有角色之间的两两关系对
  void _syncRelationships() {
    final ids = _characters.map((c) => c.id).toList();
    _relationships.removeWhere((r) =>
        !ids.contains(r.sourceCharacterId) ||
        !ids.contains(r.targetCharacterId));

    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final stableId =
            AdventureCharacterRelationship.stableId(ids[i], ids[j]);
        if (_relationships.any((r) => r.id == stableId)) continue;

        _relationships.add(
          WizardRelationshipItem(
            id: stableId,
            sourceCharacterId: ids[i],
            targetCharacterId: ids[j],
            relationType: AdventureRelationType.unset,
            assetSuggestion: _assetRelationshipSuggestion(
              _characters.firstWhere((character) => character.id == ids[i]),
              _characters.firstWhere((character) => character.id == ids[j]),
            ),
          ),
        );
      }
    }
  }

  String _assetRelationshipSuggestion(
    WizardCharacterItem source,
    WizardCharacterItem target,
  ) {
    String findIn(WizardCharacterItem owner, WizardCharacterItem other) {
      final raw = owner.rawJson;
      if (raw == null) return '';
      final data = raw['data'] is Map
          ? Map<String, dynamic>.from(raw['data'] as Map)
          : raw;
      final links = data['relationship_links'];
      if (links is List) {
        for (final value in links.whereType<Map>()) {
          final link = Map<String, dynamic>.from(value);
          final matchesId = link['targetResourceId']?.toString() == other.id;
          final matchesName = link['targetName']?.toString() == other.name;
          if (!matchesId && !matchesName) continue;
          return [link['relationType'], link['description']]
              .map((part) => part?.toString().trim() ?? '')
              .where((part) => part.isNotEmpty)
              .join('：');
        }
      }
      final profile = data['world_profile'];
      if (profile is Map) {
        final notes = profile['relationship_notes']?.toString().trim() ?? '';
        if (notes.contains(other.name)) return notes;
      }
      return '';
    }

    final direct = findIn(source, target);
    return direct.isNotEmpty ? direct : findIn(target, source);
  }

  /// 获取或生成当前向导中生效的世界观 ID
  String _getOrCreateActiveWorldviewId() {
    if (_selectedWorldviewId != null && _selectedWorldviewId!.isNotEmpty) {
      return _selectedWorldviewId!;
    }
    final newId = 'wv_wizard_${DateTime.now().millisecondsSinceEpoch}';
    _selectedWorldviewId = newId;
    return newId;
  }

  /// 获取当前向导中活跃的世界观设定项（包含用户填写的名称与法则描述）
  Map<String, dynamic> _getActiveWorldviewItem() {
    final id = _getOrCreateActiveWorldviewId();
    final name = _worldviewNameCtrl.text.trim().isNotEmpty
        ? _worldviewNameCtrl.text.trim()
        : '当前世界观';
    final desc = _worldviewDescCtrl.text.trim();
    final existing =
        _worldviews.where((w) => w['id']?.toString() == id).firstOrNull;
    if (existing != null) {
      return {
        ...existing,
        'name': name,
        'description': desc,
      };
    }
    return {
      'id': id,
      'name': name,
      'description': desc,
      'detail_json': '{}',
    };
  }

  /// 构造包含当前活跃世界观的高优先级世界观列表，确保角色设计与 AI 创作第一时间自动关联
  List<Map<String, dynamic>> _buildEffectiveWorldviews() {
    final activeItem = _getActiveWorldviewItem();
    final list = <Map<String, dynamic>>[activeItem];
    for (final w in _worldviews) {
      if (w['id']?.toString() != activeItem['id']?.toString()) {
        list.add(w);
      }
    }
    return list;
  }

  /// 手动或自动将当前编辑的世界观设定保存至资料库
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
    if (mounted) setState(() => _savingWorldview = true);

    try {
      final crud = ref.read(resourceCrudControllerProvider);
      final activeWvId = _getOrCreateActiveWorldviewId();

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
        setState(() {
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
        setState(() => _savingWorldview = false);
        if (!silent) {
          AppFeedback.error(context, l10n.saveFailedPrefix(e.toString()));
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

    setState(() => _savingCharacters = true);
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
        setState(() => _savingCharacters = false);
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
        setState(() => _savingCharacters = false);
        if (!silent) {
          AppFeedback.error(
              context, l10n.characterCardSaveFailed(e.toString()));
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
        AppFeedback.error(context, l10n.characterCardSaveFailed(e.toString()));
      }
    }
  }

  /// 打开全屏世界观选择页面 (R02-C)
  Future<void> _openWorldSelectionPage() async {
    final l10n = _l10n(context);
    final selected = await AppRouter.push<Map<String, dynamic>?>(
      context,
      pageBuilder: (_) => WorldSelectionPage(
        initialSelectedId: _selectedWorldviewId,
      ),
    );
    if (selected != null && mounted) {
      setState(() {
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
      setState(() {
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
      setState(() {
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
      setState(() {
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

      setState(() {
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
        setState(() {
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
          setState(() {
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

  /// 构建 AI 角色生成卡中的关联已有角色设定区
  Widget _buildAiCharacterAssociationSection(
    ColorScheme scheme,
    ThemeData theme,
  ) {
    final l10n = _l10n(context);
    final options = _buildAiAssociatedOptions();
    if (options.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: _aiAssociatedCharacterIds.isNotEmpty
              ? scheme.primary.withValues(alpha: 0.35)
              : scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.hub_outlined,
                size: 16,
                color: _aiAssociatedCharacterIds.isNotEmpty
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              // The title flexes instead of forcing the hint text off-screen on
              // narrow phones: both texts wrap/ellipsize inside one Row.
              Flexible(
                child: Text(
                  l10n.characterCardRelateCharacterOptional,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _aiAssociatedCharacterIds.isNotEmpty
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
              if (_aiAssociatedCharacterIds.isNotEmpty)
                InkWell(
                  onTap: _aiCharacterGenerating
                      ? null
                      : () => setState(() => _aiAssociatedCharacterIds.clear()),
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
            values: _aiAssociatedCharacterIds,
            label: l10n.selectRelatedCharacters,
            hintText: l10n.characterCardRelateCharacterHint,
            emptyText: l10n.characterCardNoOtherCharacters,
            options: options,
            direction: AppDropdownDirection.down,
            triggerHeight: 38,
            triggerPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            selectedBuilder: (values) {
              if (values.isEmpty) return l10n.characterCardIndependentRole;
              final names = values
                  .map((id) => _getAssociatedCharacterShortName(id))
                  .toList();
              return l10n.wizardRelatedCharactersSummary(
                values.length,
                names.join(', '),
              );
            },
            onChanged: _aiCharacterGenerating
                ? null
                : (newVals) {
                    setState(() {
                      _aiAssociatedCharacterIds
                        ..clear()
                        ..addAll(newVals);
                    });
                  },
          ),
          if (_aiAssociatedCharacterIds.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs + 2),
            Row(
              children: [
                Text(
                  l10n.characterCardBondRelation,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                AppDropdown<String>.compact(
                  value: _aiRelationType,
                  direction: AppDropdownDirection.down,
                  options: [
                    AppDropdownOption(
                      value: '同伴',
                      label: l10n.relationCompanion,
                    ),
                    AppDropdownOption(
                      value: '青梅竹马',
                      label: l10n.relationChildhoodFriend,
                    ),
                    AppDropdownOption(
                      value: '恋人',
                      label: l10n.relationLover,
                    ),
                    AppDropdownOption(value: '师徒', label: l10n.relationMentor),
                    AppDropdownOption(value: '宿敌', label: l10n.relationRival),
                    AppDropdownOption(value: '亲人', label: l10n.relationKin),
                    AppDropdownOption(
                      value: '救命恩人',
                      label: l10n.relationBenefactor,
                    ),
                    AppDropdownOption(
                      value: '雇佣关系',
                      label: l10n.relationEmployment,
                    ),
                    AppDropdownOption(value: '自定义', label: l10n.relationCustom),
                  ],
                  onChanged: _aiCharacterGenerating
                      ? null
                      : (val) {
                          if (val != null) {
                            setState(() => _aiRelationType = val);
                          }
                        },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <String, String>{
                        '同伴': l10n.relationCompanion,
                        '青梅竹马': l10n.relationChildhoodFriend,
                        '恋人': l10n.relationLover,
                        '师徒': l10n.relationMentor,
                        '宿敌': l10n.relationRival,
                        '救命恩人': l10n.relationBenefactor,
                      }.entries.map((entry) {
                        final preset = entry.key;
                        final isSel = _aiRelationType == preset;
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: ChoiceChip(
                            label: Text(
                              entry.value,
                              style: const TextStyle(fontSize: 11),
                            ),
                            selected: isSel,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onSelected: _aiCharacterGenerating
                                ? null
                                : (selected) {
                                    if (selected) {
                                      setState(() => _aiRelationType = preset);
                                    }
                                  },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
            if (_aiRelationType == '自定义') ...[
              const SizedBox(height: 6),
              SizedBox(
                height: 34,
                child: TextField(
                  controller: _aiCustomRelationCtrl,
                  enabled: !_aiCharacterGenerating,
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
          setState(() {
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

    setState(() {
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
        setState(() {
          _aiGenerating = false;
          _aiGenError = ref.read(adventureAiControllerProvider).errorMessage ??
              l10n.aiGenerationNoValidContent;
        });
        return;
      }

      setState(() {
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
      setState(() {
        _aiGenerating = false;
        _aiGenError = l10n.aiGenerationFailed(e.toString());
      });
    }
  }

  WizardCharacterItem get _protagonistItem {
    final protagonist = _characters.where((c) => c.isProtagonist).firstOrNull;
    if (protagonist != null) return protagonist;
    if (_characters.isNotEmpty) return _characters.first;
    return WizardCharacterItem(id: 'protagonist', name: '冒险者');
  }

  List<AdventureSelectedCharacter> _composeSelectedCharacters() {
    final result = <AdventureSelectedCharacter>[];
    for (var i = 0; i < _characters.length; i++) {
      final c = _characters[i];
      final cardJson = Map<String, dynamic>.from(c.rawJson ??
          {
            'name': c.name,
            'gender': c.gender,
            'age': c.age,
            'profession': c.profession,
            'personality': c.personality,
            'description': c.background,
          });
      if ((c.libraryEntry?.customAttributes.isNotEmpty ?? false) &&
          cardJson['custom_attributes'] == null &&
          cardJson['customAttributes'] == null) {
        cardJson['custom_attributes'] =
            c.libraryEntry!.customAttributes.map((a) => a.toJson()).toList();
      }
      result.add(AdventureSelectedCharacter(
        id: c.id,
        characterId: c.id,
        characterName: c.name,
        isProtagonist: c.isProtagonist,
        narrativeRole: c.narrativeRole,
        customRoleName: c.customRoleName,
        sortOrder: c.isProtagonist ? 0 : i + 1,
        characterCardJson: cardJson,
      ));
    }
    return result;
  }

  List<AdventureCharacterRelationship> _composeRelationships() => _relationships
      .map((r) => AdventureCharacterRelationship(
            id: r.id,
            sourceCharacterId: r.sourceCharacterId,
            targetCharacterId: r.targetCharacterId,
            relationType: r.relationType,
            customRelationName: r.customRelationName,
            description: r.description,
          ))
      .toList();

  List<SupportingCharacter> _composeSupportingCharacters(
      WizardCharacterItem protagonist) {
    final result = <SupportingCharacter>[];
    for (final c in _characters) {
      if (c.isProtagonist) continue;
      final rel = _relationships
          .where((r) =>
              (r.sourceCharacterId == protagonist.id &&
                  r.targetCharacterId == c.id) ||
              (r.sourceCharacterId == c.id &&
                  r.targetCharacterId == protagonist.id))
          .firstOrNull;

      final rawAttrs = c.libraryEntry?.customAttributes;
      final listAttrs = (rawAttrs != null && rawAttrs.isNotEmpty)
          ? rawAttrs
          : (c.rawJson != null &&
                  (c.rawJson!['custom_attributes'] is List ||
                      c.rawJson!['customAttributes'] is List))
              ? ((c.rawJson!['custom_attributes'] ??
                      c.rawJson!['customAttributes']) as List)
                  .map((item) => CustomAttributeItem.fromJson(
                      Map<String, dynamic>.from(item as Map)))
                  .toList()
              : <CustomAttributeItem>[];

      result.add(
        SupportingCharacter(
          id: c.id,
          name: c.name,
          gender: c.gender,
          role: c.profession.isNotEmpty ? c.profession : c.effectiveRole,
          relation: rel != null &&
                  AdventureRelationType.normalize(rel.relationType) !=
                      AdventureRelationType.unset
              ? rel.effectiveRelation
              : '',
          personality: c.personality,
          customAttributes: listAttrs,
        ),
      );
    }
    return result;
  }

  Map<String, dynamic> _npcJsonOf(Map<String, dynamic> row) {
    try {
      final decoded = jsonDecode(row['json_data']?.toString() ?? '{}');
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return <String, dynamic>{};
  }

  Iterable<Map<String, dynamic>> get _selectedNpcRows =>
      _npcCards.where((npc) => _selectedNpcIds.contains(npc['id']?.toString()));

  List<AdventureNpcSnapshot> _composeNpcSnapshots() => _selectedNpcRows
      .map((row) => AdventureNpcSnapshot(
            assetId: row['id']?.toString() ?? '',
            name: row['name']?.toString() ?? '未命名 NPC',
            originWorldviewId: row['matching_worldview_id']?.toString() ?? '',
            npcJson: _npcJsonOf(row),
          ))
      .toList();

  List<SupportingCharacter> _supportingWithNpcs(
      List<SupportingCharacter> supporting) {
    final result = List<SupportingCharacter>.from(supporting);
    for (final row in _selectedNpcRows) {
      final assetId = row['id']?.toString() ?? '';
      final name = row['name']?.toString() ?? '未命名 NPC';
      final npcJson = _npcJsonOf(row);
      result.add(SupportingCharacter.fromJson({
        ...npcJson,
        'id': assetId,
        'name': name,
        'relation': npcJson['relation']?.toString() ?? '',
      }));
    }
    return result;
  }

  AdventureConfig _composeAdventureConfig({
    required String worldview,
    Map<String, dynamic>? worldviewSnapshot,
  }) {
    final protagonist = _protagonistItem;
    final openingOpts = [
      _option1Ctrl.text.trim(),
      _option2Ctrl.text.trim(),
      _option3Ctrl.text.trim(),
    ].where((opt) => opt.isNotEmpty).toList();
    return AdventureConfig(
      worldview: worldview,
      worldviewSnapshot: worldviewSnapshot,
      name: protagonist.name,
      gender: protagonist.gender,
      age: protagonist.age,
      protagonistClass:
          protagonist.profession.isNotEmpty ? protagonist.profession : '冒险者',
      personality: protagonist.personality,
      protagonistBackground: protagonist.background,
      characterCard: protagonist.libraryEntry?.card ??
          CharacterCard.fromJson(protagonist.rawJson ??
              {
                'name': protagonist.name,
                'gender': protagonist.gender,
                'age': protagonist.age,
                'profession': protagonist.profession,
                'personality': protagonist.personality,
                'description': protagonist.background,
              }),
      selectedCharacters: _composeSelectedCharacters(),
      characterRelationships: _composeRelationships(),
      supportingCharacters:
          _supportingWithNpcs(_composeSupportingCharacters(protagonist)),
      npcSnapshots: _composeNpcSnapshots(),
      openingScene: _openingSceneCtrl.text.trim().isNotEmpty
          ? _openingSceneCtrl.text.trim()
          : '你在未知的起点苏醒，周围寂静无声。你整理了一下行囊，准备迈出第一步。',
      openingOptions: openingOpts.isNotEmpty
          ? openingOpts
          : ['检查随身携带的装备与地图', '顺着前方道路继续探索', '隐蔽身形，观察四周动静'],
    );
  }

  /// Saves the current wizard state as a recoverable preview template without
  /// starting the adventure.
  Future<void> _savePreview() async {
    if (_savingPreview) return;
    final l10n = _l10n(context);
    if (_characters.isEmpty) {
      AppFeedback.info(context, l10n.pleaseAddAtLeastOneCharacter);
      return;
    }
    setState(() => _savingPreview = true);
    try {
      final wvName = _worldviewNameCtrl.text.trim().isNotEmpty
          ? _worldviewNameCtrl.text.trim()
          : l10n.unnamedWorldview;
      final wvDesc = _worldviewDescCtrl.text.trim();
      final previewName = l10n.adventurePreviewName(wvName);
      final config = _composeAdventureConfig(worldview: wvName);
      final controller = ref.read(adventureTemplateControllerProvider);
      final saved = await controller.saveAdventurePreview(
        id: 'wizard_preview_${DateTime.now().millisecondsSinceEpoch}',
        name: previewName,
        worldviewName: wvName,
        worldviewDesc: wvDesc.isNotEmpty ? wvDesc : wvName,
        config: config,
      );
      if (!mounted) return;
      if (saved) {
        AppFeedback.success(
          context,
          l10n.adventurePreviewSavedMessage(previewName),
        );
      } else {
        AppFeedback.info(context, l10n.adventurePreviewExistsMessage);
      }
    } catch (e) {
      debugPrint('Adventure preview save failed: $e');
      if (mounted) {
        AppFeedback.error(
          context,
          l10n.adventurePreviewSaveFailed(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPreview = false);
    }
  }

  Future<void> _handleStart() async {
    if (_submitting) return;
    final l10n = _l10n(context);

    final chat = ref.read(chatProvider);
    if (!chat.isKeyConfigured) {
      showApiSettings(context);
      return;
    }

    if (_characters.isEmpty) {
      AppFeedback.info(context, l10n.pleaseAddAtLeastOneCharacter);
      return;
    }

    // 确保有且仅有一个主控主角
    if (!_characters.any((c) => c.isProtagonist)) {
      _characters.first.isProtagonist = true;
      _characters.first.narrativeRole = AdventureCharacterRole.protagonist;
    }

    setState(() => _submitting = true);

    // 单一异常边界：世界观/角色的持久化、资源重载、快照构建、
    // custom attribute 解析与配置装配，以及最终的启动回调，全部
    // 纳入同一个 try/catch/finally。任何一步失败都会复位 _submitting
    // 并把错误反馈给用户，避免按钮永久 disabled。
    try {
      final setupController = ref.read(adventureSetupControllerProvider);
      final activeWvId = _getOrCreateActiveWorldviewId();
      final wvName = _worldviewNameCtrl.text.trim().isNotEmpty
          ? _worldviewNameCtrl.text.trim()
          : '未知大陆';
      final wvDesc = _worldviewDescCtrl.text.trim();

      // 1. 自动持久化当前生效的世界观
      final crud = ref.read(resourceCrudControllerProvider);

      final existingWv = _worldviews
          .where((w) => w['id']?.toString() == activeWvId)
          .firstOrNull;
      final detailJson = existingWv?['detail_json'] as String? ?? '{}';

      if (_saveWorldviewToLibrary) {
        final result = await crud.saveWorldviewPreset(
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
        if (!result.success) {
          throw StateError(result.errorMessage ?? '世界观保存失败');
        }
      }

      // 重新加载以确保 setupController 包含最新世界观数据
      await setupController.loadInitialData();

      // 构建世界观快照 (若 setupController 未找到则使用快照服务直接构建完整快照)
      Map<String, dynamic>? worldviewSnapshot =
          setupController.buildWorldviewSnapshot(
        id: activeWvId,
        worldview: wvName,
      );
      if (worldviewSnapshot == null) {
        Map<String, dynamic>? detail;
        if (detailJson.isNotEmpty && detailJson != '{}') {
          try {
            final dec = jsonDecode(detailJson);
            if (dec is Map<String, dynamic>) detail = dec;
          } catch (_) {}
        }
        worldviewSnapshot = WorldviewSnapshotService.snapshot(WorldviewPreset(
          id: activeWvId,
          name: wvName,
          description: wvDesc,
          details:
              WorldviewDetails.fromJson(detail, fallbackDescription: wvDesc),
        ));
      }

      // 2. 根据设置自动将采用的角色保存至资料库，并关联当前世界观
      if (_saveCharactersToLibrary) {
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

          // Same pipeline as every other entry point: the wizard no longer
          // owns a character persistence path of its own.
          final result = await crud.saveCharacterCard(
            id: c.id,
            name: c.name,
            jsonData: jsonEncode(cardMap),
            source: '冒险向导',
            now: DateTime.now().toIso8601String(),
            matchingWorldviewId: matchingWvId,
            mode: ResourceLibraryMode.adventure,
          );
          if (!result.success) {
            throw StateError(result.errorMessage ?? '角色保存失败');
          }
        }
        ref.read(libraryProvider).loadCharacterCards();
      }

      // 3-5. 构建配置（角色、关系、NPC、序章与行动分支）
      var config = _composeAdventureConfig(
        worldview: wvName,
        worldviewSnapshot: worldviewSnapshot,
      );

      // Phase 10: assembly readiness 门禁。被选中的统一资源必须已就绪；
      // 存在旧 ready revision 时由用户明确选择，绝不静默降级。
      final gate = ref.read(adventureReadinessGateProvider);
      final statuses = await gate.resolveConfig(config);
      final blocked = statuses.values
          .where((readiness) => readiness.status.blocksStart)
          .toList(growable: false);
      if (blocked.isNotEmpty) {
        final hardBlocked = blocked
            .where((readiness) =>
                readiness.status !=
                AdventureAssetGateStatus.staleWithPreviousReady)
            .toList(growable: false);
        final staleBlocked = blocked
            .where((readiness) =>
                readiness.status ==
                AdventureAssetGateStatus.staleWithPreviousReady)
            .toList(growable: false);
        if (hardBlocked.isNotEmpty) {
          if (mounted) {
            await showAssemblyReadinessBlockDialog(
              context,
              hardBlocked.map((readiness) => readiness.message).toList(),
            );
          }
          return;
        }
        if (mounted) {
          final usePrevious = await showStaleAssemblyChoiceDialog(
            context,
            staleBlocked.map((readiness) => readiness.message).toList(),
          );
          if (!usePrevious) return;
          config = config.copyWith(
            resourceBindings: [
              ...config.resourceBindings,
              ...staleBlocked.map(
                (readiness) => AdventureResourceBinding(
                  resourceId: readiness.assetId,
                  revisionId: readiness.assemblyRevisionId,
                  contentHash: readiness.assemblyContentHash,
                  staleAllowed: true,
                ),
              ),
            ],
          );
        }
      }

      await widget.onStartAdventure(config);
      if (mounted) {
        final chatAfter = ref.read(chatProvider);
        if (chatAfter.isAdventureChatOpen && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    } catch (e, st) {
      // 保留诊断堆栈以定位是哪一步失败，同时只向用户暴露安全文案。
      debugPrint('Adventure start failed: $e\n$st');
      if (mounted) {
        AppFeedback.error(context, l10n.startAdventureFailed(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final isCompact = size.width < AppBreakpoints.mediumMin ||
        (size.width < 760 && textScale > 1.15);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(l10n.adventureWizardTitle),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: l10n.closeAction,
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Stepper(
            type: isCompact ? StepperType.vertical : StepperType.horizontal,
            currentStep: _currentStep,
            onStepTapped: (step) => setState(() => _currentStep = step),
            onStepContinue: () async {
              final l10n = _l10n(context);
              if (_currentStep == 0) {
                if (_saveWorldviewToLibrary &&
                    _worldviewNameCtrl.text.trim().isNotEmpty) {
                  await _saveCurrentWorldviewToLibrary(silent: true);
                  if (!context.mounted) return;
                }
              }
              if (_currentStep == 1) {
                if (_characters.isEmpty) {
                  AppFeedback.info(context, l10n.pleaseAddAtLeastOneCharacter);
                  return;
                }
                if (_saveCharactersToLibrary) {
                  await _saveCurrentCharactersToLibrary(silent: true);
                  if (!context.mounted) return;
                }
              }
              if (_currentStep < 4) {
                setState(() => _currentStep += 1);
              } else {
                _handleStart();
              }
            },
            onStepCancel: () {
              if (_currentStep > 0) {
                setState(() => _currentStep -= 1);
              }
            },
            controlsBuilder: (context, details) {
              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.lg),
                child: Wrap(
                  spacing: AppSpacing.sm + 4,
                  runSpacing: AppSpacing.sm,
                  children: [
                    FilledButton(
                      onPressed: _submitting ? null : details.onStepContinue,
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_currentStep == 4
                              ? l10n.enterAdventureAction
                              : l10n.continueAction),
                    ),
                    if (_currentStep > 0) ...[
                      OutlinedButton(
                        onPressed: details.onStepCancel,
                        child: Text(l10n.previousStepAction),
                      ),
                    ],
                  ],
                ),
              );
            },
            steps: [
              Step(
                title: Text(l10n.phaseWorldview),
                isActive: _currentStep >= 0,
                content: _buildWorldviewStep(context),
              ),
              Step(
                title: Text(l10n.phaseCharacters),
                isActive: _currentStep >= 1,
                content: _buildCharacterStep(context),
              ),
              Step(
                title: Text(l10n.resourceNpcTab),
                isActive: _currentStep >= 2,
                content: _buildNpcStep(context),
              ),
              Step(
                title: Text(l10n.phaseOpening),
                isActive: _currentStep >= 3,
                content: _buildOpeningStep(context),
              ),
              Step(
                title: Text(l10n.phasePreview),
                isActive: _currentStep >= 4,
                content: _buildPreviewStep(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWorldviewStep(BuildContext context) {
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(builder: (context, constraints) {
            final stackActions = constraints.maxWidth < 420;
            return stackActions
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.public_rounded,
                            size: 20, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(l10n.worldSelectionTitle,
                                style: theme.textTheme.titleMedium)),
                      ]),
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton.tonalIcon(
                        onPressed: _openAiWorldviewCreator,
                        icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                        label: Text(l10n.worldviewCreateAction),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Icon(Icons.public_rounded,
                          size: 20, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(l10n.worldSelectionTitle,
                            style: theme.textTheme.titleMedium),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _openAiWorldviewCreator,
                        icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                        label: Text(l10n.worldviewCreateAction),
                      ),
                    ],
                  );
          }),
          const SizedBox(height: AppSpacing.sm),
          // AI 快速编写世界观卡片
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
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: scheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.xs + 2),
                    Text(
                      l10n.worldviewAiAssistantTitle,
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
                  l10n.wizardWorldviewAiSummary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _aiWorldviewPromptCtrl,
                  enabled: !_aiWorldviewGenerating,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: l10n.wizardWorldviewPromptLabel,
                    hintText: l10n.wizardWorldviewPromptHint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.all(AppSpacing.sm),
                  ),
                ),
                if (_aiWorldviewError != null) ...[
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
                        Icon(
                          Icons.error_outline_rounded,
                          color: scheme.error,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            _aiWorldviewError!,
                            style: TextStyle(
                              color: scheme.onErrorContainer,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              setState(() => _aiWorldviewError = null),
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
                      selected: !_aiWorldviewDetailed,
                      onSelected: _aiWorldviewGenerating
                          ? null
                          : (v) {
                              if (v) {
                                setState(() => _aiWorldviewDetailed = false);
                              }
                            },
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text(l10n.detailedMode,
                          style: const TextStyle(fontSize: 12)),
                      selected: _aiWorldviewDetailed,
                      onSelected: _aiWorldviewGenerating
                          ? null
                          : (v) {
                              if (v) {
                                setState(() => _aiWorldviewDetailed = true);
                              }
                            },
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    if (_aiWorldviewProgress != null) ...[
                      const SizedBox(width: 12),
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _aiWorldviewProgress!,
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
                      onPressed: _aiWorldviewGenerating
                          ? null
                          : _generateWorldviewWithAi,
                      icon: _aiWorldviewGenerating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: Text(
                        _aiWorldviewGenerating
                            ? (_aiWorldviewDetailed
                                ? l10n.wizardWorldviewGeneratingDetailed
                                : l10n.wizardWorldviewGeneratingBrief)
                            : (_worldviewNameCtrl.text.isNotEmpty
                                ? l10n.wizardRegenerateWorldviewAction
                                : l10n.wizardGenerateWorldviewAction),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: _aiWorldviewGenerating
                          ? null
                          : _openAiWorldviewCreator,
                      icon: const Icon(Icons.library_books_rounded, size: 16),
                      label: Text(l10n.worldviewAiAssistantTitle),
                    ),
                    if (_worldviewNameCtrl.text.isNotEmpty ||
                        _worldviewDescCtrl.text.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.sm),
                      TextButton.icon(
                        onPressed: _aiWorldviewGenerating
                            ? null
                            : () {
                                setState(() {
                                  _worldviewNameCtrl.clear();
                                  _worldviewDescCtrl.clear();
                                  _selectedWorldviewId = null;
                                });
                              },
                        icon: const Icon(Icons.clear, size: 14),
                        label: Text(l10n.clearSettingsAction,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                    if (_worldviewNameCtrl.text.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.xs),
                      TextButton.icon(
                        onPressed: _aiWorldviewGenerating || _savingWorldview
                            ? null
                            : () => _saveCurrentWorldviewToLibrary(),
                        icon: const Icon(Icons.bookmark_add_outlined, size: 14),
                        label: Text(l10n.autoSaveToLibrary,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          const SizedBox(height: AppSpacing.sm),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            )
          else if (_worldviewLoadError != null)
            _resourceBanner(
              context,
              icon: Icons.error_outline,
              isError: true,
              message: l10n.resourceLoadFailedRetry,
            ),
          if (_worldviews.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.worldSelectionSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _openWorldSelectionPage,
                  icon: const Icon(Icons.travel_explore_rounded, size: 16),
                  label: Text(l10n.fullscreenPreviewButton),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _worldviews.map((wv) {
                final id = wv['id'] as String;
                final name = wv['name'] as String? ?? l10n.unnamedWorldview;
                final isSelected = id == _selectedWorldviewId;
                return ChoiceChip(
                  avatar: isSelected
                      ? const Icon(Icons.check, size: 14)
                      : const Icon(Icons.public, size: 14),
                  label: Text(name),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedWorldviewId = id;
                        _worldviewNameCtrl.text = name;
                        _worldviewDescCtrl.text =
                            wv['description'] as String? ?? '';
                      } else {
                        _selectedWorldviewId = null;
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.md),
          ] else if (_worldviewLoadError == null) ...[
            _resourceBanner(
              context,
              icon: Icons.info_outline,
              isError: false,
              message:
                  '${l10n.worldSelectionEmptyTitle}\n${l10n.worldSelectionEmptyDesc}',
            ),
          ],
          AppTextField(
            controller: _worldviewNameCtrl,
            label: l10n.worldNameRequiredLabel,
            hintText: l10n.worldNameHint,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: _worldviewDescCtrl,
            label: l10n.lawsAndBackgroundLabel,
            hintText: l10n.lawsAndBackgroundHint,
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.md),

          // ── 保存到资料库选项与快捷操作 ──
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 560;
              final childContent = Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Checkbox(
                    value: _saveWorldviewToLibrary,
                    onChanged: (val) {
                      setState(() {
                        _saveWorldviewToLibrary = val ?? true;
                      });
                    },
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _saveWorldviewToLibrary = !_saveWorldviewToLibrary;
                        });
                      },
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: AppSpacing.xs,
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
                              l10n.wizardWorldviewSaveDescription,
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
                      onPressed: _savingWorldview
                          ? null
                          : () => _saveCurrentWorldviewToLibrary(),
                      icon: _savingWorldview
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.bookmark_add_rounded, size: 16),
                      label: Text(_savingWorldview
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
                              onPressed: _savingWorldview
                                  ? null
                                  : () => _saveCurrentWorldviewToLibrary(),
                              icon: _savingWorldview
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.bookmark_add_rounded,
                                      size: 16),
                              label: Text(_savingWorldview
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
                        Icon(Icons.groups_rounded,
                            size: 20, color: scheme.primary),
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
                            icon:
                                const Icon(Icons.person_add_rounded, size: 16),
                            label: Text(l10n.newCharacterAction),
                          ),
                          OutlinedButton.icon(
                            onPressed: _openCharacterSelectionPage,
                            icon: const Icon(Icons.person_search_rounded,
                                size: 16),
                            label: Text(l10n.fullscreenSelectionAction),
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Icon(Icons.groups_rounded,
                          size: 20, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(l10n.characterSelectionTitle,
                            style: theme.textTheme.titleMedium),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _openCharacterEditor(),
                        icon: const Icon(Icons.person_add_rounded, size: 16),
                        label: Text(l10n.newCharacterAction),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      OutlinedButton.icon(
                        onPressed: _openCharacterSelectionPage,
                        icon: const Icon(Icons.person_search_rounded, size: 16),
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
                    Icon(
                      Icons.auto_awesome_rounded,
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
                        Icon(
                          Icons.error_outline_rounded,
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
                          icon: const Icon(Icons.close, size: 16),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              setState(() => _aiCharacterError = null),
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
                                setState(() => _aiCharacterDetailed = false);
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
                                setState(() => _aiCharacterDetailed = true);
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
                          : const Icon(Icons.auto_awesome_rounded, size: 18),
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
                      icon: const Icon(Icons.library_books_rounded, size: 16),
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
              icon: Icons.error_outline,
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
              icon: Icons.warning_amber_rounded,
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
                      ? const Icon(Icons.check, size: 14)
                      : const Icon(Icons.person_rounded, size: 14),
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
              icon: Icons.info_outline,
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
                  Icon(
                    Icons.groups_outlined,
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
                                const Icon(Icons.star_rounded,
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
                            icon: const Icon(Icons.star_outline_rounded,
                                size: 14),
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
                          icon:
                              const Icon(Icons.bookmark_add_outlined, size: 18),
                          tooltip: l10n.saveToLibraryNow,
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          onPressed: () =>
                              _openCharacterEditor(existing: character),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: l10n.editAction,
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          onPressed: () => _removeCharacter(character.id),
                          icon: const Icon(Icons.close, size: 18),
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
                                setState(() {
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
                Icon(Icons.hub_rounded, size: 20, color: scheme.tertiary),
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
                                child: Icon(Icons.swap_horiz_rounded, size: 16),
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
                              setState(() {
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
                      setState(() {
                        _saveCharactersToLibrary = val ?? true;
                      });
                    },
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() {
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
                          : const Icon(Icons.bookmark_add_rounded, size: 16),
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
                                  : const Icon(Icons.bookmark_add_rounded,
                                      size: 16),
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

  Widget _buildOpeningStep(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = _l10n(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.openingAndRulesAdvancedConfigTitle,
                    style: theme.textTheme.titleMedium),
              ),
              TextButton.icon(
                onPressed: _openConfigPage,
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: Text(l10n.fullscreenAdvancedConfig),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // AI 自动构思生成卡片
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.28),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.xs + 2),
                    // Flexes so the badge below never pushes the title off a
                    // narrow phone screen.
                    Flexible(
                      child: Text(
                        l10n.aiOpeningPanelTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        l10n.wizardWorldviewQuickBadge,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.aiOpeningPanelDesc,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _aiPromptCtrl,
                  enabled: !_aiGenerating,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: l10n.openingPromptLabel,
                    hintText: l10n.openingPromptHint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.all(AppSpacing.sm),
                  ),
                ),
                if (_aiGenError != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: colorScheme.error,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            _aiGenError!,
                            style: TextStyle(
                              color: colorScheme.onErrorContainer,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => _aiGenError = null),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                // Buttons wrap on narrow phones instead of being pushed
                // off-screen by the fixed Row.
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _aiGenerating ? null : _generateOpeningWithAi,
                      icon: _aiGenerating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: Text(
                        _aiGenerating
                            ? l10n.aiOpeningGeneratingProgress
                            : (_openingSceneCtrl.text.isNotEmpty
                                ? l10n.regenerate
                                : l10n.aiGenerateOpeningAndBranches),
                      ),
                    ),
                    if (_openingSceneCtrl.text.isNotEmpty ||
                        _option1Ctrl.text.isNotEmpty) ...[
                      OutlinedButton.icon(
                        onPressed: _aiGenerating
                            ? null
                            : () {
                                setState(() {
                                  _openingSceneCtrl.clear();
                                  _option1Ctrl.clear();
                                  _option2Ctrl.clear();
                                  _option3Ctrl.clear();
                                });
                              },
                        icon: const Icon(Icons.cleaning_services_outlined,
                            size: 16),
                        label: Text(l10n.clearSettingsAction),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
          const SizedBox(height: AppSpacing.sm),
          // 开场第一幕剧情描写
          Row(
            children: [
              Text(
                l10n.openingFirstSceneTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  l10n.openingFirstSceneDesc,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          AppTextField(
            controller: _openingSceneCtrl,
            hintText: l10n.openingFirstSceneHint,
            maxLines: 5,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          // 初始行动抉择分支
          Row(
            children: [
              Text(
                l10n.initialActionBranchesTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              // The hint flexes and ellipsizes so the row still fits at 320px
              // when the clear action is visible.
              Flexible(
                child: Text(
                  l10n.initialActionBranchesDesc,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              if (_option1Ctrl.text.isNotEmpty ||
                  _option2Ctrl.text.isNotEmpty ||
                  _option3Ctrl.text.isNotEmpty)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _option1Ctrl.clear();
                    _option2Ctrl.clear();
                    _option3Ctrl.clear();
                  }),
                  icon: const Icon(Icons.clear, size: 14),
                  label: Text(l10n.clearSettingsAction,
                      style: const TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          _buildBranchOptionField(
            controller: _option1Ctrl,
            indexLabel: l10n.actionBranch1,
            hint: l10n.actionBranch1Hint,
            scheme: colorScheme,
          ),
          const SizedBox(height: AppSpacing.xs + 2),
          _buildBranchOptionField(
            controller: _option2Ctrl,
            indexLabel: l10n.actionBranch2,
            hint: l10n.actionBranch2Hint,
            scheme: colorScheme,
          ),
          const SizedBox(height: AppSpacing.xs + 2),
          _buildBranchOptionField(
            controller: _option3Ctrl,
            indexLabel: l10n.actionBranch3,
            hint: l10n.actionBranch3Hint,
            scheme: colorScheme,
          ),
        ],
      ),
    );
  }

  Widget _buildBranchOptionField({
    required TextEditingController controller,
    required String indexLabel,
    required String hint,
    required ColorScheme scheme,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 13),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 10, right: 8),
          child: Center(
            widthFactor: 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                indexLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                ),
              ),
            ),
          ),
        ),
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }

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
                icon: const Icon(Icons.record_voice_over_rounded, size: 16),
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
              icon: Icons.error_outline,
              isError: true,
              message: l10n.resourceLoadFailedRetry,
            )
          else if (orderedNpcs.isEmpty)
            _resourceBanner(
              context,
              icon: Icons.info_outline,
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
                      avatar: const Icon(Icons.record_voice_over, size: 16),
                      label: Text(
                        '${npc['name']?.toString() ?? l10n.unnamedNpc} · $originLabel',
                      ),
                      onSelected: (selected) {
                        setState(() {
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
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(l10n.fullscreenPreviewButton),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.public, color: colorScheme.primary),
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
            leading: Icon(Icons.person, color: colorScheme.secondary),
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
              leading: Icon(Icons.groups_rounded, color: colorScheme.tertiary),
              title: Text(
                  l10n.accompanyingCharactersCount(otherCharacters.length)),
              subtitle: Text(
                otherCharacters.map((c) {
                  final role =
                      c.narrativeRole == AdventureCharacterRole.custom &&
                              c.customRoleName.trim().isNotEmpty
                          ? c.customRoleName.trim()
                          : _localizedAdventureRole(c.narrativeRole, l10n);
                  return '${c.name} [$role${c.profession.isNotEmpty ? " · ${c.profession}" : ""}]';
                }).join('、'),
              ),
            ),
          if (_selectedNpcIds.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading:
                  Icon(Icons.record_voice_over, color: colorScheme.tertiary),
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
              leading: Icon(Icons.hub_rounded, color: colorScheme.primary),
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
                          : _localizedAdventureRelation(r.relationType, l10n);
                  return '$n1 ⇄ $n2: $relation$desc';
                }).join('；'),
              ),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.play_circle_fill, color: colorScheme.tertiary),
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
                  : const Icon(Icons.bookmark_add_outlined, size: 18),
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
