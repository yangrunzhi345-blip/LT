import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/feedback/app_feedback.dart';
import '../../../../../core/router/app_router.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_card.dart';
import '../../../../../core/widgets/ui_foundation.dart';
import '../../../../../models/adventure_config.dart';
import '../../../../../models/character_card_entry.dart';
import '../../../../../models/resource_library_mode.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../widgets/app_dialogs.dart';
import '../models/wizard_character_item.dart';
import 'assembly_config_page.dart';
import 'assembly_preview_page.dart';
import 'character_selection_page.dart';
import 'npc_selection_page.dart';
import 'world_selection_page.dart';

/// R02-C 现代化组装总控页面 (Assembly Create Page)
///
/// 遵循 Navigation-first UI 架构：
/// 淘汰复杂嵌套弹窗与庞大 Stepper，采用独立页面推进与全屏资源选择器。
/// 包含 4 个核心阶段：
/// 1. 世界设定 (Worldview)
/// 2. 角色阵容与羁绊 (Characters & Roster)
/// 3. 序章与行动分支 (Opening & Config)
/// 4. 装配总览与启程 (Preview & Launch)
class AssemblyCreatePage extends ConsumerStatefulWidget {
  final Future<void> Function(AdventureConfig config) onStartAdventure;
  final AdventureConfig? initialConfig;
  final String? initialWorldviewId;
  final String? initialCharacterId;
  final String? initialWorldviewDesc;

  const AssemblyCreatePage({
    super.key,
    required this.onStartAdventure,
    this.initialConfig,
    this.initialWorldviewId,
    this.initialCharacterId,
    this.initialWorldviewDesc,
  });

  @override
  ConsumerState<AssemblyCreatePage> createState() => _AssemblyCreatePageState();
}

class _AssemblyCreatePageState extends ConsumerState<AssemblyCreatePage> {
  int _currentPhase = 0;
  bool _submitting = false;

  // Phase 1: 世界设定
  String? _selectedWorldviewId;
  late final TextEditingController _worldviewNameCtrl;
  late final TextEditingController _worldviewDescCtrl;

  // Phase 2: 角色阵容与羁绊
  final List<WizardCharacterItem> _characters = [];
  final List<WizardRelationshipItem> _relationships = [];
  final Set<String> _selectedNpcIds = {};

  // Phase 3: 序章剧情与抉择分支
  late final TextEditingController _openingSceneCtrl;
  late final TextEditingController _option1Ctrl;
  late final TextEditingController _option2Ctrl;
  late final TextEditingController _option3Ctrl;
  late final TextEditingController _promptCtrl;
  String _difficulty = '普通 (标准叙事与平衡挑战)';

  static const List<String> _phaseTitles = [
    '世界设定',
    '角色阵容',
    '序章分支',
    '装配总览',
  ];

