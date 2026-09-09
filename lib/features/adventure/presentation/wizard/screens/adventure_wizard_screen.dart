import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/feedback/app_feedback.dart';
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
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../screens/resource_library/character_card_tab.dart';
import '../../../../../screens/resource_library/scene_batch_import_page.dart';
import '../../../../../screens/resource_library/worldview_tab.dart';
import '../../../../../services/worldview_snapshot_service.dart';
import '../../../../../widgets/app_dialogs.dart';
import '../models/wizard_character_item.dart';

/// 现代化流式场景创建向导 (Adventure Wizard)
/// 全面联动资料库：支持世界观快照绑定、多角色选择与身份赋予 (男主/女主/同伴等)、角色间羁绊关系网设定
class AdventureWizardScreen extends ConsumerStatefulWidget {
  final Future<void> Function(AdventureConfig config) onStartAdventure;
  final AdventureConfig? initialConfig;
  final String? initialWorldviewId;
  final String? initialCharacterId;
  final int reloadTrigger;

  const AdventureWizardScreen({
    super.key,
    required this.onStartAdventure,
    this.initialConfig,
    this.initialWorldviewId,
    this.initialCharacterId,
    this.reloadTrigger = 0,
  });

  @override
  ConsumerState<AdventureWizardScreen> createState() =>
      _AdventureWizardScreenState();
}

class _AdventureWizardScreenState extends ConsumerState<AdventureWizardScreen> {
  int _currentStep = 0;
  bool _loading = true;
  bool _submitting = false;

  List<Map<String, dynamic>> _worldviews = [];
  List<CharacterCardEntry> _characterCardEntries = [];

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
    _worldviewDescCtrl = TextEditingController();
    _aiWorldviewPromptCtrl = TextEditingController();
    _aiCharacterPromptCtrl = TextEditingController();
    _aiCustomRelationCtrl = TextEditingController();

    _openingSceneCtrl = TextEditingController(text: cfg?.openingScene ?? '');
    _option1Ctrl = TextEditingController();
    _option2Ctrl = TextEditingController();
    _option3Ctrl = TextEditingController();
    _aiPromptCtrl = TextEditingController();

