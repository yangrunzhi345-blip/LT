import 'dart:convert';

import 'package:flutter/material.dart';
import '../../../../../core/widgets/app_svg_icon.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/feedback/app_feedback.dart';
import '../../../../../core/localization/app_error_localizer.dart';
import '../../../../../domain/errors/app_error.dart';
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
import '../../../../../models/supporting_character.dart';
import '../../../../../application/adventure/adventure_readiness_gate.dart';
import '../../../application/use_cases/start_adventure_from_wizard.dart';
import '../../../../../domain/resources/resource_contracts.dart';
import '../../../../../domain/setting_cards/setting_card.dart';
import '../../../../resource_library/presentation/screens/setting_card_detail_page.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../widgets/assembly_readiness_dialogs.dart';
import '../adventure_preview_saver.dart';
import '../adventure_readiness_message_localization.dart';
import '../../../../../core/widgets/app_dialogs.dart';
import '../../../../../core/router/app_router.dart';
import '../models/wizard_character_item.dart';
import '../adventure_label_formatters.dart';
import '../widgets/character_step/character_ai_panel.dart';
import '../widgets/character_step/character_library_panel.dart';
import '../widgets/character_step/character_library_save_option.dart';
import '../widgets/character_step/character_relationship_panel.dart';
import '../widgets/character_step/character_roster_panel.dart';
import '../widgets/character_step/character_step_header.dart';
import '../widgets/wizard_resource_banner.dart';
import '../widgets/assembly_opening_ai.dart';
import 'assembly_config_page.dart';
import 'assembly_preview_page.dart';
import 'character_selection_page.dart';
import 'npc_selection_page.dart';
import 'world_selection_page.dart';

part 'adventure_wizard_worldview_step.dart';
part 'adventure_wizard_character_step.dart';
part 'adventure_wizard_opening_step.dart';
part 'adventure_wizard_npc_preview_steps.dart';
part 'adventure_wizard_config_composer.dart';
part 'adventure_wizard_library_sync.dart';
part 'adventure_wizard_navigation_actions.dart';
part 'adventure_wizard_ai_drafts.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

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
  bool _aiWorldviewGenerating = false;
  String? _aiWorldviewError;
  bool _aiWorldviewDetailed = false;
  String? _aiWorldviewProgress;
  bool _saveWorldviewToLibrary = true;
  bool _savingWorldview = false;

  // Step 2: 角色设计 (多角色选择、身份赋予、关系网络)
  final List<WizardCharacterItem> _characters = [];
  final List<WizardRelationshipItem> _relationships = [];
  late final TextEditingController _aiCharacterPromptCtrl;
  bool _aiCharacterGenerating = false;
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
            sourceRole: rel.sourceRole,
            targetRole: rel.targetRole,
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
          _worldviewLoadError ??= localizeAppError(
            _l10n(context),
            asAppDomainError(e),
          );
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
    required String icon,
    required String message,
    required bool isError,
  }) {
    return WizardResourceBanner(icon: icon, message: message, isError: isError);
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

    // 单一异常边界：持久化、快照重建、配置装配、readiness gate 与启动回调
    // 全部纳入同一个 try/catch/finally。任何一步失败都会复位 _submitting
    // 并把错误反馈给用户，避免按钮永久 disabled。
    try {
      final useCase = ref.read(startAdventureFromWizardUseCaseProvider);
      final activeWvId = _getOrCreateActiveWorldviewId();
      final wvName = _worldviewNameCtrl.text.trim().isNotEmpty
          ? _worldviewNameCtrl.text.trim()
          : '未知大陆';

      final outcome = await useCase.prepare(
        draft: _buildStartDraft(activeWvId, wvName),
        composeConfig: (worldviewSnapshot) => _composeAdventureConfig(
          worldview: wvName,
          worldviewSnapshot: worldviewSnapshot,
        ),
      );
      if (_saveCharactersToLibrary) {
        ref.read(libraryProvider).loadCharacterCards();
      }
      if (!mounted) return;

      // Phase 10: assembly readiness 门禁。被选中的统一资源必须已就绪；
      // 存在旧 ready revision 时由用户明确选择，绝不静默降级。
      late final AdventureConfig startConfig;
      switch (outcome) {
        case WizardStartBlocked(:final issues):
          await showAssemblyReadinessBlockDialog(
            context,
            issues
                .map((readiness) => localizeAdventureReadiness(readiness, l10n))
                .toList(),
          );
          return;
        case WizardStartNeedsStaleConfirmation():
          final usePrevious = await showStaleAssemblyChoiceDialog(
            context,
            outcome.stale
                .map((readiness) => localizeAdventureReadiness(readiness, l10n))
                .toList(),
          );
          if (!usePrevious) return;
          startConfig = useCase.acceptStale(outcome);
        case WizardStartReady(:final config):
          startConfig = config;
      }

      if (!mounted) return;
      await widget.onStartAdventure(startConfig);
      if (mounted) {
        final chatAfter = ref.read(chatProvider);
        if (chatAfter.isAdventureChatOpen && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    } catch (e, st) {
      // 保留诊断堆栈以定位是哪一步失败，同时只向用户暴露安全文案。
      debugPrint('Adventure start failed: ${e.runtimeType}\n$st');
      if (mounted) {
        final message = e is AdventureReadinessGateException
            ? (e.issues.isNotEmpty
                ? e.issues
                    .map((item) => localizeAdventureReadiness(item, l10n))
                    .join('\n')
                : e.error != null
                    ? localizeAppError(l10n, e.error!)
                    : localizeAppError(
                        l10n,
                        const AppDomainError(
                          code: AppErrorCode.adventureAssetMissing,
                        ),
                      ))
            : localizeAppError(
                l10n,
                const AppDomainError(code: AppErrorCode.unknown),
              );
        AppFeedback.error(context, l10n.startAdventureFailed(message));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Collector for [StartAdventureFromWizardUseCase]: turns the current wizard
  /// state into pure data so the start boundary owns no widget reading.
  WizardStartDraft _buildStartDraft(String activeWorldviewId, String wvName) {
    final existingWv = _worldviews
        .where((w) => w['id']?.toString() == activeWorldviewId)
        .firstOrNull;
    return WizardStartDraft(
      worldview: WizardWorldviewDraft(
        id: activeWorldviewId,
        name: wvName,
        description: _worldviewDescCtrl.text.trim(),
        detailJson: existingWv?['detail_json'] as String? ?? '{}',
        saveToLibrary: _saveWorldviewToLibrary,
      ),
      characters: [
        for (final c in _characters)
          WizardCharacterDraft(
            id: c.id,
            name: c.name,
            jsonData: jsonEncode(
              c.rawJson ??
                  {
                    'name': c.name,
                    'gender': c.gender,
                    'age': c.age,
                    'profession': c.profession,
                    'personality': c.personality,
                    'description': c.background,
                  },
            ),
            matchingWorldviewId: c.libraryEntry?.matchingWorldviewId ?? '',
          ),
      ],
      saveCharacters: _saveCharactersToLibrary,
    );
  }

  /// Extension-part rebuild hook.
  ///
  /// `setState` is protected and cannot be invoked from an extension, so the
  /// step widgets go through this single instance method.
  void _rebuild(VoidCallback fn) => setState(fn);

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
          icon: const AppSvgIcon('close'),
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
}