  @override
  void initState() {
    super.initState();
    final cfg = widget.initialConfig;

    _worldviewNameCtrl = TextEditingController(text: cfg?.worldview ?? '');
    _worldviewDescCtrl =
        TextEditingController(text: widget.initialWorldviewDesc ?? '');

    final openingOptions = cfg?.openingOptions ?? const <String>[];
    _openingSceneCtrl = TextEditingController(text: cfg?.openingScene ?? '');
    _option1Ctrl = TextEditingController(
        text: openingOptions.isNotEmpty ? openingOptions[0] : '');
    _option2Ctrl = TextEditingController(
        text: openingOptions.length > 1 ? openingOptions[1] : '');
    _option3Ctrl = TextEditingController(
        text: openingOptions.length > 2 ? openingOptions[2] : '');
    _promptCtrl = TextEditingController();

    if (cfg != null) {
      _selectedNpcIds.addAll(cfg.npcSnapshots.map((n) => n.assetId));

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

    WidgetsBinding.instance.addPostFrameCallback((_) => _initData());
  }

  @override
  void dispose() {
    _worldviewNameCtrl.dispose();
    _worldviewDescCtrl.dispose();
    _openingSceneCtrl.dispose();
    _option1Ctrl.dispose();
    _option2Ctrl.dispose();
    _option3Ctrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    final controller = ref.read(adventureSetupControllerProvider);
    await controller.loadInitialData();
    if (!mounted) return;

    if (widget.initialWorldviewId != null &&
        widget.initialWorldviewId!.isNotEmpty) {
      final match = controller.worldviewPresets
          .where((w) => w['id']?.toString() == widget.initialWorldviewId)
          .firstOrNull;
      if (match != null) {
        setState(() {
          _selectedWorldviewId = match['id']?.toString();
          _worldviewNameCtrl.text = match['name']?.toString() ?? '';
          _worldviewDescCtrl.text = match['description']?.toString() ?? '';
        });
      }
    }

    if (widget.initialCharacterId != null &&
        widget.initialCharacterId!.isNotEmpty) {
      final match = controller.characterCardEntries
          .where((c) => c.id == widget.initialCharacterId)
          .firstOrNull;
      if (match != null && !_characters.any((c) => c.id == match.id)) {
        setState(() {
          _characters.add(WizardCharacterItem(
            id: match.id,
            name: match.name,
            gender: match.gender,
            age: match.age,
            profession: match.profession,
            personality: match.personality,
            background: match.background,
            isProtagonist: _characters.isEmpty,
            narrativeRole: _characters.isEmpty
                ? AdventureCharacterRole.protagonist
                : AdventureCharacterRole.supporting,
            libraryEntry: match,
            rawJson: match.rawData,
          ));
        });
      }
    }
  }

  void _syncRelationships() {
    if (_characters.length < 2) {
      _relationships.clear();
      return;
    }
    for (int i = 0; i < _characters.length; i++) {
      for (int j = i + 1; j < _characters.length; j++) {
        final c1 = _characters[i];
        final c2 = _characters[j];
        final exists = _relationships.any((r) =>
            (r.sourceCharacterId == c1.id && r.targetCharacterId == c2.id) ||
            (r.sourceCharacterId == c2.id && r.targetCharacterId == c1.id));
        if (!exists) {
          _relationships.add(WizardRelationshipItem(
            id: '${c1.id}_${c2.id}',
            sourceCharacterId: c1.id,
            targetCharacterId: c2.id,
          ));
        }
      }
    }
    _relationships.removeWhere((r) =>
        !_characters.any((c) => c.id == r.sourceCharacterId) ||
        !_characters.any((c) => c.id == r.targetCharacterId));
  }

  AdventureConfig _buildCurrentConfig() {
    final protagonist = _characters.where((c) => c.isProtagonist).firstOrNull ??
        (_characters.isNotEmpty ? _characters.first : null);

    final selectedChars = _characters.map((c) {
      return AdventureSelectedCharacter(
        id: c.id,
        characterId: c.id,
        characterName: c.name,
        characterAvatar: '',
        isProtagonist: c.isProtagonist,
        narrativeRole: c.narrativeRole,
        customRoleName: c.customRoleName,
        sortOrder: 0,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
        characterCardJson: c.rawJson ?? c.toLibraryRecordMap(),
      );
    }).toList();

    final rels = _relationships.map((r) {
      return AdventureCharacterRelationship(
        id: r.id,
        sourceCharacterId: r.sourceCharacterId,
        targetCharacterId: r.targetCharacterId,
        relationType: r.relationType,
        customRelationName: r.customRelationName,
        description: r.description,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      );
    }).toList();

    final options = [
      _option1Ctrl.text.trim(),
      _option2Ctrl.text.trim(),
      _option3Ctrl.text.trim(),
    ].where((s) => s.isNotEmpty).toList();

    final controller = ref.read(adventureSetupControllerProvider);
    final npcCards = controller.npcCards;
    final npcSnapshots = npcCards
        .where((n) => _selectedNpcIds.contains(n['id']?.toString()))
        .map((n) {
      final raw = n['json_data'] ?? n['card_data'];
      Map<String, dynamic> rawMap = {};
      if (raw is Map<String, dynamic>) {
        rawMap = raw;
      } else if (raw is String) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) rawMap = decoded;
        } catch (_) {}
      }
      return AdventureNpcSnapshot(
        assetId: n['id']?.toString() ?? '',
        name: n['name']?.toString() ?? '未命名 NPC',
        originWorldviewId: n['matching_worldview_id']?.toString() ?? '',
        npcJson: rawMap,
      );
    }).toList();

    return AdventureConfig(
      name: protagonist?.name ?? '',
      gender: protagonist?.gender ?? '',
      age: protagonist?.age ?? '',
      protagonistClass: protagonist?.profession ?? '',
      personality: protagonist?.personality ?? '',
      protagonistBackground: protagonist?.background ?? '',
      worldview: _worldviewNameCtrl.text.trim(),
      openingScene: _openingSceneCtrl.text.trim(),
      openingOptions: options,
      selectedCharacters: selectedChars,
      characterRelationships: rels,
      npcSnapshots: npcSnapshots,
    );
  }

  Future<void> _handleStartAdventure() async {
    if (_submitting) return;

    if (_worldviewNameCtrl.text.trim().isEmpty) {
      AppFeedback.info(context, '请设定世界观名称');
      setState(() => _currentPhase = 0);
      return;
    }
    if (_characters.isEmpty) {
      AppFeedback.info(context, '请至少添加一个角色');
      setState(() => _currentPhase = 1);
      return;
    }

    setState(() => _submitting = true);
    try {
      final config = _buildCurrentConfig();
      final gate = ref.read(adventureReadinessGateProvider);
      final frozen = await gate.enforceAndFreeze(config);
      await widget.onStartAdventure(frozen);
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, '启动冒险失败：$e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // --- 导航至全屏选择器与配置页 ---

  Future<void> _navigateToWorldSelection() async {
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
      AppFeedback.success(context, '已选定世界观「${_worldviewNameCtrl.text}」');
    }
  }

  Future<void> _navigateToCharacterSelection() async {
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
        for (final entry in selectedList) {
          if (!_characters.any((c) => c.id == entry.id)) {
            final isFirst = _characters.isEmpty;
            _characters.add(WizardCharacterItem(
              id: entry.id,
              name: entry.name,
              gender: entry.gender,
              age: entry.age,
              profession: entry.profession,
              personality: entry.personality,
              background: entry.background,
              isProtagonist: isFirst,
              narrativeRole: isFirst
                  ? AdventureCharacterRole.protagonist
                  : AdventureCharacterRole.supporting,
              libraryEntry: entry,
              rawJson: entry.rawData,
            ));
          }
        }
        _syncRelationships();
      });
      AppFeedback.success(context, '已更新阵容角色');
    }
  }

  Future<void> _navigateToNpcSelection() async {
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
      AppFeedback.success(context, '已选定 ${_selectedNpcIds.length} 位 NPC');
    }
  }

  Future<void> _navigateToConfigPage() async {
    final result = await AppRouter.push<AssemblyConfigData?>(
      context,
      pageBuilder: (_) => AssemblyConfigPage(
        initialOpeningScene: _openingSceneCtrl.text,
        initialOptions: [
          _option1Ctrl.text,
          _option2Ctrl.text,
          _option3Ctrl.text,
        ],
        initialPrompt: _promptCtrl.text,
        initialDifficulty: _difficulty,
        worldviewName: _worldviewNameCtrl.text,
        protagonistName:
            _characters.where((c) => c.isProtagonist).firstOrNull?.name,
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
        _promptCtrl.text = result.customPrompt;
        _difficulty = result.difficulty;
      });
      AppFeedback.success(context, '序章配置已保存');
    }
  }

  Future<void> _navigateToPreviewPage() async {
    await AppRouter.push<void>(
      context,
      pageBuilder: (_) => AssemblyPreviewPage(
        config: _buildCurrentConfig(),
        worldviewDesc: _worldviewDescCtrl.text,
        onStartAdventure: widget.onStartAdventure,
        onEditWorldview: () {
          Navigator.of(context).pop();
          setState(() => _currentPhase = 0);
        },
        onEditCharacters: () {
          Navigator.of(context).pop();
          setState(() => _currentPhase = 1);
        },
        onEditConfig: () {
          Navigator.of(context).pop();
          setState(() => _currentPhase = 2);
        },
      ),
    );
  }

  Future<void> _openNewCharacterEditor() async {
    final savedDraft = await showCreateCharacterCardDialog(
      context,
      defaultMatchingWorldviewId: _selectedWorldviewId,
      mode: ResourceLibraryMode.adventure,
    );

    if (savedDraft != null && mounted) {
      await ref.read(adventureSetupControllerProvider).loadInitialData();
      final id =
          savedDraft.id ?? DateTime.now().millisecondsSinceEpoch.toString();
      setState(() {
        final isFirst = _characters.isEmpty;
        _characters.add(WizardCharacterItem(
          id: id,
          name: savedDraft.name,
          gender: savedDraft.isCustomGender
              ? savedDraft.customGender
              : savedDraft.gender,
          age: savedDraft.age,
          profession: savedDraft.profession,
          personality: savedDraft.personality,
          background: savedDraft.description,
          isProtagonist: isFirst,
          narrativeRole: isFirst
              ? AdventureCharacterRole.protagonist
              : AdventureCharacterRole.supporting,
        ));
        _syncRelationships();
      });
      if (!mounted) return;
      AppFeedback.success(context, '角色「${savedDraft.name}」已加入队伍');
    }
  }

  // --- UI 构建 ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppPageScaffold(
      title: '冒险装配流水线',
      titleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('冒险装配流水线', style: theme.textTheme.titleMedium),
          Text(
            '步骤推进 · 页面化资源组装 · 零弹窗约束',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      bottomBar: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              if (_currentPhase > 0) ...[
                OutlinedButton(
                  key: const Key('assembly-prev-phase-button'),
                  onPressed: () => setState(() => _currentPhase -= 1),
                  child: const Text('上一步'),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              const Spacer(),
              if (_currentPhase < 3)
                AppPrimaryButton(
                  key: const Key('assembly-next-phase-button'),
                  label: '下一步：${_phaseTitles[_currentPhase + 1]}',
                  onPressed: () {
                    if (_currentPhase == 0 &&
                        _worldviewNameCtrl.text.trim().isEmpty) {
                      AppFeedback.info(context, '请设定世界观名称');
                      return;
                    }
                    if (_currentPhase == 1 && _characters.isEmpty) {
                      AppFeedback.info(context, '请至少添加一个角色');
                      return;
                    }
                    setState(() => _currentPhase += 1);
                  },
                )
              else
                AppPrimaryButton(
                  key: const Key('assembly-start-adventure-button'),
                  label: '踏入冒险',
                  isLoading: _submitting,
                  onPressed: _submitting ? null : _handleStartAdventure,
                ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // 阶段进度指示条
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            color: scheme.surfaceContainerLowest,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(_phaseTitles.length, (idx) {
                  final isActive = idx == _currentPhase;
                  final isDone = idx < _currentPhase;

                  return InkWell(
                    onTap: () => setState(() => _currentPhase = idx),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: isActive
                            ? scheme.primaryContainer
                            : (isDone
                                ? scheme.surfaceContainerHigh
                                : Colors.transparent),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isDone
                                ? Icons.check_circle
                                : (isActive
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked),
                            size: 16,
                            color: isActive
                                ? scheme.primary
                                : (isDone
                                    ? scheme.outline
                                    : scheme.outlineVariant),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${idx + 1}. ${_phaseTitles[idx]}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isActive
                                  ? scheme.onPrimaryContainer
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          const Divider(height: 1),

          // 核心阶段视图
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: switch (_currentPhase) {
                0 => _buildWorldviewPhase(theme, scheme),
                1 => _buildCharacterPhase(theme, scheme),
                2 => _buildOpeningPhase(theme, scheme),
                3 => _buildPreviewPhase(theme, scheme),
                _ => const SizedBox.shrink(),
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- Phase 1: 世界设定 ---
  Widget _buildWorldviewPhase(ThemeData theme, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部操作卡片：选择资料库世界观
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.public_rounded, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '世界观资料库关联',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    key: const Key('assembly-open-world-selection-button'),
                    onPressed: _navigateToWorldSelection,
                    icon: const Icon(Icons.travel_explore_rounded, size: 16),
                    label: const Text('从资料库选择'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _selectedWorldviewId != null
                    ? '已绑定资料库世界观 ID: $_selectedWorldviewId'
                    : '未绑定预设，亦可直接在下方填写自定义世界设定。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // 世界观表单
        AppFormSection(
          title: '世界观设定详情',
          description: '设定大陆法则、地理背景、文明程度与势力格局。',
          child: Column(
            children: [
              AppTextField(
                key: const Key('assembly-worldview-name-input'),
                controller: _worldviewNameCtrl,
                label: '世界名称 *',
                hintText: '例如：艾尔登大陆、赛博新都 2099、修真古界...',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入世界名称' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                key: const Key('assembly-worldview-desc-input'),
                controller: _worldviewDescCtrl,
                label: '法则与背景设定',
                hintText: '描述世界的魔法与科技体系、天体气候、阵营势力格局...',
                maxLines: 4,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Phase 2: 角色阵容与羁绊 ---
  Widget _buildCharacterPhase(ThemeData theme, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部操作卡片：选择角色与 NPC
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.groups_rounded, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '角色与 NPC 装配',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  FilledButton.tonalIcon(
                    key: const Key('assembly-open-character-selection-button'),
                    onPressed: _navigateToCharacterSelection,
                    icon: const Icon(Icons.person_search_rounded, size: 16),
                    label: const Text('从资料库选择角色'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('assembly-open-npc-selection-button'),
                    onPressed: _navigateToNpcSelection,
                    icon: const Icon(Icons.record_voice_over_rounded, size: 16),
                    label: Text('选择 NPC (${_selectedNpcIds.length})'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _openNewCharacterEditor,
                    icon: const Icon(Icons.person_add_rounded, size: 16),
                    label: const Text('新建角色'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // 已选角色阵容列表
        AppFormSection(
          title: '登场角色阵容 (${_characters.length})',
          description: '必须勾选 1 位作为主控主角；其他角色可赋予同伴、反派、导师等身份定位。',
          child: _characters.isEmpty
              ? Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.groups_outlined,
                          size: 36,
                          color: scheme.outline,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '尚未添加登场角色',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '点击上方「从资料库选择角色」或「新建角色」',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: _characters.map((c) {
                    final roleOptions =
                        AdventureCharacterRole.labels.entries.toList();

                    return Container(
                      key: Key('assembly-character-card-${c.id}'),
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: c.isProtagonist
                            ? scheme.primaryContainer.withValues(alpha: 0.2)
                            : scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: c.isProtagonist
                              ? scheme.primary.withValues(alpha: 0.6)
                              : scheme.outlineVariant.withValues(alpha: 0.5),
                          width: c.isProtagonist ? 1.5 : 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: c.isProtagonist
                                    ? scheme.primary
                                    : scheme.surfaceContainerHighest,
                                child: Icon(
                                  c.isProtagonist
                                      ? Icons.star_rounded
                                      : Icons.person_rounded,
                                  size: 16,
                                  color: c.isProtagonist
                                      ? scheme.onPrimary
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${c.name}${c.profession.isNotEmpty ? " · ${c.profession}" : ""}',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Checkbox(
                                value: c.isProtagonist,
                                onChanged: (val) {
                                  setState(() {
                                    for (final other in _characters) {
                                      other.isProtagonist = (other.id == c.id);
                                      if (other.isProtagonist) {
                                        other.narrativeRole =
                                            AdventureCharacterRole.protagonist;
                                      }
                                    }
                                  });
                                },
                              ),
                              Text(
                                '设为主控主角',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  setState(() {
                                    _characters
                                        .removeWhere((item) => item.id == c.id);
                                    if (c.isProtagonist &&
                                        _characters.isNotEmpty) {
                                      _characters.first.isProtagonist = true;
                                    }
                                    _syncRelationships();
                                  });
                                },
                              ),
                            ],
                          ),
                          if (!c.isProtagonist) ...[
                            const SizedBox(height: AppSpacing.xs),
                            AppSelect<String>(
                              label: '剧本身份定位',
                              value: c.narrativeRole,
                              items: roleOptions
                                  .map((r) => AppSelectItem(
                                        value: r.key,
                                        label: r.value,
                                      ))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => c.narrativeRole = val);
                                }
                              },
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  // --- Phase 3: 序章分支与配置 ---
  Widget _buildOpeningPhase(ThemeData theme, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Row(
            children: [
              Icon(Icons.tune_rounded, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '序章与规则高级配置',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                key: const Key('assembly-open-config-page-button'),
                onPressed: _navigateToConfigPage,
                icon: const Icon(Icons.fullscreen_rounded, size: 16),
                label: const Text('全屏高级配置'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppFormSection(
          title: '序章剧情内容',
          description: '冒险开始的第一幕场景描写。',
          child: AppTextField(
            key: const Key('assembly-opening-scene-input'),
            controller: _openingSceneCtrl,
            hintText: '描述主角登场时刻的环境与转折...',
            maxLines: 4,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppFormSection(
          title: '开场行动抉择分支 (可选)',
          description: '供玩家在序章结束时选择的行动方向。',
          child: Column(
            children: [
              AppTextField(
                key: const Key('assembly-option-1-input'),
                controller: _option1Ctrl,
                label: '分支 1',
                hintText: '行动选项 1...',
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                key: const Key('assembly-option-2-input'),
                controller: _option2Ctrl,
                label: '分支 2',
                hintText: '行动选项 2...',
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                key: const Key('assembly-option-3-input'),
                controller: _option3Ctrl,
                label: '分支 3',
                hintText: '行动选项 3...',
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Phase 4: 装配总览与启程 ---
  Widget _buildPreviewPhase(ThemeData theme, ColorScheme scheme) {
    final protagonist = _characters.where((c) => c.isProtagonist).firstOrNull;
    final otherCharacters = _characters.where((c) => !c.isProtagonist).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Row(
            children: [
              Icon(Icons.visibility_rounded, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '进入独立全屏大预览',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                key: const Key('assembly-open-preview-page-button'),
                onPressed: _navigateToPreviewPage,
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('全屏预览'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // 概要卡片
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('世界观设定', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                _worldviewNameCtrl.text.isNotEmpty
                    ? _worldviewNameCtrl.text
                    : '自定义未命名世界',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Divider(height: 20),
              Text('主控主角', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                protagonist != null
                    ? '${protagonist.name} (${protagonist.profession.isNotEmpty ? protagonist.profession : "冒险者"})'
                    : '未指定主角',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (otherCharacters.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '同伴阵容: ${otherCharacters.map((c) => "${c.name}[${c.effectiveRole}]").join("、")}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (_selectedNpcIds.isNotEmpty) ...[
                const Divider(height: 20),
                Text('常驻 NPC', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  '已选定 ${_selectedNpcIds.length} 位初始 NPC',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const Divider(height: 20),
              Text('序章第一幕', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                _openingSceneCtrl.text.isNotEmpty
                    ? _openingSceneCtrl.text
                    : '由 AI 结合背景自动展开',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