    // 从初始配置中恢复角色与关系 (若有)
    if (cfg != null) {
      if (cfg.selectedCharacters.isNotEmpty) {
        for (final sc in cfg.selectedCharacters) {
          _characters.add(WizardCharacterItem(
            id: sc.characterId,
            name: sc.characterName,
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
    try {
      final setupController = ref.read(adventureSetupControllerProvider);
      await setupController.loadInitialData();
      final wvList = setupController.worldviewPresets;
      final cardEntries = setupController.characterCardEntries;

      if (mounted) {
        setState(() {
          _worldviews = wvList;
          _characterCardEntries = cardEntries;

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
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
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
          ),
        );
      }
    }
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
    final wvName = _worldviewNameCtrl.text.trim();
    if (wvName.isEmpty) {
      if (!silent) {
        AppFeedback.info(context, '请先输入或通过 AI 生成世界观名称');
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
          AppFeedback.success(context, '世界观「$wvName」已成功保存至资料库！');
        }
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _savingWorldview = false);
        if (!silent) {
          AppFeedback.error(context, '保存到资料库失败: $e');
        }
      }
      return false;
    }
  }

  /// 手动将当前设计的角色保存至资料库
  Future<bool> _saveCurrentCharactersToLibrary({bool silent = false}) async {
    if (_characters.isEmpty) {
      if (!silent && mounted) {
        AppFeedback.info(context, '当前阵容中暂无角色，请先添加或生成角色');
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
            '已成功将 ${_characters.length} 个角色设定保存至资料库！',
          );
        }
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _savingCharacters = false);
        if (!silent) {
          AppFeedback.error(context, '保存角色到资料库失败: $e');
        }
      }
      return false;
    }
  }

  /// 保存单个角色到资料库
  Future<void> _saveSingleCharacterToLibrary(
      WizardCharacterItem character) async {
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
          '角色「${character.name}」已成功保存至资料库！',
        );
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, '保存角色失败: $e');
      }
    }
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
          AppFeedback.success(context, '已从资料库 AI 选定世界观「${newWv['name']}」！');
        }
      },
      _worldviews,
      mode: ResourceLibraryMode.adventure,
    );
  }

  /// AI 自动编写世界观设定（支持简约模式与详细模式4段多轮连续生成）
  Future<void> _generateWorldviewWithAi() async {
    final chat = ref.read(chatProvider);
    if (!chat.isKeyConfigured) {
      AppFeedback.info(context, '请先配置 API Key 以使用 AI 自动生成功能');
      showApiSettings(context);
      return;
    }

    setState(() {
      _aiWorldviewGenerating = true;
      _aiWorldviewError = null;
      _aiWorldviewProgress = _aiWorldviewDetailed ? '正在连接 AI 开始构思...' : null;
    });

    try {
      final userPrompt = _aiWorldviewPromptCtrl.text.trim();
      final effectivePrompt = userPrompt.isNotEmpty
          ? userPrompt
          : '请构思一个极具沉浸感、探索潜力与戏剧张力的世界观设定，包含世界名称以及详细的世界背景、力量体系、势力格局与核心规则';
      final aiController = ref.read(adventureAiControllerProvider);

      if (_aiWorldviewDetailed) {
        final result = await aiController.generateDetailedWorldview(
          effectivePrompt,
          onProgress: (progress) {
            if (mounted) {
              setState(() {
                _aiWorldviewProgress =
                    '[1/2] [${progress.completedQuestions}/${progress.totalQuestions}] ${progress.partialText.isNotEmpty ? progress.partialText : "推演构思中"}...';
              });
            }
          },
        );

        if (!mounted) return;

        if (result.isNotEmpty &&
            (result['name']?.isNotEmpty == true ||
                result['description']?.isNotEmpty == true)) {
          final newId = _getOrCreateActiveWorldviewId();
          final detailMap = result['detail_json'] is Map
              ? Map<String, dynamic>.from(result['detail_json'] as Map)
              : null;
          final detail = WorldviewDetails.fromJson(
            detailMap,
            fallbackDescription: result['description'] ?? '',
          );

          // 完成后将详细世界观写入资料库
          final crud = ref.read(resourceCrudControllerProvider);
          await crud.saveWorldviewPreset(
            id: newId,
            name: result['name'] ?? '未命名世界观',
            description: result['description'] ?? '',
            entriesJson: '[]',
            now: DateTime.now().toIso8601String(),
            detailJson: detail.encode(),
            source: 'AI生成',
            mode: ResourceLibraryMode.adventure,
            validate: false,
          );

          await _loadData();

          if (!mounted) return;
          setState(() {
            _aiWorldviewGenerating = false;
            _aiWorldviewProgress = null;
            _selectedWorldviewId = newId;
            if (result['name']?.isNotEmpty ?? false) {
              _worldviewNameCtrl.text = result['name']!;
            }
            if (result['description']?.isNotEmpty ?? false) {
              _worldviewDescCtrl.text = result['description']!;
            }
          });
          AppFeedback.success(context, 'AI 详细世界观已自动生成并写入资料库！');
        } else {
          setState(() {
            _aiWorldviewGenerating = false;
            _aiWorldviewProgress = null;
            _aiWorldviewError =
                aiController.errorMessage ?? '生成未返回有效内容，请检查网络或重试';
          });
        }
      } else {
        final result = await aiController.generateWorldview(effectivePrompt);

        if (!mounted) return;

        if (result.isNotEmpty &&
            (result['name']?.isNotEmpty == true ||
                result['description']?.isNotEmpty == true)) {
          setState(() {
            _aiWorldviewGenerating = false;
            _aiWorldviewProgress = null;
            _selectedWorldviewId = null; // 自定义/AI新生成
            if (result['name']?.isNotEmpty ?? false) {
              _worldviewNameCtrl.text = result['name']!;
            }
            if (result['description']?.isNotEmpty ?? false) {
              _worldviewDescCtrl.text = result['description']!;
            }
          });
          AppFeedback.success(context, 'AI 世界观名称与背景法则已自动生成并填入！');
        } else {
          setState(() {
            _aiWorldviewGenerating = false;
            _aiWorldviewProgress = null;
            _aiWorldviewError =
                aiController.errorMessage ?? '生成未返回有效内容，请检查网络或重试';
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiWorldviewGenerating = false;
        _aiWorldviewProgress = null;
        _aiWorldviewError = '生成失败：$e';
      });
    }
  }

  /// AI 自动编写角色设定（支持简约模式与详细全维模式生成）
  Future<void> _generateCharacterWithAi() async {
    final chat = ref.read(chatProvider);
    if (!chat.isKeyConfigured) {
      AppFeedback.info(context, '请先配置 API Key 以使用 AI 自动生成功能');
      showApiSettings(context);
      return;
    }

    setState(() {
      _aiCharacterGenerating = true;
      _aiCharacterError = null;
      _aiCharacterProgress = _aiCharacterDetailed ? '正在连接 AI 深度构思角色...' : null;
    });

    try {
      final userPrompt = _aiCharacterPromptCtrl.text.trim();
      final activeWv = _getActiveWorldviewItem();
      final wvName = activeWv['name'] as String? ?? '当前世界';
      final wvDesc = activeWv['description'] as String? ?? '';
      final fullWorldview = '$wvName\n$wvDesc'.trim();

      final isFirst = _characters.isEmpty;
      String defaultRoleDesc;
      if (isFirst) {
        defaultRoleDesc = '作为冒险的主角';
      } else {
        final hasProtagonist = _characters.any((c) => c.isProtagonist);
        defaultRoleDesc = hasProtagonist ? '作为冒险队伍的重要伙伴或核心角色' : '作为冒险队伍的核心角色';
      }

      String effectivePrompt;
      if (userPrompt.isNotEmpty) {
        if (userPrompt == '女主' || userPrompt == '女主角') {
          effectivePrompt =
              '女主角（女性重要角色，${isFirst ? '作为冒险的主角' : '作为与主角紧密同行的队伍核心伙伴/女主角'}）';
        } else if (userPrompt == '男主' || userPrompt == '男主角') {
          effectivePrompt =
              '男主角（男性重要角色，${isFirst ? '作为冒险的主角' : '作为队伍核心伙伴/男主角'}）';
        } else {
          effectivePrompt = '$userPrompt（$defaultRoleDesc）';
        }
      } else {
        effectivePrompt =
            '请根据世界观设定，构思一个富有戏剧张力与鲜明性格特征的冒险角色（$defaultRoleDesc），包含姓名、性别、年龄、职业身份、性格特质与核心背景经历';
      }

      final aiController = ref.read(adventureAiControllerProvider);
      final existingChars = _characters
          .map((c) => {
                'name': c.name,
                'role': c.effectiveRole,
                'gender': c.gender,
                'age': c.age,
                'profession': c.profession,
                'personality': c.personality,
                'background': c.background,
              })
          .toList();

      final effectiveRelationName = _aiRelationType == '自定义'
          ? (_aiCustomRelationCtrl.text.trim().isNotEmpty
              ? _aiCustomRelationCtrl.text.trim()
              : '伙伴')
          : _aiRelationType;

      final List<Map<String, String>> associatedCharsForAi = [];
      final List<String> associatedCharNames = [];

      for (final id in _aiAssociatedCharacterIds) {
        final c = _characters.where((char) => char.id == id).firstOrNull;
        if (c != null) {
          associatedCharsForAi.add({
            'name': c.name,
            'role': c.effectiveRole,
            'gender': c.gender,
            'age': c.age,
            'profession': c.profession,
            'personality': c.personality,
            'background': c.background,
            'relation': effectiveRelationName,
          });
          associatedCharNames.add(c.name);
          continue;
        }
        final card = _characterCardEntries.where((e) => e.id == id).firstOrNull;
        if (card != null) {
          associatedCharsForAi.add({
            'name': card.name,
            'role': card.profession,
            'gender': card.gender,
            'age': card.age,
            'profession': card.profession,
            'personality': card.personality,
            'background': card.background,
            'relation': effectiveRelationName,
          });
          associatedCharNames.add(card.name);
        }
      }

      if (associatedCharsForAi.isNotEmpty) {
        final namesStr = associatedCharNames.join('、');
        effectivePrompt +=
            '。新角色与已有角色「$namesStr」设定为【$effectiveRelationName】羁绊关系，请在角色的性格互动、身世背景与过往经历中深度体现这一羁绊！';
      }

      final charsToPass = associatedCharsForAi.isNotEmpty
          ? associatedCharsForAi
          : existingChars;

      if (_aiCharacterDetailed) {
        final result = await aiController.generateDetailedResourceCharacter(
          source: effectivePrompt,
          worldview: fullWorldview,
          associatedCharacters: charsToPass,
          onProgress: (current, total, stageName) {
            if (mounted) {
              setState(() {
                _aiCharacterProgress = '[2/2] [$current/$total] $stageName...';
              });
            }
          },
        );

        if (!mounted) return;

        if (result.isNotEmpty &&
            (result['name']?.toString().isNotEmpty ?? false)) {
          var charName = result['name']?.toString().trim() ?? '未命名角色';
          if (charName.isEmpty) charName = '未命名角色';
          if (_characters.any((c) => c.name.trim() == charName)) {
            final prof = result['profession']?.toString().trim() ?? '';
            final suffix = prof.isNotEmpty ? prof : '${_characters.length + 1}';
            charName = '$charName·$suffix';
            result['name'] = charName;
          }
          final charId = 'char_wiz_${DateTime.now().millisecondsSinceEpoch}';

          final crud = ref.read(resourceCrudControllerProvider);
          await crud.saveCharacterCard(
            id: charId,
            name: charName,
            jsonData: jsonEncode(result),
            source: '冒险向导',
            now: DateTime.now().toIso8601String(),
            matchingWorldviewId: (activeWv['id'] as String?) ?? '',
            mode: ResourceLibraryMode.adventure,
          );

          await _loadData();

          if (!mounted) return;
          final createdCard =
              _characterCardEntries.where((c) => c.id == charId).firstOrNull;
          setState(() {
            _aiCharacterGenerating = false;
            _aiCharacterProgress = null;
            if (createdCard != null) {
              _bindCharacterFromLibrary(createdCard, asProtagonist: isFirst);
            } else {
              _characters.add(WizardCharacterItem(
                id: charId,
                name: charName,
                gender: result['gender']?.toString() ?? '',
                age: result['age']?.toString() ?? '',
                profession: result['profession']?.toString() ?? '',
                personality: result['personality']?.toString() ?? '',
                background: result['background']?.toString() ?? '',
                isProtagonist: isFirst,
                narrativeRole: isFirst
                    ? AdventureCharacterRole.protagonist
                    : AdventureCharacterRole.companion,
                rawJson: result,
              ));
              _syncRelationships();
            }

            if (_aiAssociatedCharacterIds.isNotEmpty) {
              _applyAssociatedRelationships(
                  charId, charName, effectiveRelationName);
            }
            _aiCharacterPromptCtrl.clear();
          });
          final relNotice = associatedCharNames.isNotEmpty
              ? '，已建立与「${associatedCharNames.join('、')}」的【$effectiveRelationName】羁绊'
              : '';
          AppFeedback.success(
              context, 'AI 详细角色卡「$charName」已生成并加入队伍$relNotice！');
        } else {
          setState(() {
            _aiCharacterGenerating = false;
            _aiCharacterProgress = null;
            _aiCharacterError =
                aiController.errorMessage ?? '生成未返回有效内容，请检查网络或重试';
          });
        }
      } else {
        final result = await aiController.generateResourceCharacter(
          source: effectivePrompt,
          worldview: fullWorldview,
          associatedCharacters: charsToPass,
        );

        if (!mounted) return;

        if (result.isNotEmpty && (result['name']?.isNotEmpty ?? false)) {
          var charName = (result['name'] ?? '未命名角色').trim();
          if (charName.isEmpty) charName = '未命名角色';
          if (_characters.any((c) => c.name.trim() == charName)) {
            final prof = (result['profession'] ?? '').trim();
            final suffix = prof.isNotEmpty ? prof : '${_characters.length + 1}';
            charName = '$charName·$suffix';
            result['name'] = charName;
          }
          final charId = 'char_wiz_${DateTime.now().millisecondsSinceEpoch}';
          final payload = {
            'name': charName,
            'gender': result['gender'] ?? '',
            'age': result['age'] ?? '',
            'profession': result['profession'] ?? '',
            'personality': result['personality'] ?? '',
            'background': result['background'] ?? '',
          };

          final crud = ref.read(resourceCrudControllerProvider);
          await crud.saveCharacterCard(
            id: charId,
            name: charName,
            jsonData: jsonEncode(payload),
            source: '冒险向导',
            now: DateTime.now().toIso8601String(),
            matchingWorldviewId: (activeWv['id'] as String?) ?? '',
            mode: ResourceLibraryMode.adventure,
          );

          await _loadData();

          if (!mounted) return;
          final createdCard =
              _characterCardEntries.where((c) => c.id == charId).firstOrNull;
          setState(() {
            _aiCharacterGenerating = false;
            _aiCharacterProgress = null;
            if (createdCard != null) {
              _bindCharacterFromLibrary(createdCard, asProtagonist: isFirst);
            } else {
              _characters.add(WizardCharacterItem(
                id: charId,
                name: charName,
                gender: result['gender'] ?? '',
                age: result['age'] ?? '',
                profession: result['profession'] ?? '',
                personality: result['personality'] ?? '',
                background: result['background'] ?? '',
                isProtagonist: isFirst,
                narrativeRole: isFirst
                    ? AdventureCharacterRole.protagonist
                    : AdventureCharacterRole.companion,
                rawJson: payload,
              ));
              _syncRelationships();
            }

            if (_aiAssociatedCharacterIds.isNotEmpty) {
              _applyAssociatedRelationships(
                  charId, charName, effectiveRelationName);
            }
            _aiCharacterPromptCtrl.clear();
          });
          final relNotice = associatedCharNames.isNotEmpty
              ? '，已建立与「${associatedCharNames.join('、')}」的【$effectiveRelationName】羁绊'
              : '';
          AppFeedback.success(context, 'AI 角色「$charName」已生成并加入队伍$relNotice！');
        } else {
          setState(() {
            _aiCharacterGenerating = false;
            _aiCharacterProgress = null;
            _aiCharacterError =
                aiController.errorMessage ?? '生成未返回有效内容，请检查网络或重试';
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiCharacterGenerating = false;
        _aiCharacterProgress = null;
        _aiCharacterError = '生成失败：$e';
      });
    }
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
    final options = <AppDropdownOption<String>>[];
    for (final c in _characters) {
      final roleTag = c.isProtagonist ? '主角' : '队伍同伴';
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
        '资料库',
        if (card.gender.isNotEmpty) card.gender,
        if (card.profession.isNotEmpty) card.profession,
      ];
      options.add(AppDropdownOption(
        value: card.id,
        label: '${card.name} (资料库)',
        subtitle: subList.join(' · '),
      ));
    }
    return options;
  }

  /// 在 AI 生成角色完成后，自动将其与所选已有角色的羁绊关系写入关系网
  void _applyAssociatedRelationships(
    String newCharId,
    String newCharName,
    String relationName,
  ) {
    String mappedType = AdventureRelationType.custom;
    String customName = '';
    switch (_aiRelationType) {
      case '同伴':
        mappedType = AdventureRelationType.companion;
        break;
      case '恋人':
        mappedType = AdventureRelationType.lover;
        break;
      case '师徒':
        mappedType = AdventureRelationType.mentor;
        break;
      case '宿敌':
        mappedType = AdventureRelationType.rival;
        break;
      case '亲人':
        mappedType = AdventureRelationType.family;
        break;
      case '雇佣关系':
      case '雇主':
        mappedType = AdventureRelationType.employer;
        break;
      case '青梅竹马':
        mappedType = AdventureRelationType.custom;
        customName = '青梅竹马';
        break;
      case '救命恩人':
        mappedType = AdventureRelationType.custom;
        customName = '救命恩人';
        break;
      case '自定义':
      default:
        mappedType = AdventureRelationType.custom;
        customName = relationName;
        break;
    }

    for (final assocId in _aiAssociatedCharacterIds) {
      // 若关联角色此前仅在资料库而未在队伍中，一并添加进入向导队伍
      if (!_characters.any((c) => c.id == assocId)) {
        final libCard =
            _characterCardEntries.where((c) => c.id == assocId).firstOrNull;
        if (libCard != null) {
          _characters.add(WizardCharacterItem(
            id: libCard.id,
            name: libCard.name,
            gender: libCard.gender,
            age: libCard.age,
            profession: libCard.profession,
            personality: libCard.personality,
            background: libCard.background,
            isProtagonist: false,
            narrativeRole: AdventureCharacterRole.companion,
            libraryEntry: libCard,
            rawJson: libCard.rawData,
          ));
        }
      }

      final stableId =
          AdventureCharacterRelationship.stableId(assocId, newCharId);
      final assocName = _getAssociatedCharacterShortName(assocId);
      final existingIndex = _relationships.indexWhere((r) => r.id == stableId);

      final relItem = WizardRelationshipItem(
        id: stableId,
        sourceCharacterId: assocId,
        targetCharacterId: newCharId,
        relationType: mappedType,
        customRelationName: customName,
        description: '$newCharName 与 $assocName 设定为 $relationName 关系',
      );

      if (existingIndex >= 0) {
        _relationships[existingIndex] = relItem;
      } else {
        _relationships.add(relItem);
      }
    }
    _syncRelationships();
  }

  /// 构建 AI 角色生成卡中的关联已有角色设定区
  Widget _buildAiCharacterAssociationSection(
    ColorScheme scheme,
    ThemeData theme,
  ) {
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
              Text(
                '关联已有角色生成 (可选)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _aiAssociatedCharacterIds.isNotEmpty
                      ? scheme.primary
                      : scheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '新角色将与所选角色建立深层故事羁绊',
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
                      '清空关联',
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
            label: '选择关联已有角色',
            hintText: '点击勾选要产生羁绊联系的已有角色（留空则为独立新角色）',
            emptyText: '暂无可关联的已有角色',
            options: options,
            direction: AppDropdownDirection.down,
            triggerHeight: 38,
            triggerPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            selectedBuilder: (values) {
              if (values.isEmpty) return '不关联（作为独立新角色构思）';
              final names = values
                  .map((id) => _getAssociatedCharacterShortName(id))
                  .toList();
              return '已关联 ${values.length} 位角色: ${names.join('、')}';
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
                  '羁绊关系：',
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
                  options: const [
                    AppDropdownOption(value: '同伴', label: '同伴 / 队友'),
                    AppDropdownOption(value: '青梅竹马', label: '青梅竹马'),
                    AppDropdownOption(value: '恋人', label: '恋人 / 命定伴侣'),
                    AppDropdownOption(value: '师徒', label: '师徒 (师承/弟子)'),
                    AppDropdownOption(value: '宿敌', label: '宿敌 / 竞争对手'),
                    AppDropdownOption(value: '亲人', label: '家族亲人'),
                    AppDropdownOption(value: '救命恩人', label: '救命恩人 / 报恩'),
                    AppDropdownOption(value: '雇佣关系', label: '雇佣关系'),
                    AppDropdownOption(value: '自定义', label: '自定义关系...'),
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
                      children: [
                        '同伴',
                        '青梅竹马',
                        '恋人',
                        '师徒',
                        '宿敌',
                        '救命恩人',
                      ].map((preset) {
                        final isSel = _aiRelationType == preset;
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: ChoiceChip(
                            label: Text(
                              preset,
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
                  decoration: const InputDecoration(
                    labelText: '自定义关系描述',
                    hintText: '例如：指腹为婚的未婚妻、异界灵魂共生者、背负血海深仇的遗孤...',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
          AppFeedback.success(context, 'AI 创作的角色已自动加入冒险队伍！');
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

  List<Map<String, String>> _buildSelectedCharacterContexts() {
    return _characters.map((c) {
      return {
        'name': c.name,
        'isProtagonist': c.isProtagonist ? 'true' : 'false',
        'role': c.effectiveRole,
        'personality': c.personality,
        'background': c.background,
        'profession': c.profession,
        'gender': c.gender,
        'age': c.age,
      };
    }).toList();
  }

  List<Map<String, String>> _buildCharacterRelationshipContexts() {
    return _relationships.map((r) {
      final c1 =
          _characters.where((c) => c.id == r.sourceCharacterId).firstOrNull;
      final c2 =
          _characters.where((c) => c.id == r.targetCharacterId).firstOrNull;
      final name1 = c1?.name ?? r.sourceCharacterId;
      final name2 = c2?.name ?? r.targetCharacterId;
      return {
        'sourceName': name1,
        'targetName': name2,
        'relationType': r.effectiveRelation,
        'description': r.description,
      };
    }).toList();
  }

  /// AI 自动编写序章与初始行动分支
  Future<void> _generateOpeningWithAi() async {
    final chat = ref.read(chatProvider);
    if (!chat.isKeyConfigured) {
      AppFeedback.info(context, '请先配置 API Key 以使用 AI 自动生成功能');
      showApiSettings(context);
      return;
    }

    setState(() {
      _aiGenerating = true;
      _aiGenError = null;
    });

    try {
      final userPrompt = _aiPromptCtrl.text.trim();
      final protagonist =
          _characters.where((c) => c.isProtagonist).firstOrNull ??
              _characters.firstOrNull;

      final selectedChars = _buildSelectedCharacterContexts();
      final characterRels = _buildCharacterRelationshipContexts();

      final aiController = ref.read(adventureAiControllerProvider);
      final result = await aiController.generateOpening(
        userPrompt: userPrompt.isNotEmpty
            ? userPrompt
            : '请根据世界观和当前登场角色的性格、身份及羁绊关系，设计一个引人入胜的冒险序章开幕与3个极具代入感的初始行动抉择',
        worldview: _worldviewDescCtrl.text.trim().isNotEmpty
            ? _worldviewDescCtrl.text.trim()
            : (_worldviewNameCtrl.text.trim().isNotEmpty
                ? _worldviewNameCtrl.text.trim()
                : '未知世界'),
        protagonistName: protagonist?.name ?? '',
        protagonistRole: protagonist?.effectiveRole ?? '',
        protagonistPersonality: protagonist?.personality ?? '',
        protagonistBackground: protagonist?.background ?? '',
        selectedCharacters: selectedChars,
        characterRelationships: characterRels,
      );

      if (!mounted) return;

      if (result != null) {
        final sceneText = result['scene']?.trim() ?? '';
        final rawOptions = result['options'] ?? '';
        final optionLines = rawOptions
            .split('\n')
            .map((l) => l.replaceFirst(RegExp(r'^\d+[\.\s、]+'), '').trim())
            .where((l) => l.isNotEmpty)
            .toList();

        setState(() {
          _aiGenerating = false;
          if (sceneText.isNotEmpty) {
            _openingSceneCtrl.text = sceneText;
          }
          if (optionLines.isNotEmpty) {
            _option1Ctrl.text = optionLines[0];
            _option2Ctrl.text = optionLines.length > 1 ? optionLines[1] : '';
            _option3Ctrl.text = optionLines.length > 2 ? optionLines[2] : '';
          }
        });

        AppFeedback.success(context, 'AI 序章与初始行动分支已自动生成并填入！');
      } else {
        setState(() {
          _aiGenerating = false;
          _aiGenError = aiController.errorMessage ?? '生成未返回有效内容，请检查网络或重试';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiGenerating = false;
        _aiGenError = '生成失败：$e';
      });
    }
  }

  Future<void> _handleStart() async {
    if (_submitting) return;

    final chat = ref.read(chatProvider);
    if (!chat.isKeyConfigured) {
      showApiSettings(context);
      return;
    }

    if (_characters.isEmpty) {
      AppFeedback.info(context, '请至少添加一个角色作为冒险主角');
      return;
    }

    // 确保有且仅有一个主控主角
    if (!_characters.any((c) => c.isProtagonist)) {
      _characters.first.isProtagonist = true;
      _characters.first.narrativeRole = AdventureCharacterRole.protagonist;
    }

    setState(() => _submitting = true);

    final setupController = ref.read(adventureSetupControllerProvider);
    final activeWvId = _getOrCreateActiveWorldviewId();
    final wvName = _worldviewNameCtrl.text.trim().isNotEmpty
        ? _worldviewNameCtrl.text.trim()
        : '未知大陆';
    final wvDesc = _worldviewDescCtrl.text.trim();

    // 1. 自动持久化当前生效的世界观
    final crud = ref.read(resourceCrudControllerProvider);
    final repo = ref.read(libraryRepoProvider);

    final existingWv =
        _worldviews.where((w) => w['id']?.toString() == activeWvId).firstOrNull;
    final detailJson = existingWv?['detail_json'] as String? ?? '{}';

    if (_saveWorldviewToLibrary) {
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
        details: WorldviewDetails.fromJson(detail, fallbackDescription: wvDesc),
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
      ref.read(libraryProvider).loadCharacterCards();
    }

    // 3. 构建主控主角与多角色列表
    final protagonist = _characters.firstWhere((c) => c.isProtagonist);
    final selectedCharacters = <AdventureSelectedCharacter>[];

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

      selectedCharacters.add(
        AdventureSelectedCharacter(
          id: c.id,
          characterId: c.id,
          characterName: c.name,
          isProtagonist: c.isProtagonist,
          narrativeRole: c.narrativeRole,
          customRoleName: c.customRoleName,
          sortOrder: c.isProtagonist ? 0 : i + 1,
          characterCardJson: cardJson,
        ),
      );
    }

    // 4. 构建角色关系网络
    final relationships = _relationships.map((r) {
      return AdventureCharacterRelationship(
        id: r.id,
        sourceCharacterId: r.sourceCharacterId,
        targetCharacterId: r.targetCharacterId,
        relationType: r.relationType,
        customRelationName: r.customRelationName,
        description: r.description,
      );
    }).toList();

    // 5. 构建同伴/配角列表 (兼容原有提示词与逻辑)
    final supportingCharacters = <SupportingCharacter>[];
    for (final c in _characters) {
      if (!c.isProtagonist) {
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

        supportingCharacters.add(
          SupportingCharacter(
            id: c.id,
            name: c.name,
            gender: c.gender,
            role: c.profession.isNotEmpty ? c.profession : c.effectiveRole,
            relation: rel != null ? rel.effectiveRelation : c.effectiveRole,
            personality: c.personality,
            customAttributes: listAttrs,
          ),
        );
      }
    }

    final openingOpts = [
      _option1Ctrl.text.trim(),
      _option2Ctrl.text.trim(),
      _option3Ctrl.text.trim(),
    ].where((opt) => opt.isNotEmpty).toList();

    final config = AdventureConfig(
      worldview: wvName,
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
      selectedCharacters: selectedCharacters,
      characterRelationships: relationships,
      supportingCharacters: supportingCharacters,
      openingScene: _openingSceneCtrl.text.trim().isNotEmpty
          ? _openingSceneCtrl.text.trim()
          : '你在未知的起点苏醒，周围寂静无声。你整理了一下行囊，准备迈出第一步。',
      openingOptions: openingOpts.isNotEmpty
          ? openingOpts
          : ['检查随身携带的装备与地图', '顺着前方道路继续探索', '隐蔽身形，观察四周动静'],
    );

    try {
      await widget.onStartAdventure(config);
      if (mounted) {
        final chatAfter = ref.read(chatProvider);
        if (chatAfter.isAdventureChatOpen && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, '启动场景失败: $e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final isCompact = size.width < 600 || (size.width < 720 && textScale > 1.2);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('定制冒险向导'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: '关闭',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: Stepper(
        type: isCompact ? StepperType.vertical : StepperType.horizontal,
        currentStep: _currentStep,
        onStepTapped: (step) => setState(() => _currentStep = step),
        onStepContinue: () async {
          if (_currentStep == 0) {
            if (_saveWorldviewToLibrary &&
                _worldviewNameCtrl.text.trim().isNotEmpty) {
              await _saveCurrentWorldviewToLibrary(silent: true);
              if (!context.mounted) return;
            }
          }
          if (_currentStep == 1) {
            if (_characters.isEmpty) {
              AppFeedback.info(context, '请至少添加一个角色');
              return;
            }
            if (_saveCharactersToLibrary) {
              await _saveCurrentCharactersToLibrary(silent: true);
              if (!context.mounted) return;
            }
          }
          if (_currentStep < 3) {
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
                      : Text(_currentStep == 3 ? '踏入冒险' : '下一步'),
                ),
                if (_currentStep > 0) ...[
                  OutlinedButton(
                    onPressed: details.onStepCancel,
                    child: const Text('上一步'),
                  ),
                ],
              ],
            ),
          );
        },
        steps: [
          Step(
            title: const Text('世界观'),
            isActive: _currentStep >= 0,
            content: _buildWorldviewStep(context),
          ),
          Step(
            title: const Text('角色设计'),
            isActive: _currentStep >= 1,
            content: _buildCharacterStep(context),
          ),
          Step(
            title: const Text('序章剧情'),
            isActive: _currentStep >= 2,
            content: _buildOpeningStep(context),
          ),
          Step(
            title: const Text('确认预览'),
            isActive: _currentStep >= 3,
            content: _buildPreviewStep(context),
          ),
        ],
      ),
    );
  }

  Widget _buildWorldviewStep(BuildContext context) {
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
                            child: Text('选择或自定义世界观设定',
                                style: theme.textTheme.titleMedium)),
                      ]),
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton.tonalIcon(
                        onPressed: _openAiWorldviewCreator,
                        icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                        label: const Text('AI 创作世界观'),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Icon(Icons.public_rounded,
                          size: 20, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('选择或自定义世界观设定',
                            style: theme.textTheme.titleMedium),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _openAiWorldviewCreator,
                        icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                        label: const Text('AI 创作世界观'),
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
                      'AI 自动编写世界观设定',
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
                        '支持快速构思与资料库创作',
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
                  '输入题材风格或核心构思，AI 将自动为你生成世界观名称与世界法则背景；亦可使用资料库 AI 创作完整多模块世界。',
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
                    labelText: '世界观创意要求 / 题材偏好 (可选)',
                    hintText: '例如：蒸汽朋克浮空城与古神低语、克苏鲁异界修真、深海末日城邦，留空则由 AI 自由发挥...',
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
                      '生成模式：',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    ChoiceChip(
                      label: const Text('简约模式', style: TextStyle(fontSize: 12)),
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
                      label: const Text('详细模式 (4段多轮)',
                          style: TextStyle(fontSize: 12)),
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
                            ? (_aiWorldviewDetailed ? '多轮推演中...' : '构思推演中...')
                            : (_worldviewNameCtrl.text.isNotEmpty
                                ? '重新生成世界观'
                                : '开始 AI 自动编写'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: _aiWorldviewGenerating
                          ? null
                          : _openAiWorldviewCreator,
                      icon: const Icon(Icons.library_books_rounded, size: 16),
                      label: const Text('资料库 AI 创作 (详尽版)'),
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
                        label:
                            const Text('清空设定', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                    if (_worldviewNameCtrl.text.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.xs),
                      TextButton.icon(
                        onPressed: _aiWorldviewGenerating || _savingWorldview
                            ? null
                            : () => _saveCurrentWorldviewToLibrary(),
                        icon: const Icon(Icons.bookmark_add_outlined, size: 14),
                        label:
                            const Text('存入资料库', style: TextStyle(fontSize: 12)),
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
          else if (_worldviews.isNotEmpty) ...[
            Text(
              '从资料库中选择已构想的世界设定：',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _worldviews.map((wv) {
                final id = wv['id'] as String;
                final name = wv['name'] as String? ?? '未命名世界';
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
          ] else ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: scheme.primary),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Text(
                      '资料库暂无保存的世界观，你可以直接在下方输入新设定，或前往资料库创建。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
          AppTextField(
            controller: _worldviewNameCtrl,
            label: '世界观名称',
            hintText: '输入世界名称，例如：无尽星海、神弃之城、太虚灵界...',
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: _worldviewDescCtrl,
            label: '背景设定与世界法则 (可选)',
            hintText: '简要描述世界的历史背景、力量体系、势力格局与核心规则...',
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
                                  '保存到资料库',
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
                                    '可随时复用',
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
                              '自动收录此设定至世界观资料库，方便在未来的冒险中随时调用与扩展',
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
                      label: Text(_savingWorldview ? '保存中...' : '立即保存到资料库'),
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
                              label: Text(
                                  _savingWorldview ? '保存中...' : '立即保存到资料库'),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final availableCards = [..._characterCardEntries]..sort((left, right) {
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
                            child: Text('选择或设计冒险角色',
                                style: theme.textTheme.titleMedium)),
                      ]),
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton.tonalIcon(
                        onPressed: () => _openCharacterEditor(),
                        icon: const Icon(Icons.person_add_rounded, size: 16),
                        label: const Text('新建角色'),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Icon(Icons.groups_rounded,
                          size: 20, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('选择或设计冒险角色',
                            style: theme.textTheme.titleMedium),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _openCharacterEditor(),
                        icon: const Icon(Icons.person_add_rounded, size: 16),
                        label: const Text('新建角色'),
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
                      'AI 自动编写角色设定',
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
                        '支持快速构思与资料库创作',
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
                  '输入角色性格或定位偏好，AI 将结合当前世界观「${_worldviewNameCtrl.text.trim().isNotEmpty ? _worldviewNameCtrl.text.trim() : "当前世界"}」，自动构思主角或阵容角色并直接加入队伍；亦可使用资料库 AI 进行完整创作。',
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
                    labelText: '角色创意要求 / 人设偏好 (可选)',
                    hintText:
                        '例如：性格沉稳的退魔剑士、天真活泼的治愈系白发法师、冷酷机械游侠，留空则由 AI 自由发挥...',
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
                          child: const Text('重试',
                              style: TextStyle(
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
                      '生成模式：',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    ChoiceChip(
                      label: const Text('简约模式', style: TextStyle(fontSize: 12)),
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
                      label: const Text('详细模式 (全维深度)',
                          style: TextStyle(fontSize: 12)),
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
                            ? (_aiCharacterDetailed ? '深度推演中...' : '构思推演中...')
                            : (_characters.isEmpty
                                ? '开始 AI 自动生成主角'
                                : 'AI 增添阵容角色'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: _aiCharacterGenerating
                          ? null
                          : _openAiCharacterCreator,
                      icon: const Icon(Icons.library_books_rounded, size: 16),
                      label: const Text('资料库 AI 创作 (详尽版)'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          const SizedBox(height: AppSpacing.sm),

          // 1. 从资料库中选择角色 (若有) 或统一的提示
          if (availableCards.isNotEmpty) ...[
            Text(
              '从资料库中选择已构想的角色档案：',
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
                  CharacterWorldviewCompatibility.native => ' · 当前世界',
                  CharacterWorldviewCompatibility.unbound => ' · 未绑定',
                  CharacterWorldviewCompatibility.crossWorld => ' · 来自其他世界',
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
          ] else ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: scheme.primary),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Text(
                      '资料库暂无保存的角色卡，你可以直接使用上方 AI 自动编写，或点击右上角新建角色。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 2. 已选角色阵容列表
          Row(
            children: [
              Text(
                '登场角色阵容 (${_characters.length})：',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_characters.isNotEmpty)
                Text(
                  '必须指定 1 位作为主控主角',
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
                    '暂未添加任何登场角色',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '可使用上方 AI 一键生成契合世界观的角色，或从资料库勾选/新建角色',
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
                                      '${character.age}岁',
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
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star_rounded,
                                    size: 14, color: Colors.white),
                                SizedBox(width: 4),
                                Text(
                                  '主控主角',
                                  style: TextStyle(
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
                            label: const Text('设为主控主角',
                                style: TextStyle(fontSize: 11)),
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
                          tooltip: '保存角色到资料库',
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          onPressed: () =>
                              _openCharacterEditor(existing: character),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: '编辑角色卡',
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          onPressed: () => _removeCharacter(character.id),
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: '移除',
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
                          '身份定位：',
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
                              '主控主角 (掌控行动与关键抉择)',
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
                                label:
                                    AdventureCharacterRole.labels[role] ?? role,
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
                                  decoration: const InputDecoration(
                                    hintText: '输入自定义身份...',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
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
                                '性格：${character.personality}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (character.background.isNotEmpty)
                              Text(
                                '背景：${character.background}',
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
                Text('角色羁绊与关系网', style: theme.textTheme.titleMedium),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_relationships.length} 条关系',
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
              '标明登场角色之间的羁绊纽带、阵营立场与过往恩怨，AI 推演时将严格遵循此关系脉络',
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
                          child: Row(
                            children: [
                              Text(
                                c1.name,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              if (c1.isProtagonist)
                                Text(' (主角)',
                                    style: TextStyle(
                                        fontSize: 10, color: scheme.primary)),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(Icons.swap_horiz_rounded, size: 16),
                              ),
                              Text(
                                c2.name,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              if (c2.isProtagonist)
                                Text(' (主角)',
                                    style: TextStyle(
                                        fontSize: 10, color: scheme.primary)),
                            ],
                          ),
                        ),
                        // 关系类型下拉选
                        AppDropdown<String>.compact(
                          value: rel.relationType,
                          options: [
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
                              label: AdventureRelationType.labelOf(type),
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
                    if (rel.relationType == AdventureRelationType.custom) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 32,
                        child: TextField(
                          controller: TextEditingController(
                              text: rel.customRelationName)
                            ..selection = TextSelection.collapsed(
                                offset: rel.customRelationName.length),
                          decoration: const InputDecoration(
                            labelText: '自定义关系名称',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
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
                          hintText: '描述两人的关系渊源或羁绊线索 (可选，如：十年前并肩作战，因宿怨分道扬镳...)',
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
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '保存角色到资料库',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 6),
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
                                    '可随时复用',
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
                              '自动收录阵容中的角色设定至角色资料库，方便在未来的冒险中随时调用与复用',
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
                      label: Text(_savingCharacters ? '保存中...' : '立即保存到资料库'),
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
                              label: Text(
                                  _savingCharacters ? '保存中...' : '立即保存到资料库'),
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

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                    Text(
                      'AI 自动编写序章与初始行动分支',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
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
                        '联动世界观与角色羁绊',
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
                  'AI 将深度结合你选定的世界观、主角设定以及队伍角色的身份与羁绊网络，一键推演开场第一幕即时危机，并生成3个极具代入感的初始行动抉择。',
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
                    labelText: '剧情倾向 / 特定开场要求 (可选)',
                    hintText:
                        '可输入特定偏好（例如：深夜大雨中的酒馆突遭袭击、遗迹深处苏醒等），留空则由 AI 自由发挥...',
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
                Row(
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
                            ? '构思推演中...'
                            : (_openingSceneCtrl.text.isNotEmpty
                                ? '重新生成序章与分支'
                                : '开始 AI 自动编写'),
                      ),
                    ),
                    if (_openingSceneCtrl.text.isNotEmpty ||
                        _option1Ctrl.text.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.sm),
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
                        label: const Text('清空内容'),
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
                '开场第一幕剧情描写',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '可选 · 支持手动编辑',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          AppTextField(
            controller: _openingSceneCtrl,
            hintText:
                '描述冒险开篇的时间、地点与即时危机；可使用上方 AI 一键生成，亦可手动撰写调整。留空则在踏入世界时由 AI 全自动推演...',
            maxLines: 5,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          // 初始行动抉择分支
          Row(
            children: [
              Text(
                '初始行动分支 (可选)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '(进入世界后的第一批抉择)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.outline,
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
                  label: const Text('清空分支', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          _buildBranchOptionField(
            controller: _option1Ctrl,
            indexLabel: '分支 1',
            hint: '可选行动分支 1（如：拔剑格挡并掩护同伴撤退，留空则由 AI 自动推演）',
            scheme: colorScheme,
          ),
          const SizedBox(height: AppSpacing.xs + 2),
          _buildBranchOptionField(
            controller: _option2Ctrl,
            indexLabel: '分支 2',
            hint: '可选行动分支 2（如：施展感知法术寻找隐蔽退路，留空则由 AI 自动推演）',
            scheme: colorScheme,
          ),
          const SizedBox(height: AppSpacing.xs + 2),
          _buildBranchOptionField(
            controller: _option3Ctrl,
            indexLabel: '分支 3',
            hint: '可选行动分支 3（如：冷静交涉质问对方来意，留空则由 AI 自动推演）',
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

  Widget _buildPreviewStep(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final hasWorldSnapshot = _selectedWorldviewId != null;
    final protagonist = _characters.where((c) => c.isProtagonist).firstOrNull;
    final protagonistName = protagonist?.name ?? '无名勇者';
    final protagonistClass = (protagonist?.profession.isNotEmpty ?? false)
        ? protagonist!.profession
        : '冒险者';

    final otherCharacters = _characters.where((c) => !c.isProtagonist).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('准备就绪，踏入世界', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.public, color: colorScheme.primary),
            title: Text(
                '世界设定: ${_worldviewNameCtrl.text.isNotEmpty ? _worldviewNameCtrl.text : "自定义世界"}'),
            subtitle: Text(
              hasWorldSnapshot
                  ? '已完整绑定资料库世界观快照与规则法则'
                  : (_worldviewDescCtrl.text.isNotEmpty
                      ? _worldviewDescCtrl.text
                      : '自定义大陆法则'),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.person, color: colorScheme.secondary),
            title: Text('主控主角: $protagonistName ($protagonistClass)'),
            subtitle: Text(
              protagonist != null && protagonist.personality.isNotEmpty
                  ? '性格: ${protagonist.personality}'
                  : (protagonist?.libraryEntry != null
                      ? '已完整绑定资料库角色卡档案'
                      : '已定制主角设定'),
            ),
          ),
          if (otherCharacters.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.groups_rounded, color: colorScheme.tertiary),
              title: Text('协同登场角色 (${otherCharacters.length} 位)'),
              subtitle: Text(
                otherCharacters
                    .map((c) =>
                        '${c.name} [${c.effectiveRole}${c.profession.isNotEmpty ? " · ${c.profession}" : ""}]')
                    .join('、'),
              ),
            ),
          if (_relationships.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.hub_rounded, color: colorScheme.primary),
              title: Text('角色关系与羁绊网 (${_relationships.length} 条设定)'),
              subtitle: Text(
                _relationships.map((r) {
                  final c1 = _characters
                      .where((c) => c.id == r.sourceCharacterId)
                      .firstOrNull;
                  final c2 = _characters
                      .where((c) => c.id == r.targetCharacterId)
                      .firstOrNull;
                  final n1 = c1?.name ?? '角色A';
                  final n2 = c2?.name ?? '角色B';
                  final desc =
                      r.description.isNotEmpty ? ' (${r.description})' : '';
                  return '$n1 ⇄ $n2: ${r.effectiveRelation}$desc';
                }).join('；'),
              ),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.play_circle_fill, color: colorScheme.tertiary),
            title: const Text('序幕剧情'),
            subtitle: Text(
              _openingSceneCtrl.text.isNotEmpty
                  ? _openingSceneCtrl.text
                  : '由 AI 实时推演生成沉浸式开局第一幕',
            ),
          ),
        ],
      ),
    );
  }
}
