import "../core/theme/app_colors.dart";
import '../core/feedback/app_feedback.dart';
import '../core/widgets/form_sub_page_scaffold.dart';
import '../core/widgets/narr_aitor_dropdown.dart';
import '../widgets/narr_aitor_loading.dart';
import '../core/utils/worldview_character_scope_policy.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import '../providers/riverpod_providers.dart';
import '../models/adventure_config.dart';
import '../models/supporting_character.dart';
import '../models/character_card.dart';
import '../models/character_card_entry.dart';
import '../controllers/adventure_setup_controller.dart';
import '../application/prompt_policies/adventure_context_policy.dart';
import 'chat/widgets/ai_generate_section.dart';
import 'adventure_manual_subpages.dart';

class AdventureBuilder extends ConsumerStatefulWidget {
  final Future<void> Function(AdventureConfig config) onStartAdventure;
  final AdventureConfig? initialConfig;
  final int reloadTrigger; // 父组件递增此值触发数据重新加载

  const AdventureBuilder(
      {super.key,
      required this.onStartAdventure,
      this.initialConfig,
      this.reloadTrigger = 0});

  @override
  ConsumerState<AdventureBuilder> createState() => _AdventureBuilderState();
}

class _AdventureBuilderState extends ConsumerState<AdventureBuilder> {
  List<Map<String, dynamic>> _worldviewPresets = [];
  List<Map<String, dynamic>> _characterCards = [];
  bool _loading = true;
  int _lastReloadTrigger = 0;

  String? _selWorldviewId;
  String _worldviewDesc = '';
  final List<TextEditingController> _manualWvNameCtrls = [];
  final List<TextEditingController> _manualWvDescCtrls = [];

  final List<AdventureSelectedCharacter> _selectedCharacters = [];
  final List<AdventureCharacterRelationship> _characterRelationships = [];
  bool _relationshipsExpanded = true;
  final List<TextEditingController> _manualCardNameCtrls = [];
  final List<String> _manualCardGenders = [];
  final List<TextEditingController> _manualCardAgeCtrls = [];
  final List<TextEditingController> _manualCardProfCtrls = [];
  final List<TextEditingController> _manualCardPersonCtrls = [];
  final List<TextEditingController> _manualCardBgCtrls = [];
  final List<TextEditingController> _manualCardAppearCtrls = [];
  final List<SupportingCharacter> _npcs = [];
  final List<TextEditingController> _npcNameCtrls = [];
  final List<TextEditingController> _npcRelCtrls = [];
  final List<TextEditingController> _npcPersCtrls = [];
  final List<String> _npcGenders = [];
  final List<TextEditingController> _npcRoleCtrls = [];

  late TextEditingController _openingSceneCtrl;
  late TextEditingController _openingOptionsCtrl;

  bool _showPreview = false;
  bool _isStartingAdventure = false;
  int _currentStep = 0;
  static const _stepLabels = ['世界观', '角色卡', 'NPC配角', '开场设置', '确认'];
  static const _stepCount = 5;

  // ─── NPC AI 批量生成状态 ───
  final _npcGenCtrl = TextEditingController();
  bool _npcGenLoading = false;
  bool _npcGenExpanded = false;
  List<Map<String, String>>? _npcGenResult;
  String? _npcGenError;
  // NPC 关联角色多选（可选）
  final Set<String> _npcAssociatedIds = {};

  // ─── 开场场景 AI 生成状态 ───
  final _openingGenCtrl = TextEditingController();
  bool _openingGenLoading = false;
  bool _openingGenExpanded = false;
  Map<String, String>? _openingGenResult;
  String? _openingGenError;

  @override
  void initState() {
    super.initState();
    _openingSceneCtrl = TextEditingController();
    _openingOptionsCtrl = TextEditingController();
    _applyInitialConfig();
    // 延迟到首帧后，避免在 build 期间修改 ChangeNotifierProvider 状态。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadData();
    });
  }

  void _applyInitialConfig() {
    final cfg = widget.initialConfig;
    if (cfg == null) return;
    _selWorldviewId = WorldviewCharacterScopePolicy.stableId(
        cfg.worldviewSnapshot?['source_id']);
    if (cfg.worldview.isNotEmpty) {
      _worldviewDesc = cfg.worldview;
    }
    if (cfg.openingScene.isNotEmpty) _openingSceneCtrl.text = cfg.openingScene;
    if (cfg.openingOptions.isNotEmpty) {
      _openingOptionsCtrl.text = cfg.openingOptions.join(', ');
    }
    if (cfg.selectedCharacters.isNotEmpty) {
      _selectedCharacters
        ..clear()
        ..addAll(cfg.selectedCharacters.map((c) {
          return AdventureSelectedCharacter.fromJson(c.toJson());
        }));
      _normalizeSelectedCharacters();
    } else if (cfg.characterCard != null || cfg.name.isNotEmpty) {
      final id = cfg.characterCard?.name ?? 'legacy_protagonist';
      _selectedCharacters.add(AdventureSelectedCharacter(
        id: id,
        characterId: id,
        characterName: cfg.name.isNotEmpty ? cfg.name : cfg.characterCard!.name,
        isProtagonist: true,
        narrativeRole: AdventureCharacterRole.protagonist,
        characterCardJson: cfg.characterCard?.toJson(),
      ));
    }
    _characterRelationships
      ..clear()
      ..addAll(cfg.characterRelationships.map((r) {
        return AdventureCharacterRelationship.fromJson(r.toJson());
      }));
    _syncRelationshipPairs();
    if (cfg.supportingCharacters.isNotEmpty) {
      for (final sc in cfg.supportingCharacters) {
        _npcs.add(sc);
        _npcNameCtrls.add(TextEditingController(text: sc.name));
        _npcRelCtrls.add(TextEditingController(text: sc.relation));
        _npcPersCtrls.add(TextEditingController(text: sc.personality));
        _npcGenders.add(sc.gender);
        _npcRoleCtrls.add(TextEditingController(text: sc.role));
      }
    }
  }

  @override
  void didUpdateWidget(AdventureBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 父组件切换 tab 时递增 reloadTrigger，触发数据刷新
    if (widget.reloadTrigger != _lastReloadTrigger) {
      _lastReloadTrigger = widget.reloadTrigger;
      _loadData();
    }
  }

  @override
  void dispose() {
    _openingSceneCtrl.dispose();
    _openingOptionsCtrl.dispose();
    _npcGenCtrl.dispose();
    _openingGenCtrl.dispose();
    for (final c in _manualWvNameCtrls) {
      c.dispose();
    }
    for (final c in _manualWvDescCtrls) {
      c.dispose();
    }
    for (final c in _manualCardNameCtrls) {
      c.dispose();
    }
    for (final c in _manualCardAgeCtrls) {
      c.dispose();
    }
    for (final c in _manualCardProfCtrls) {
      c.dispose();
    }
    for (final c in _manualCardPersonCtrls) {
      c.dispose();
    }
    for (final c in _manualCardBgCtrls) {
      c.dispose();
    }
    for (final c in _manualCardAppearCtrls) {
      c.dispose();
    }
    for (final c in _npcNameCtrls) {
      c.dispose();
    }
    for (final c in _npcRelCtrls) {
      c.dispose();
    }
    for (final c in _npcPersCtrls) {
      c.dispose();
    }
    for (final c in _npcRoleCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final setupController = ref.read(adventureSetupControllerProvider);
      await setupController.loadInitialData();
      final worldviews = setupController.worldviewPresets;
      final cards = setupController.characterCards;
      if (mounted) {
        setState(() {
          _worldviewPresets = worldviews;
          _characterCards = cards;
          _reconcileCharacterScopeAfterWorldviewChange();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  AdventureSetupController get _setup =>
      ref.read(adventureSetupControllerProvider);

  List<Map<String, dynamic>> get _availableCharacterCards =>
      WorldviewCharacterScopePolicy.filterSceneResources(
        _characterCards,
        _selWorldviewId,
      );

  List<CharacterCardEntry> get _availableCardEntries =>
      _setup.scopedCharacterCardEntries(_selWorldviewId);

  void _selectWorldview(Map<String, dynamic> worldview) {
    setState(() {
      _selWorldviewId = WorldviewCharacterScopePolicy.stableId(worldview['id']);
      _worldviewDesc = worldview['description']?.toString() ?? '';
      _reconcileCharacterScopeAfterWorldviewChange();
    });
  }

  /// Removes only current-flow references that are no longer in the selected
  /// worldview scope. The underlying library cache and database stay intact.
  void _reconcileCharacterScopeAfterWorldviewChange() {
    final allowedIds = _availableCharacterCards
        .map((card) => card['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty);
    final retainedIds =
        WorldviewCharacterScopePolicy.reconcileSelectedCharacterIds(
      _selectedCharacters.map((character) => character.characterId),
      allowedIds,
    );
    final retainedCharacters = _selectedCharacters
        .where((character) => retainedIds.contains(character.characterId))
        .toList(growable: false);
    if (retainedCharacters.length != _selectedCharacters.length) {
      debugPrint('[Builder] 已清理当前世界观外的角色选择');
      _selectedCharacters
        ..clear()
        ..addAll(retainedCharacters);
    }
    final allowedNpcAssociations =
        WorldviewCharacterScopePolicy.reconcileSelectedCharacterIds(
            _npcAssociatedIds, allowedIds);
    _npcAssociatedIds
      ..clear()
      ..addAll(allowedNpcAssociations);
    _normalizeSelectedCharacters();
    _syncRelationshipPairs();
  }

  double get _progress {
    int done = 0;
    const total = 5;
    if (_selWorldviewId != null) done++;
    if (_selectedCharacters.isNotEmpty || _manualCardNameCtrls.isNotEmpty) {
      done++;
    }
    if (_npcs.isNotEmpty) done++;
    if (_openingSceneCtrl.text.trim().isNotEmpty) done++;
    if (_openingOptionsCtrl.text.trim().isNotEmpty) done++;
    return done / total;
  }

  Map<String, String> _buildCharacterContext() {
    return AdventureContextPolicy.buildCharacterContext(
      protagonistBinding: _protagonistBinding,
      characterCards: _characterCards,
      manualName: _manualCardNameCtrls.isNotEmpty
          ? _manualCardNameCtrls[0].text.trim()
          : '',
      manualAge: _manualCardAgeCtrls.isNotEmpty
          ? _manualCardAgeCtrls[0].text.trim()
          : '',
      manualRole: _manualCardProfCtrls.isNotEmpty
          ? _manualCardProfCtrls[0].text.trim()
          : '',
      manualPersonality: _manualCardPersonCtrls.isNotEmpty
          ? _manualCardPersonCtrls[0].text.trim()
          : '',
      manualBackground: _manualCardBgCtrls.isNotEmpty
          ? _manualCardBgCtrls[0].text.trim()
          : '',
      manualAppearance: _manualCardAppearCtrls.isNotEmpty
          ? _manualCardAppearCtrls[0].text.trim()
          : '',
    );
  }

  List<Map<String, String>> _buildSelectedCharacterContexts() {
    return _selectedCharacters.map((character) {
      final data = character.characterCardJson ?? const <String, dynamic>{};
      final cardData = data['data'] is Map<String, dynamic>
          ? data['data'] as Map<String, dynamic>
          : data;
      final bodyDescription = _readCardText(cardData, const [
        'bodyDescription',
        'body_description',
        'physique',
        'figureDescription',
        'bodyShape',
        'bodyType',
        'physicalDescription',
        'appearanceDetail',
        'lookDescription',
      ]);
      return <String, String>{
        'name': character.characterName,
        'role': character.effectiveRole,
        'customRoleName': character.customRoleName,
        'isProtagonist': character.isProtagonist.toString(),
        'personality': (cardData['personality'] as String?) ?? '',
        'background': (cardData['background'] as String?) ??
            (cardData['description'] as String?) ??
            '',
        'bodyDescription': bodyDescription,
        'appearance': (cardData['appearance'] as String?) ?? '',
        'sortOrder': character.sortOrder.toString(),
      };
    }).toList()
      ..sort((a, b) {
        final aFlag = a['isProtagonist'] == 'true';
        final bFlag = b['isProtagonist'] == 'true';
        if (aFlag != bFlag) return aFlag ? -1 : 1;
        final aOrder = int.tryParse(a['sortOrder'] ?? '') ?? 0;
        final bOrder = int.tryParse(b['sortOrder'] ?? '') ?? 0;
        return aOrder.compareTo(bOrder);
      });
  }

  List<Map<String, String>> _buildCharacterRelationshipContexts() {
    final nameById = {
      for (final character in _selectedCharacters)
        character.characterId: character.characterName,
    };
    return _characterRelationships
        .where((relation) =>
            relation.sourceCharacterId.isNotEmpty &&
            relation.targetCharacterId.isNotEmpty)
        .map((relation) => <String, String>{
              'sourceName': nameById[relation.sourceCharacterId] ??
                  relation.sourceCharacterId,
              'targetName': nameById[relation.targetCharacterId] ??
                  relation.targetCharacterId,
              'relationType': relation.effectiveRelation,
              'description': relation.description,
            })
        .toList();
  }

  /// 聚合手动输入的世界观文本（用于预设保存）
  String _buildManualWorldviewText() {
    final buf = StringBuffer();
    for (int i = 0; i < _manualWvNameCtrls.length; i++) {
      final n = _manualWvNameCtrls[i].text.trim();
      final d = _manualWvDescCtrls[i].text.trim();
      if (n.isNotEmpty) buf.writeln('【$n】');
      if (d.isNotEmpty) buf.writeln(d);
    }
    return buf.toString().trim();
  }

  String _readCardText(Map<String, dynamic> data, List<String> keys) {
    final nested = data['data'];
    if (nested is Map<String, dynamic>) {
      for (final key in keys) {
        final value = nested[key];
        if (value == null) continue;
        final text = value.toString().trim();
        if (text.isNotEmpty) return text;
      }
    }
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  /// 聚合当前已选择的世界观描述（预设 + 手动输入），供 AI 生成角色/NPC/开场时使用
  String get _currentWorldviewDesc {
    // 优先使用选中的预设世界观
    if (_selWorldviewId != null && _worldviewDesc.isNotEmpty) {
      return _worldviewDesc;
    }
    // 否则从手动输入的字段聚合
    final buf = StringBuffer();
    for (int i = 0; i < _manualWvNameCtrls.length; i++) {
      final n = _manualWvNameCtrls[i].text.trim();
      final d = _manualWvDescCtrls[i].text.trim();
      if (n.isNotEmpty) buf.writeln('【$n】');
      if (d.isNotEmpty) buf.writeln(d);
    }
    return buf.toString().trim();
  }

  Future<void> _addManualWorldview() async {
    final result = await showAdventureManualWorldviewPage(context);
    if (!mounted || result == null) return;
    _appendManualWorldview(result);
  }

  void _appendManualWorldview(Map<String, String> result) {
    setState(() {
      // A manually entered worldview has no stable library ID. Keep its local
      // characters available, but do not retain cards selected for a prior
      // library worldview.
      _selWorldviewId = null;
      _worldviewDesc = '';
      _manualWvNameCtrls.add(TextEditingController());
      _manualWvDescCtrls.add(TextEditingController());
      final index = _manualWvNameCtrls.length - 1;
      _manualWvNameCtrls[index].text = result['name'] ?? '';
      _manualWvDescCtrls[index].text = result['description'] ?? '';
      _reconcileCharacterScopeAfterWorldviewChange();
    });
  }

  void _removeManualWorldview(int i) {
    setState(() {
      _manualWvNameCtrls[i].dispose();
      _manualWvDescCtrls[i].dispose();
      _manualWvNameCtrls.removeAt(i);
      _manualWvDescCtrls.removeAt(i);
    });
  }

  Future<void> _addManualCard() async {
    final result = await showAdventureManualCharacterPage(context);
    if (!mounted || result == null) return;
    _appendManualCard(result);
  }

  void _appendManualCard(Map<String, String> result) {
    setState(() {
      _manualCardNameCtrls.add(TextEditingController());
      _manualCardGenders.add('女');
      _manualCardAgeCtrls.add(TextEditingController());
      _manualCardProfCtrls.add(TextEditingController());
      _manualCardPersonCtrls.add(TextEditingController());
      _manualCardBgCtrls.add(TextEditingController());
      _manualCardAppearCtrls.add(TextEditingController());
      final index = _manualCardNameCtrls.length - 1;
      _manualCardNameCtrls[index].text = result['name'] ?? '';
      _manualCardGenders[index] = result['gender'] ?? '女';
      _manualCardAgeCtrls[index].text = result['age'] ?? '';
      _manualCardProfCtrls[index].text = result['profession'] ?? '';
      _manualCardPersonCtrls[index].text = result['personality'] ?? '';
      _manualCardBgCtrls[index].text = result['background'] ?? '';
      _manualCardAppearCtrls[index].text = result['appearance'] ?? '';
    });
  }

  void _removeManualCard(int i) {
    setState(() {
      _manualCardNameCtrls[i].dispose();
      _manualCardAgeCtrls[i].dispose();
      _manualCardProfCtrls[i].dispose();
      _manualCardPersonCtrls[i].dispose();
      _manualCardBgCtrls[i].dispose();
      _manualCardAppearCtrls[i].dispose();
      _manualCardNameCtrls.removeAt(i);
      _manualCardGenders.removeAt(i);
      _manualCardAgeCtrls.removeAt(i);
      _manualCardProfCtrls.removeAt(i);
      _manualCardPersonCtrls.removeAt(i);
      _manualCardBgCtrls.removeAt(i);
      _manualCardAppearCtrls.removeAt(i);
    });
  }

  AdventureSelectedCharacter? get _protagonistBinding {
    for (final character in _selectedCharacters) {
      if (character.isProtagonist) return character;
    }
    return _selectedCharacters.isNotEmpty ? _selectedCharacters.first : null;
  }

  AdventureSelectedCharacter _bindingFromEntry(CharacterCardEntry entry) {
    final data = Map<String, dynamic>.from(entry.rawData);
    final worldviewId = entry.matchingWorldviewId ?? '';
    if (worldviewId.isNotEmpty) {
      data['worldview_binding'] = {
        'resource_id': worldviewId,
        'snapshot_worldview_id': _selWorldviewId ?? '',
      };
    }
    final id = entry.id.isNotEmpty ? entry.id : entry.name;
    final name = entry.name.isEmpty ? '未命名角色' : entry.name;
    final first = _selectedCharacters.isEmpty;
    return AdventureSelectedCharacter(
      id: id,
      characterId: id,
      characterName: name,
      isProtagonist: first,
      narrativeRole: first
          ? AdventureCharacterRole.protagonist
          : AdventureCharacterRole.companion,
      sortOrder: _selectedCharacters.length,
      characterCardJson: data,
    );
  }

  void _toggleCharacterCard(CharacterCardEntry entry) {
    final id = entry.id;
    if (id.isEmpty) return;
    setState(() {
      final existingIndex =
          _selectedCharacters.indexWhere((c) => c.characterId == id);
      if (existingIndex >= 0) {
        final wasProtagonist = _selectedCharacters[existingIndex].isProtagonist;
        _selectedCharacters.removeAt(existingIndex);
        if (wasProtagonist && _selectedCharacters.isNotEmpty) {
          _selectedCharacters.first.isProtagonist = true;
        }
      } else {
        _selectedCharacters.add(_bindingFromEntry(entry));
      }
      _normalizeSelectedCharacters();
      _syncRelationshipPairs();
    });
  }

  void _removeSelectedCharacter(String id) {
    setState(() {
      final wasProtagonist = _selectedCharacters
          .where((c) => c.characterId == id)
          .any((c) => c.isProtagonist);
      _selectedCharacters.removeWhere((c) => c.characterId == id);
      if (wasProtagonist && _selectedCharacters.isNotEmpty) {
        _selectedCharacters.first.isProtagonist = true;
      }
      _normalizeSelectedCharacters();
      _syncRelationshipPairs();
    });
  }

  void _setProtagonist(String id) {
    setState(() {
      for (final character in _selectedCharacters) {
        character.isProtagonist = character.characterId == id;
        character.updatedAt = DateTime.now().toIso8601String();
      }
    });
  }

  void _normalizeSelectedCharacters() {
    if (_selectedCharacters.isEmpty) {
      return;
    }
    var seen = false;
    for (var i = 0; i < _selectedCharacters.length; i++) {
      final character = _selectedCharacters[i];
      character.sortOrder = i;
      if (character.isProtagonist && !seen) {
        seen = true;
      } else if (character.isProtagonist) {
        character.isProtagonist = false;
      }
    }
    if (!seen) _selectedCharacters.first.isProtagonist = true;
  }

  void _syncRelationshipPairs() {
    final ids = _selectedCharacters.map((c) => c.characterId).toList();
    _characterRelationships.removeWhere((r) =>
        !ids.contains(r.sourceCharacterId) ||
        !ids.contains(r.targetCharacterId));
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final id = AdventureCharacterRelationship.stableId(ids[i], ids[j]);
        if (_characterRelationships.any((r) => r.id == id)) continue;
        _characterRelationships.add(AdventureCharacterRelationship(
          id: id,
          sourceCharacterId: ids[i],
          targetCharacterId: ids[j],
          relationType: AdventureRelationType.unset,
        ));
      }
    }
  }

  String? _validateCharacterSetup() {
    final hasManualCharacter = _manualCardNameCtrls
        .any((controller) => controller.text.trim().isNotEmpty);
    if (_selectedCharacters.isEmpty && !hasManualCharacter) {
      return '请至少选择一个角色。';
    }
    if (_selectedCharacters.isNotEmpty) {
      final protagonists =
          _selectedCharacters.where((c) => c.isProtagonist).length;
      if (protagonists == 0) return '请设置一个主角。';
      if (protagonists > 1) return '主角只能有一个。';
      for (final character in _selectedCharacters) {
        if (character.narrativeRole == AdventureCharacterRole.custom &&
            character.customRoleName.trim().isEmpty) {
          return '请输入自定义身份。';
        }
      }
      for (final relation in _characterRelationships) {
        if (relation.relationType == AdventureRelationType.custom &&
            relation.customRelationName.trim().isEmpty) {
          return '请输入自定义关系名称。';
        }
      }
    }
    return null;
  }

  bool _guardCharacterSetup() {
    final error = _validateCharacterSetup();
    if (error == null) return true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    return false;
  }

  // ─── AI 生成 ───

  bool get _isVisionModel {
    try {
      final p = ref.read(chatProvider);
      final model = p.modelName.toLowerCase();
      for (final k in ['vl-', 'vl_', 'vision', 'llava', '4v', 'minicpm-v']) {
        if (model.contains(k)) return true;
      }
      if (model == 'deepseek-v4' && !model.contains('flash')) return true;
    } catch (_) {}
    return false;
  }

  void _onAiFillWorldview(Map<String, String> r) {
    _appendManualWorldview(r);
  }

  void _onAiFillCharacterCard(Map<String, String> r) {
    _appendManualCard(r);
  }

  Future<void> _onAiSaveWorldview(Map<String, String> r) async {
    final result =
        await ref.read(resourceCrudControllerProvider).saveWorldviewPreset(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              name: r['name'] ?? 'AI生成的世界观',
              description: r['description'] ?? '',
              entriesJson: '[]',
              now: DateTime.now().toIso8601String(),
              source: 'AI生成',
              // AI 生成的短描述保持现状不做字数完整性校验。
              validate: false,
            );
    if (!result.success) {
      debugPrint('[Builder] 保存世界观失败: ${result.errorMessage}');
      if (mounted) {
        AppFeedback.error(context, '保存世界观失败: ${result.errorMessage}');
      }
      return;
    }
    await ref
        .read(chatProvider)
        .adventureProvider
        .worldMgr
        .loadWorldviewPresets()
        .catchError((e) => debugPrint('[Builder] 加载世界观预设失败: $e'));
    _loadData();
  }

  Future<void> _onAiSaveCharacterCard(Map<String, String> r) async {
    if (_selWorldviewId == null) {
      debugPrint('[Builder] 未选择资料库世界观，跳过角色卡持久化');
      return;
    }
    Map<String, dynamic> worldProfile = {};
    try {
      worldProfile = Map<String, dynamic>.from(
        jsonDecode(r['world_profile'] ?? '{}') as Map,
      );
    } catch (_) {}
    final jsonData = jsonEncode({
      'name': r['name'],
      'gender': r['gender'],
      'age': r['age'],
      'profession': r['profession'],
      'personality': r['personality'],
      'description': r['background'],
      'appearance': r['appearance'],
      'world_profile': worldProfile,
    });
    final result =
        await ref.read(resourceCrudControllerProvider).saveCharacterCard(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              name: r['name'] ?? 'AI生成的角色',
              jsonData: jsonData,
              source: 'AI生成',
              now: DateTime.now().toIso8601String(),
              matchingWorldviewId: _selWorldviewId ?? '',
            );
    if (!result.success) {
      debugPrint('[Builder] 保存角色卡失败: ${result.errorMessage}');
      if (mounted) {
        AppFeedback.error(context, '保存角色卡失败: ${result.errorMessage}');
      }
      return;
    }
    // controller 的 onLibraryChanged 已刷新角色卡缓存。
    _loadData();
  }

  /// AI 批量生成 NPC
  Future<void> _generateNpcs() async {
    final pref = _npcGenCtrl.text.trim();
    if (pref.isEmpty) {
      setState(() => _npcGenError = '请输入 NPC 偏好描述');
      return;
    }
    setState(() {
      _npcGenLoading = true;
      _npcGenError = null;
      _npcGenResult = null;
    });

    try {
      final worldview = _currentWorldviewDesc;
      final ctx = _buildCharacterContext();

      _syncNpcsFromControllers();
      final existingNpcs = _npcs
          .where((n) => n.name.isNotEmpty)
          .map((n) => {
                'name': n.name,
                'role': n.role,
              })
          .toList();

      // 提取选中关联角色的完整字段
      final associatedCharacters = <Map<String, String>>[];
      for (final id in _npcAssociatedIds) {
        final entry =
            _availableCardEntries.where((e) => e.id == id).firstOrNull;
        if (entry != null) {
          associatedCharacters.add(entry.toAssociatedMap());
        }
      }

      final aiController = ref.read(adventureAiControllerProvider);
      final npcs = await aiController.generateNpcs(
        userPrompt: pref,
        worldview: worldview,
        protagonistName: ctx['name']!,
        protagonistRole: ctx['role']!,
        protagonistPersonality: ctx['personality']!,
        protagonistBackground: ctx['background']!,
        protagonistBodyDescription: ctx['bodyDescription']!,
        protagonistAppearance: ctx['appearance']!,
        selectedCharacters: _buildSelectedCharacterContexts(),
        characterRelationships: _buildCharacterRelationshipContexts(),
        existingNpcs: existingNpcs,
        associatedCharacters: associatedCharacters,
      );

      if (!mounted) return;
      if (npcs.isEmpty) {
        setState(() {
          _npcGenLoading = false;
          _npcGenError = 'AI 未能生成有效 NPC，请调整描述后重试';
        });
        return;
      }

      setState(() {
        _npcGenLoading = false;
        _npcGenResult = npcs;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _npcGenLoading = false;
        final msg = e.toString().split('\n').first;
        if (msg.contains('timeout') || msg.contains('Timeout')) {
          _npcGenError = 'AI 响应超时，请检查网络后重试';
        } else if (msg.contains('401') || msg.contains('403')) {
          _npcGenError = 'API Key 无效，请检查设置';
        } else {
          _npcGenError = '生成失败: $msg';
        }
      });
    }
  }

  /// AI 生成开场场景和选项
  Future<void> _generateOpening() async {
    final pref = _openingGenCtrl.text.trim();
    setState(() {
      _openingGenLoading = true;
      _openingGenError = null;
      _openingGenResult = null;
    });

    try {
      final worldview = _currentWorldviewDesc;
      final ctx = _buildCharacterContext();

      // 同步 NPC 控制器并构建 NPC 上下文（第二优先级 - 角色卡+NPC）
      _syncNpcsFromControllers();
      final npcs = _npcs
          .where((n) => n.name.isNotEmpty)
          .map((n) => {
                'name': n.name,
                'role': n.role,
                'personality': n.personality,
                'relation': n.relation,
              })
          .toList();

      final aiController = ref.read(adventureAiControllerProvider);
      final result = await aiController.generateOpening(
        userPrompt: pref.isNotEmpty ? pref : '根据世界观和主角设定，设计一个精彩的开场',
        worldview: worldview,
        protagonistName: ctx['name']!,
        protagonistRole: ctx['role']!,
        protagonistPersonality: ctx['personality']!,
        protagonistBackground: ctx['background']!,
        protagonistBodyDescription: ctx['bodyDescription']!,
        protagonistAppearance: ctx['appearance']!,
        selectedCharacters: _buildSelectedCharacterContexts(),
        characterRelationships: _buildCharacterRelationshipContexts(),
        npcs: npcs,
      );

      if (!mounted) return;
      setState(() {
        _openingGenLoading = false;
        _openingGenResult = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _openingGenLoading = false;
        final msg = e.toString().split('\n').first;
        if (msg.contains('timeout') || msg.contains('Timeout')) {
          _openingGenError = 'AI 响应超时，请检查网络后重试';
        } else if (msg.contains('401') || msg.contains('403')) {
          _openingGenError = 'API Key 无效，请检查设置';
        } else {
          _openingGenError = '生成失败: $msg';
        }
      });
    }
  }

  /// 将 AI 生成的开场填入文本框
  void _fillOpeningFromAi(Map<String, String> r) {
    setState(() {
      _openingSceneCtrl.text = r['scene'] ?? '';
      _openingOptionsCtrl.text = r['options'] ?? '';
      _openingGenResult = null;
      _openingGenCtrl.clear();
      _openingGenExpanded = false;
    });
  }

  /// 将 AI 生成的 NPC 批量填入列表
  void _fillNpcsFromAi(List<Map<String, String>> npcs) {
    setState(() {
      for (final npc in npcs) {
        final name = npc['name'] ?? '';
        if (name.isEmpty) continue;
        _npcs.add(SupportingCharacter(
          name: name,
          gender: npc['gender'] ?? '',
          role: npc['role'] ?? '',
          personality: npc['personality'] ?? '',
          relation: npc['relation'] ?? '',
        ));
        _npcNameCtrls.add(TextEditingController(text: name));
        _npcRelCtrls.add(TextEditingController(text: npc['relation'] ?? ''));
        _npcPersCtrls
            .add(TextEditingController(text: npc['personality'] ?? ''));
        _npcGenders.add(npc['gender'] ?? '');
        _npcRoleCtrls.add(TextEditingController(text: npc['role'] ?? ''));
      }
      // 填入后清空生成结果
      _npcGenResult = null;
      _npcGenCtrl.clear();
      _npcGenExpanded = false;
    });
  }

  Future<void> _addNpc() async {
    final result = await showAdventureManualNpcPage(context);
    if (!mounted || result == null) return;
    _appendNpc(result);
  }

  void _appendNpc(Map<String, String> result) {
    setState(() {
      final name = result['name'] ?? '';
      final relation = result['relation'] ?? '';
      final personality = result['personality'] ?? '';
      final gender = result['gender'] ?? '';
      final role = result['role'] ?? '';
      _npcs.add(SupportingCharacter(
        name: name,
        relation: relation,
        personality: personality,
        gender: gender,
        role: role,
      ));
      _npcNameCtrls.add(TextEditingController(text: name));
      _npcRelCtrls.add(TextEditingController(text: relation));
      _npcPersCtrls.add(TextEditingController(text: personality));
      _npcGenders.add(gender);
      _npcRoleCtrls.add(TextEditingController(text: role));
    });
  }

  void _removeNpc(int index) {
    setState(() {
      _npcs.removeAt(index);
      _npcNameCtrls[index].dispose();
      _npcRelCtrls[index].dispose();
      _npcPersCtrls[index].dispose();
      _npcRoleCtrls[index].dispose();
      _npcNameCtrls.removeAt(index);
      _npcRelCtrls.removeAt(index);
      _npcPersCtrls.removeAt(index);
      _npcGenders.removeAt(index);
      _npcRoleCtrls.removeAt(index);
    });
  }

  void _syncNpcsFromControllers() {
    for (int i = 0; i < _npcs.length; i++) {
      _npcs[i].name = _npcNameCtrls[i].text;
      _npcs[i].relation = _npcRelCtrls[i].text;
      _npcs[i].personality = _npcPersCtrls[i].text;
      _npcs[i].gender = _npcGenders[i];
      _npcs[i].role = _npcRoleCtrls[i].text;
    }
  }

  AdventureConfig _buildConfig() {
    _syncNpcsFromControllers();
    final options = _openingOptionsCtrl.text
        .split('\n')
        .map((s) => s.trim().replaceFirst(RegExp(r'^\d+[、.\s]+'), ''))
        .where((s) => s.isNotEmpty)
        .toList();

    // 从选中的角色卡提取主角信息，没有则用手动输入
    String name = '';
    String gender = '';
    String age = '';
    String protagonistClass = '';
    String protagonistBackground = '';
    String personality = '';
    CharacterCard? characterCard;

    final protagonist = _protagonistBinding;
    if (protagonist != null) {
      final entry = _setup.entryById(protagonist.characterId);
      if (entry != null) {
        name = entry.name;
        gender = entry.gender;
        age = entry.age;
        protagonistClass = entry.profession;
        protagonistBackground = entry.card.description;
        personality = entry.personality;
        characterCard = entry.card;
      } else {
        final data = protagonist.characterCardJson ?? const <String, dynamic>{};
        name = protagonist.characterName;
        gender = data['gender'] as String? ?? '';
        age = data['age']?.toString() ?? '';
        protagonistClass =
            data['profession'] as String? ?? protagonist.effectiveRole;
        protagonistBackground = data['description'] as String? ??
            data['background'] as String? ??
            '';
        personality = data['personality'] as String? ?? '';
      }
    } else {
      name = _manualCardNameCtrls.isNotEmpty
          ? _manualCardNameCtrls[0].text.trim()
          : '';
      gender = _manualCardGenders.isNotEmpty ? _manualCardGenders[0] : '';
      age = _manualCardAgeCtrls.isNotEmpty
          ? _manualCardAgeCtrls[0].text.trim()
          : '';
      protagonistClass = _manualCardProfCtrls.isNotEmpty
          ? _manualCardProfCtrls[0].text.trim()
          : '';
      personality = _manualCardPersonCtrls.isNotEmpty
          ? _manualCardPersonCtrls[0].text.trim()
          : '';
      protagonistBackground = _manualCardBgCtrls.isNotEmpty
          ? _manualCardBgCtrls[0].text.trim()
          : '';
    }

    final selectedCharacters = _selectedCharacters
        .map((character) => AdventureSelectedCharacter.fromJson(
              character.toJson(),
            ))
        .toList();
    if (selectedCharacters.isEmpty && name.isNotEmpty) {
      selectedCharacters.add(AdventureSelectedCharacter(
        id: 'manual_protagonist',
        characterId: 'manual_protagonist',
        characterName: name,
        isProtagonist: true,
        narrativeRole: AdventureCharacterRole.protagonist,
        sortOrder: 0,
        characterCardJson: {
          'name': name,
          'gender': gender,
          'age': age,
          'profession': protagonistClass,
          'personality': personality,
          'description': protagonistBackground,
        },
      ));
    }
    final relationships = _characterRelationships
        .map((relation) => AdventureCharacterRelationship.fromJson(
              relation.toJson(),
            ))
        .toList();

    String worldview = _worldviewDesc;
    if (worldview.isEmpty && _manualWvNameCtrls.isNotEmpty) {
      final buf = StringBuffer();
      for (int i = 0; i < _manualWvNameCtrls.length; i++) {
        final n = _manualWvNameCtrls[i].text.trim();
        final d = _manualWvDescCtrls[i].text.trim();
        if (n.isNotEmpty) buf.writeln('【$n】');
        if (d.isNotEmpty) buf.writeln(d);
      }
      worldview = buf.toString().trim();
    }

    Map<String, dynamic>? worldviewSnapshot;
    if (_selWorldviewId != null) {
      worldviewSnapshot =
          ref.read(adventureSetupControllerProvider).buildWorldviewSnapshot(
                id: _selWorldviewId!,
                worldview: worldview,
              );
    }

    return AdventureConfig(
      worldview: worldview,
      worldviewSnapshot: worldviewSnapshot,
      name: name,
      gender: gender,
      age: age,
      protagonistClass: protagonistClass,
      protagonistBackground: protagonistBackground,
      personality: personality,
      characterCard: characterCard,
      selectedCharacters: selectedCharacters,
      characterRelationships: relationships,
      openingScene: _openingSceneCtrl.text.trim(),
      openingOptions:
          options.isNotEmpty ? options : ['探索前方的道路', '观察周围环境', '检查随身物品'],
      supportingCharacters: List<SupportingCharacter>.from(_npcs),
    );
  }

  Future<void> _startAdventure(AdventureConfig config) async {
    if (_isStartingAdventure) return;
    setState(() => _isStartingAdventure = true);

    try {
      await widget.onStartAdventure(config);
    } finally {
      if (mounted) {
        setState(() => _isStartingAdventure = false);
      }
    }
  }

  List<String> get _openingOptionList {
    return _openingOptionsCtrl.text
        .split('\n')
        .map((s) => s.trim().replaceFirst(RegExp(r'^\d+[、.\s]+'), ''))
        .where((s) => s.isNotEmpty)
        .toList();
  }

  void _showNpcImportDialog() {
    final candidates = <Map<String, dynamic>>[
      for (final entry in _availableCardEntries)
        {
          'id': entry.id,
          'name': entry.name,
          'gender': entry.gender,
          'personality': entry.personality,
          'role': entry.profession,
          'appearance': entry.appearance,
        },
    ];
    showFormSubPage<void>(
      context: context,
      title: '从资料库导入角色',
      maxWidth: 760,
      builder: (ctx) => SizedBox(
        height: 520,
        child: Column(
          children: [
            Expanded(
              child: candidates.isEmpty
                  ? const Center(child: Text('当前世界观没有可导入的关联角色。'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: candidates.length,
                      itemBuilder: (ctx, index) {
                        final c = candidates[index];
                        final subtitle = [
                          if ((c['gender'] as String).isNotEmpty) c['gender'],
                          if ((c['role'] as String).isNotEmpty) c['role'],
                        ].join(' · ');
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              (c['name'] as String).isNotEmpty
                                  ? (c['name'] as String)[0]
                                  : '?',
                            ),
                          ),
                          title: Text(c['name'] as String),
                          subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
                          trailing: const Icon(Icons.add_circle_outline),
                          onTap: () {
                            setState(() {
                              _npcs.add(SupportingCharacter(
                                name: c['name'] as String,
                                gender: c['gender'] as String,
                                personality: c['personality'] as String,
                                role: c['role'] as String,
                              ));
                              _npcNameCtrls.add(TextEditingController(
                                  text: c['name'] as String));
                              _npcRelCtrls.add(TextEditingController());
                              _npcPersCtrls.add(TextEditingController(
                                  text: c['personality'] as String));
                              _npcGenders.add(c['gender'] as String);
                              _npcRoleCtrls.add(TextEditingController(
                                  text: c['role'] as String));
                            });
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNpcImportFromCardDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('从角色卡导入'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: ctrl,
            maxLines: 8,
            scrollPadding: const EdgeInsets.only(bottom: 120),
            decoration: const InputDecoration(
              hintText: '粘贴角色卡 JSON 内容...',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ctrl.dispose();
              Navigator.pop(ctx);
            },
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final text = ctrl.text.trim();
              if (text.isEmpty) {
                ctrl.dispose();
                Navigator.pop(ctx);
                return;
              }
              try {
                final json = jsonDecode(text) as Map<String, dynamic>;
                final data = json['data'] as Map<String, dynamic>? ?? json;
                final name = data['name'] as String? ?? '';
                final personality = data['personality'] as String? ?? '';
                setState(() {
                  _npcs.add(SupportingCharacter(
                    name: name,
                    personality: personality,
                  ));
                  _npcNameCtrls.add(TextEditingController(text: name));
                  _npcRelCtrls.add(TextEditingController());
                  _npcPersCtrls.add(TextEditingController(text: personality));
                  _npcGenders.add(data['gender'] as String? ?? '');
                  _npcRoleCtrls.add(TextEditingController(
                      text: data['profession'] as String? ?? ''));
                });
                ctrl.dispose();
                Navigator.pop(ctx);
              } catch (_) {
                ctrl.dispose();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('JSON 格式无效')),
                );
              }
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showPreview) return _buildPreviewPage();
    return _buildEditorPage();
  }

  Widget _buildEditorPage() {
    if (_loading) {
      return const NarrAItorLoading.normal();
    }

    return Column(children: [
      _buildStepIndicator(),
      Expanded(
        child: IndexedStack(
          index: _currentStep,
          children: [
            _buildStep0Worldview(),
            _buildStep1CharacterCard(),
            _buildStep2Npcs(),
            _buildStep3Opening(),
            _buildStep4Confirm(),
          ],
        ),
      ),
      AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              if (_currentStep > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _currentStep--),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('上一步：${_stepLabels[_currentStep - 1]}'),
                  ),
                ),
              if (_currentStep > 0) const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _currentStep < _stepCount - 1
                      ? () {
                          if (_currentStep == 1 && !_guardCharacterSetup()) {
                            return;
                          }
                          setState(() => _currentStep++);
                        }
                      : () {
                          if (!_guardCharacterSetup()) return;
                          setState(() => _showPreview = true);
                        },
                  icon: Icon(_currentStep < _stepCount - 1
                      ? Icons.arrow_forward
                      : Icons.preview),
                  label: Text(
                    _currentStep < _stepCount - 1
                        ? '下一步：${_stepLabels[_currentStep + 1]}'
                        : '预览冒险',
                    style: const TextStyle(fontSize: 15),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  /// C10: 重置所有表单字段
  void _resetAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置定制'),
        content: const Text('确定要重置所有已填写的内容吗？此操作不可撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定重置')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _selWorldviewId = null;
      _worldviewDesc = '';
      _selectedCharacters.clear();
      _characterRelationships.clear();
      _currentStep = 0;
      // Clear manual worldviews
      for (final c in _manualWvNameCtrls) {
        c.dispose();
      }
      for (final c in _manualWvDescCtrls) {
        c.dispose();
      }
      _manualWvNameCtrls.clear();
      _manualWvDescCtrls.clear();
      // Clear manual character cards
      for (final c in _manualCardNameCtrls) {
        c.dispose();
      }
      for (final c in _manualCardAgeCtrls) {
        c.dispose();
      }
      for (final c in _manualCardProfCtrls) {
        c.dispose();
      }
      for (final c in _manualCardPersonCtrls) {
        c.dispose();
      }
      for (final c in _manualCardBgCtrls) {
        c.dispose();
      }
      for (final c in _manualCardAppearCtrls) {
        c.dispose();
      }
      _manualCardNameCtrls.clear();
      _manualCardGenders.clear();
      _manualCardAgeCtrls.clear();
      _manualCardProfCtrls.clear();
      _manualCardPersonCtrls.clear();
      _manualCardBgCtrls.clear();
      _manualCardAppearCtrls.clear();
      // Clear NPCs
      for (final c in _npcNameCtrls) {
        c.dispose();
      }
      for (final c in _npcRelCtrls) {
        c.dispose();
      }
      for (final c in _npcPersCtrls) {
        c.dispose();
      }
      for (final c in _npcRoleCtrls) {
        c.dispose();
      }
      _npcNameCtrls.clear();
      _npcRelCtrls.clear();
      _npcPersCtrls.clear();
      _npcGenders.clear();
      _npcRoleCtrls.clear();
      _npcs.clear();
      // Clear opening
      _openingSceneCtrl.clear();
      _openingOptionsCtrl.clear();
      _openingGenResult = null;
      _openingGenCtrl.clear();
      _openingGenExpanded = false;
      _npcGenResult = null;
      _npcGenCtrl.clear();
      _npcGenExpanded = false;
    });
  }

  Widget _buildStepIndicator() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor =
        isDark ? AppColors.darkSurface : AppColors.surfaceElevated;
    final borderColor =
        isDark ? AppColors.darkSurfaceElevated : Colors.grey[200]!;
    final inactiveDotColor =
        isDark ? AppColors.darkSurfaceElevated : Colors.grey[300]!;
    final inactiveTextColor =
        isDark ? AppColors.darkTextSecondary : Colors.grey[500]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Column(children: [
        Row(
          children: List.generate(_stepCount, (i) {
            final done = i < _currentStep;
            final active = i == _currentStep;
            return Expanded(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: done
                        ? AppColors.accent
                        : (active ? AppColors.accent : inactiveDotColor),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Center(
                    child: done
                        ? const Icon(Icons.check, size: 9, color: Colors.white)
                        : Text('${i + 1}',
                            style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w600,
                                color:
                                    active ? Colors.white : inactiveTextColor)),
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(_stepLabels[i],
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.w400,
                          color:
                              active ? AppColors.accent : inactiveTextColor)),
                ),
              ]),
            );
          }),
        ),
        const SizedBox(height: 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(1),
          child: LinearProgressIndicator(
            value: _progress,
            minHeight: 1.5,
            backgroundColor: borderColor,
            valueColor: AlwaysStoppedAnimation<Color>(
                _progress >= 1.0 ? AppColors.success : AppColors.accent),
          ),
        ),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton.icon(
            onPressed: _resetAll,
            icon: const Icon(Icons.restart_alt, size: 14),
            label: const Text('重置', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              minimumSize: const Size(0, 28),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _buildStep0Worldview() {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildSectionHeader('世界观', '选择预设或手动添加世界背景'),
        if (_worldviewPresets.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('暂无世界观预设，请在下方手动添加或侧边栏创建',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          )
        else
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: _worldviewPresets.length,
              itemBuilder: (context, index) {
                final wv = _worldviewPresets[index];
                final name = wv['name'] as String? ?? '';
                final desc = wv['description'] as String? ?? '';
                final selected = _selWorldviewId == wv['id'];
                return GestureDetector(
                  onTap: () => _selectWorldview(wv),
                  child: Container(
                    width: 160,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.accent
                          : isDark
                              ? AppColors.darkSurfaceElevated
                              : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? AppColors.accent
                            : isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.grey[300]!,
                        width: selected ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? Colors.white
                                    : isDark
                                        ? AppColors.darkTextPrimary
                                        : Colors.black87),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Text(desc,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: selected
                                      ? Colors.white70
                                      : isDark
                                          ? AppColors.darkTextSecondary
                                          : Colors.grey[600],
                                  height: 1.4),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 12),
        // AI 快速生成
        AiGenerateSection(
          mode: AiGenerateMode.worldview,
          onGenerate: (
              {prompt,
              base64Image,
              worldviewHint,
              associatedCharacters}) async {
            final ai = ref.read(adventureAiControllerProvider);
            if (base64Image != null) {
              return await ai.imageToWorldview(base64Image);
            } else {
              return await ai.generateWorldview(prompt ?? '');
            }
          },
          isVisionModel: _isVisionModel,
          onFill: _onAiFillWorldview,
          onSave: _onAiSaveWorldview,
        ),
        const SizedBox(height: 8),
        Row(children: [
          const Text('手动添加',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          IconButton(
            onPressed: _addManualWorldview,
            icon: const Icon(Icons.add_circle, color: AppColors.accent),
            tooltip: '手动添加',
          ),
        ]),
        if (_manualWvNameCtrls.isEmpty)
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 4),
            child: Text('暂未手动添加，可跳过此步',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        ...List.generate(_manualWvNameCtrls.length, (i) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: AppColors.accent.withValues(alpha: 0.1),
                      child: Text('${i + 1}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accent)),
                    ),
                    const SizedBox(width: 8),
                    Text('世界观 ${i + 1}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    const Spacer(),
                    IconButton(
                      onPressed: () => _removeManualWorldview(i),
                      icon: const Icon(Icons.close, size: 18),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      color: AppColors.error,
                    ),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _manualWvNameCtrls[i],
                    decoration: const InputDecoration(
                      labelText: '名称',
                      hintText: '例如：中土大陆、赛博都市...',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _manualWvDescCtrls[i],
                    maxLines: 3,
                    minLines: 2,
                    decoration: const InputDecoration(
                      labelText: '描述',
                      hintText: '世界背景、种族、势力、魔法体系...',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }),
      ]),
    );
  }

  Widget _buildStep1CharacterCard() {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final availableCards = _availableCardEntries;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildSectionHeader('选择角色', '可选择多个角色，但主角只能有一个。'),
        if (_selWorldviewId == null)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('请先选择世界观，系统将只显示与该世界观关联的角色。',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          )
        else if (availableCards.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('当前世界观尚未关联角色。\n请前往对应资料库为角色关联该世界观，或在当前步骤新建角色。',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          )
        else
          SizedBox(
            height: 128,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: availableCards.length,
              itemBuilder: (context, index) {
                final entry = availableCards[index];
                final name = entry.name;
                final cardId = entry.id;
                final selected =
                    _selectedCharacters.any((c) => c.characterId == cardId);
                final isProtagonist =
                    _protagonistBinding?.characterId == cardId;
                final role = entry.profession;
                final personality = entry.personality;
                return GestureDetector(
                  onTap: () => _toggleCharacterCard(entry),
                  child: Container(
                    width: 140,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.accent
                          : isDark
                              ? AppColors.darkSurfaceElevated
                              : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? AppColors.accent
                            : isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.grey[300]!,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: selected
                                ? Colors.white24
                                : AppColors.accent.withValues(alpha: 0.1),
                            child: Text(name.isNotEmpty ? name[0] : '?',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: selected
                                        ? Colors.white
                                        : AppColors.accent)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(name,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: selected
                                        ? Colors.white
                                        : isDark
                                            ? AppColors.darkTextPrimary
                                            : Colors.black87),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ]),
                        if (role.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(role,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: selected
                                      ? Colors.white70
                                      : isDark
                                          ? AppColors.darkTextSecondary
                                          : Colors.grey[500]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                        const Spacer(),
                        if (isProtagonist)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: selected
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : AppColors.accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('主角',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: selected
                                        ? Colors.white
                                        : AppColors.accent,
                                    fontWeight: FontWeight.w600)),
                          ),
                        if (personality.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(personality,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: selected
                                      ? Colors.white60
                                      : isDark
                                          ? AppColors.darkTextSecondary
                                          : Colors.grey[500],
                                  height: 1.3),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        _buildSelectedCharactersPanel(),
        _buildRelationshipsPanel(),
        const SizedBox(height: 12),
        // AI 快速生成
        AiGenerateSection(
          mode: AiGenerateMode.characterCard,
          onGenerate: (
              {prompt,
              base64Image,
              worldviewHint,
              associatedCharacters}) async {
            final ai = ref.read(adventureAiControllerProvider);
            if (base64Image != null) {
              return await ai.imageToCharacterCard(base64Image,
                  worldview: worldviewHint ?? '');
            } else {
              return await ai.generateResourceCharacter(
                  source: prompt ?? '',
                  worldview: worldviewHint ?? '',
                  associatedCharacters: associatedCharacters ?? []);
            }
          },
          isVisionModel: _isVisionModel,
          worldviewHint: _currentWorldviewDesc,
          availableCharacterCards: availableCards,
          excludeCardIds: _selectedCharacters.map((c) => c.characterId).toSet(),
          canSaveToLibrary: _selWorldviewId != null,
          saveRestrictionMessage: '选择资料库世界观后，才能保存角色卡到资料库。',
          onFill: _onAiFillCharacterCard,
          onSave: _onAiSaveCharacterCard,
        ),
        const SizedBox(height: 8),
        Row(children: [
          const Text('手动添加',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          IconButton(
            onPressed: _addManualCard,
            icon: const Icon(Icons.add_circle, color: AppColors.accent),
            tooltip: '手动添加',
          ),
        ]),
        if (_manualCardNameCtrls.isEmpty)
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 4),
            child: Text('暂未手动添加，可跳过此步',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        ...List.generate(_manualCardNameCtrls.length, (i) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: AppColors.accent.withValues(alpha: 0.1),
                      child: Text('${i + 1}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accent)),
                    ),
                    const SizedBox(width: 8),
                    Text('角色卡 ${i + 1}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    const Spacer(),
                    IconButton(
                      onPressed: () => _removeManualCard(i),
                      icon: const Icon(Icons.close, size: 18),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      color: AppColors.error,
                    ),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _manualCardNameCtrls[i],
                    decoration: const InputDecoration(
                      labelText: '姓名 *',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Flexible(
                      child: NarrAItorDropdown<String>(
                        value: _manualCardGenders[i],
                        label: '性别',
                        options: ['男', '女', '其他']
                            .map((g) =>
                                NarrAItorDropdownOption(value: g, label: g))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _manualCardGenders[i] = v ?? '女'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: TextField(
                        controller: _manualCardAgeCtrls[i],
                        decoration: const InputDecoration(
                          labelText: '年龄',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _manualCardProfCtrls[i],
                    decoration: const InputDecoration(
                      labelText: '职业/身份',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _manualCardPersonCtrls[i],
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '性格',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _manualCardBgCtrls[i],
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '背景故事',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _manualCardAppearCtrls[i],
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '外貌描述',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }),
      ]),
    );
  }

  Widget _buildSelectedCharactersPanel() {
    if (_selectedCharacters.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text('点击上方角色卡即可加入已选角色。第一个角色会自动成为主角。',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('已选角色',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('${_selectedCharacters.length} 个',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
        ]),
        const SizedBox(height: 8),
        ..._selectedCharacters.map((character) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                      child: Text(
                        character.characterName.isNotEmpty
                            ? character.characterName[0]
                            : '?',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.accent,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(character.characterName,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (character.isProtagonist)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text('当前主角',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.accent,
                                fontWeight: FontWeight.w600)),
                      )
                    else
                      TextButton(
                        onPressed: () => _setProtagonist(character.characterId),
                        child:
                            const Text('设为主角', style: TextStyle(fontSize: 12)),
                      ),
                    IconButton(
                      onPressed: () =>
                          _removeSelectedCharacter(character.characterId),
                      icon: const Icon(Icons.close, size: 18),
                      visualDensity: VisualDensity.compact,
                      tooltip: '移除角色',
                    ),
                  ]),
                  const SizedBox(height: 8),
                  NarrAItorDropdown<String>(
                    value: character.narrativeRole,
                    label: '身份定位',
                    options: AdventureCharacterRole.labels.entries
                        .map((entry) => NarrAItorDropdownOption(
                              value: entry.key,
                              label: entry.value,
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        character.narrativeRole = value;
                        character.updatedAt = DateTime.now().toIso8601String();
                        if (value == AdventureCharacterRole.protagonist) {
                          for (final other in _selectedCharacters) {
                            other.isProtagonist =
                                other.characterId == character.characterId;
                          }
                        }
                      });
                    },
                  ),
                  if (character.narrativeRole ==
                      AdventureCharacterRole.custom) ...[
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: character.customRoleName,
                      decoration: const InputDecoration(
                        labelText: '自定义身份',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onChanged: (value) => character.customRoleName = value,
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ]),
    );
  }

  Widget _buildRelationshipsPanel() {
    if (_selectedCharacters.length < 2) return const SizedBox.shrink();
    final nameById = {
      for (final character in _selectedCharacters)
        character.characterId: character.characterName,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Card(
        child: Column(children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.account_tree_outlined,
                color: AppColors.accent),
            title: const Text('角色关系',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: const Text('为已选角色之间设置关系', style: TextStyle(fontSize: 11)),
            trailing: Icon(
                _relationshipsExpanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(
                () => _relationshipsExpanded = !_relationshipsExpanded),
          ),
          if (_relationshipsExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                children: _characterRelationships.map((relation) {
                  final source = nameById[relation.sourceCharacterId] ?? '角色 A';
                  final target = nameById[relation.targetCharacterId] ?? '角色 B';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$source - $target',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          NarrAItorDropdown<String>(
                            value: relation.relationType,
                            label: '关系类型',
                            options: AdventureRelationType.labels.entries
                                .map((entry) => NarrAItorDropdownOption(
                                      value: entry.key,
                                      label: entry.value,
                                    ))
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                relation.relationType = value;
                                relation.updatedAt =
                                    DateTime.now().toIso8601String();
                              });
                            },
                          ),
                          if (relation.relationType ==
                              AdventureRelationType.custom) ...[
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: relation.customRelationName,
                              decoration: const InputDecoration(
                                labelText: '自定义关系名称',
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                              ),
                              onChanged: (value) =>
                                  relation.customRelationName = value,
                            ),
                          ],
                          const SizedBox(height: 8),
                          TextFormField(
                            initialValue: relation.description,
                            minLines: 1,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: '关系描述（可选）',
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                            ),
                            onChanged: (value) => relation.description = value,
                          ),
                        ]),
                  );
                }).toList(),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildStep2Npcs() {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildSectionHeader('NPC 配角', '添加冒险中的重要配角'),
        Row(children: [
          OutlinedButton.icon(
            onPressed: _showNpcImportDialog,
            icon: const Icon(Icons.storage, size: 16),
            label: const Text('从资料库导入'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.accent),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _showNpcImportFromCardDialog,
            icon: const Icon(Icons.person_add, size: 16),
            label: const Text('从角色卡导入'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey[600],
              side: BorderSide(color: Colors.grey[400]!),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _addNpc,
            icon: const Icon(Icons.add_circle, color: AppColors.accent),
            tooltip: '手动添加',
          ),
        ]),
        const SizedBox(height: 10),

        // ── AI 批量生成 NPC ──
        _buildNpcAiSection(),

        const SizedBox(height: 8),
        if (_npcs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('暂未添加 NPC，可跳过此步', style: TextStyle(color: Colors.grey)),
          ),
        ...List.generate(_npcs.length, (i) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: AppColors.accent.withValues(alpha: 0.1),
                      child: Text('${i + 1}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accent)),
                    ),
                    const SizedBox(width: 8),
                    Text('NPC ${i + 1}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    const Spacer(),
                    IconButton(
                      onPressed: () => _removeNpc(i),
                      icon: const Icon(Icons.close, size: 18),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      color: AppColors.error,
                    ),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _npcNameCtrls[i],
                    decoration: const InputDecoration(
                      labelText: '名称',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _npcRelCtrls[i],
                        decoration: const InputDecoration(
                          labelText: '关系',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _npcRoleCtrls[i],
                        decoration: const InputDecoration(
                          labelText: '身份',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 70,
                      child: NarrAItorDropdown<String>(
                        value: _npcGenders[i].isEmpty ? null : _npcGenders[i],
                        label: '性别',
                        options: ['', '男', '女', '其他']
                            .map((g) => NarrAItorDropdownOption(
                                value: g.isEmpty ? null : g,
                                label: g.isEmpty ? '-' : g))
                            .toList(),
                        onChanged: (v) {
                          _npcGenders[i] = v ?? '';
                        },
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _npcPersCtrls[i],
                    decoration: const InputDecoration(
                      labelText: '性格/描述',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          );
        }),
      ]),
    );
  }

  /// AI 批量生成 NPC 的可折叠面板
  Widget _buildNpcAiSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelBg = isDark
        ? AppColors.darkSurfaceElevated
        : AppColors.accent.withValues(alpha: 0.04);
    final panelBorder = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : AppColors.accent.withValues(alpha: 0.15);
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: panelBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: panelBorder),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ── 折叠/展开头部 ──
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _npcGenExpanded = !_npcGenExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              const Icon(Icons.auto_fix_high,
                  size: 16, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                _npcGenResult != null
                    ? 'AI 已生成 ${_npcGenResult!.length} 个 NPC'
                    : 'AI 批量生成 NPC',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _npcGenResult != null
                        ? AppColors.success
                        : AppColors.accent),
              ),
              if (_npcGenResult != null) ...[
                const SizedBox(width: 6),
                const Icon(Icons.check_circle,
                    size: 16, color: AppColors.success),
              ],
              const Spacer(),
              Icon(_npcGenExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: textSecondary),
            ]),
          ),
        ),

        // ── 展开内容 ──
        if (_npcGenExpanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '描述你想要的 NPC 类型（可选参考世界观和主角设定）',
                style: TextStyle(fontSize: 11, color: textSecondary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _npcGenCtrl,
                minLines: 3,
                maxLines: (MediaQuery.of(context).size.height * 0.4 ~/ 20)
                    .clamp(3, 20),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: _npcAssociatedIds.isNotEmpty
                      ? '提示词中写明关联角色的关系'
                      : '例如：需要一个神秘的老巫师作为导师，'
                          '一个嫉妒主角的同门师兄，一个活泼的旅伴...',
                  hintStyle: TextStyle(fontSize: 11, color: textSecondary),
                  filled: true,
                  fillColor: isDark ? AppColors.darkSurface : AppColors.surface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  isDense: true,
                ),
              ),
              // ── 关联已有角色（可折叠可选项） ──
              if (_availableCharacterCards.isNotEmpty)
                _buildNpcAssociatePanel(),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _npcGenLoading ? null : _generateNpcs,
                  icon: const Icon(Icons.auto_fix_high, size: 15),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(_npcGenLoading ? '正在生成...' : '生成 NPC',
                        style: const TextStyle(fontSize: 12)),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    minimumSize: const Size.fromHeight(52),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
              ),

              // 加载状态
              if (_npcGenLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Center(
                    child: Column(children: [
                      NarrAItorLoading.mini(),
                      SizedBox(height: 8),
                      Text('AI 正在构思角色...',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ]),
                  ),
                ),

              // 错误提示
              if (_npcGenError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                          size: 16, color: AppColors.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_npcGenError!,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.error)),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _npcGenError = null),
                        child: const Text('关闭', style: TextStyle(fontSize: 11)),
                      ),
                    ]),
                  ),
                ),

              // 生成结果 — 多个 NPC 卡片
              if (_npcGenResult != null) ...[
                const SizedBox(height: 12),
                ..._npcGenResult!.asMap().entries.map(
                    (entry) => _buildNpcResultCard(entry.key, entry.value)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _npcGenResult = null;
                        _npcGenError = null;
                      }),
                      icon: const Icon(Icons.refresh, size: 14),
                      label: const Text('重新生成', style: TextStyle(fontSize: 12)),
                    ),
                    FilledButton.icon(
                      onPressed: () => _fillNpcsFromAi(_npcGenResult!),
                      icon: const Icon(Icons.add_circle_outline, size: 16),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('全部填入 (${_npcGenResult!.length}个)',
                            style: const TextStyle(fontSize: 12)),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        minimumSize: const Size.fromHeight(52),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                      ),
                    ),
                  ],
                ),
              ],
            ]),
          ),
      ]),
    );
  }

  /// NPC 关联已有角色（统一多选下拉）。
  Widget _buildNpcAssociatePanel() {
    final selectedIds = _selectedCharacters.map((c) => c.characterId).toSet();
    final cards =
        _availableCardEntries.where((e) => !selectedIds.contains(e.id));
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: NarrAItorMultiSelectDropdown<String>(
        values: _npcAssociatedIds,
        label: '关联已有角色（可选）',
        emptyText: '暂无已有角色卡',
        selectedBuilder: (values) =>
            values.isEmpty ? '不指定' : '已选 ${values.length} 个角色',
        options: cards.map((entry) {
          return NarrAItorDropdownOption(
            value: entry.id,
            label: entry.name.isEmpty ? '未命名角色' : entry.name,
            subtitle: entry.profession.isEmpty ? null : entry.profession,
          );
        }).toList(),
        onChanged: (values) => setState(() {
          _npcAssociatedIds
            ..clear()
            ..addAll(values);
        }),
      ),
    );
  }

  /// 单个 NPC 生成结果卡片
  Widget _buildNpcResultCard(int index, Map<String, String> npc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = npc['name'] ?? '';
    final role = npc['role'] ?? '';
    final personality = npc['personality'] ?? '';
    final relation = npc['relation'] ?? '';
    final gender = npc['gender'] ?? '';
    final colorIndex = index % AppColors.avatarColors.length;
    final avatarColor = AppColors.avatarColors[colorIndex];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.grey[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: avatarColor,
            child: Text(
              name.isNotEmpty ? name[0] : '?',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(name,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (gender.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(gender,
                          style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.textSecondary)),
                    ],
                    if (role.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(role,
                            style: const TextStyle(
                                fontSize: 10, color: AppColors.accent)),
                      ),
                    ],
                  ],
                ),
                if (personality.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(personality,
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.textPrimary,
                          height: 1.35)),
                ],
                if (relation.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('关系: $relation',
                      style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.textSecondary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// AI 生成开场场景的可折叠面板
  Widget _buildOpeningAiSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelBg = isDark
        ? AppColors.darkSurfaceElevated
        : AppColors.accent.withValues(alpha: 0.04);
    final panelBorder = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : AppColors.accent.withValues(alpha: 0.15);
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: panelBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: panelBorder),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ── 折叠/展开头部 ──
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              setState(() => _openingGenExpanded = !_openingGenExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              const Icon(Icons.auto_fix_high,
                  size: 16, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                _openingGenResult != null ? 'AI 已生成开场' : 'AI 快速生成开场',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _openingGenResult != null
                        ? AppColors.success
                        : AppColors.accent),
              ),
              if (_openingGenResult != null) ...[
                const SizedBox(width: 6),
                const Icon(Icons.check_circle,
                    size: 16, color: AppColors.success),
              ],
              const Spacer(),
              Icon(_openingGenExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: textSecondary),
            ]),
          ),
        ),

        // ── 展开内容 ──
        if (_openingGenExpanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '描述你想要的冒险开场风格（可选参考世界观和主角设定）',
                style: TextStyle(fontSize: 11, color: textSecondary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _openingGenCtrl,
                minLines: 3,
                maxLines: (MediaQuery.of(context).size.height * 0.4 ~/ 20)
                    .clamp(3, 20),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: '例如：紧张刺激的追逐战开场、'
                      '神秘的古墓探险、温馨的村庄日常...',
                  hintStyle: TextStyle(fontSize: 11, color: textSecondary),
                  filled: true,
                  fillColor: isDark ? AppColors.darkSurface : AppColors.surface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openingGenLoading ? null : _generateOpening,
                  icon: const Icon(Icons.auto_fix_high, size: 15),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(_openingGenLoading ? '正在生成...' : '生成开场',
                        style: const TextStyle(fontSize: 12)),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    minimumSize: const Size.fromHeight(52),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
              ),

              // 加载状态
              if (_openingGenLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Center(
                    child: Column(children: [
                      NarrAItorLoading.mini(),
                      SizedBox(height: 8),
                      Text('AI 正在构思开场...',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ]),
                  ),
                ),

              // 错误提示
              if (_openingGenError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                          size: 16, color: AppColors.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_openingGenError!,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.error)),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => _openingGenError = null),
                        child: const Text('关闭', style: TextStyle(fontSize: 11)),
                      ),
                    ]),
                  ),
                ),

              // 生成结果
              if (_openingGenResult != null) ...[
                const SizedBox(height: 12),
                _buildOpeningResultCard(_openingGenResult!),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _openingGenResult = null;
                        _openingGenError = null;
                      }),
                      icon: const Icon(Icons.refresh, size: 14),
                      label: const Text('重新生成', style: TextStyle(fontSize: 12)),
                    ),
                    FilledButton.icon(
                      onPressed: () => _fillOpeningFromAi(_openingGenResult!),
                      icon: const Icon(Icons.edit_note, size: 16),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('填入表单', style: TextStyle(fontSize: 12)),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        minimumSize: const Size.fromHeight(52),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                      ),
                    ),
                  ],
                ),
              ],
            ]),
          ),
      ]),
    );
  }

  Widget _buildOpeningResultCard(Map<String, String> r) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scene = r['scene'] ?? '';
    final options = r['options'] ?? '';
    final optionList = options
        .split('\n')
        .map((s) => s.trim().replaceFirst(RegExp(r'^\d+[、.\s]+'), ''))
        .where((s) => s.isNotEmpty)
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : AppColors.success.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.movie_creation_outlined,
                size: 20, color: AppColors.accent),
            SizedBox(width: 8),
            Expanded(
              child: Text('生成的开场',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            Text('已生成',
                style: TextStyle(fontSize: 11, color: AppColors.success)),
            SizedBox(width: 4),
            Icon(Icons.check_circle, size: 14, color: AppColors.success),
          ]),
          const SizedBox(height: 8),
          SelectableText(
            scene,
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
          if (optionList.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('开场选项：',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            ...optionList.asMap().entries.map((entry) {
              final index = entry.key;
              final option = entry.value;
              return Container(
                margin: EdgeInsets.only(
                    bottom: index == optionList.length - 1 ? 0 : 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${index + 1}. ',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent)),
                    Expanded(
                      child: SelectableText(
                        option,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildStep3Opening() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildOpeningAiSection(),
        const SizedBox(height: 12),
        _buildSectionHeader('开场场景', '冒险的开场叙述'),
        TextField(
          controller: _openingSceneCtrl,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: '描述冒险的开场场景...',
            hintStyle: TextStyle(color: textSecondary),
            border: const OutlineInputBorder(),
          ),
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 12),
        _buildSectionHeader('开场选项', '玩家可选择的初始行动（逗号分隔）'),
        TextField(
          controller: _openingOptionsCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: '1 探索前方的道路\n2 观察周围环境\n3 检查随身物品',
            hintStyle: TextStyle(color: textSecondary),
            border: const OutlineInputBorder(),
          ),
          style: const TextStyle(fontSize: 13),
        ),
        if (_openingOptionList.isNotEmpty) ...[
          const SizedBox(height: 8),
          ..._openingOptionList.asMap().entries.map((entry) {
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${entry.key + 1}. ',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent)),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ]),
    );
  }

  Widget _buildStep4Confirm() {
    _syncNpcsFromControllers();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildSectionHeader('配置预览', '最终确认所有设置'),
        _buildConfigSummary(),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [AppColors.accent, Color(0xFF8B5CF6)],
            ),
          ),
          child: const Text(
            '确认无误后进入场景，开场内容将在对话页实时生成。',
            style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: _isStartingAdventure
                ? null
                : () {
                    if (!_guardCharacterSetup()) return;
                    _startAdventure(_buildConfig());
                  },
            icon: _isStartingAdventure
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: NarrAItorLoading.mini(size: 18),
                  )
                : const Icon(Icons.play_arrow, size: 20),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _isStartingAdventure ? '创建中...' : '直接进入场景',
                style: const TextStyle(fontSize: 16),
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.success,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildSectionHeader(String emojiTitle, String subtitle) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emojiTitle,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 1),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppColors.darkTextSecondary : Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigSummary() {
    _syncNpcsFromControllers();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor =
        isDark ? AppColors.darkSurfaceElevated : Colors.grey[50]!;
    final borderColor = isDark
        ? AppColors.darkTextSecondary.withValues(alpha: 0.24)
        : Colors.grey[200]!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _summaryRow(
                '世界观',
                _selWorldviewId != null
                    ? (_worldviewPresets
                            .where((w) => w['id'] == _selWorldviewId)
                            .firstOrNull?['name'] as String? ??
                        '已选择')
                    : '未选择'),
            const Divider(height: 14),
            _summaryRow(
                '角色卡',
                _selectedCharacters.isEmpty
                    ? '未选择'
                    : '${_selectedCharacters.length} 个角色'),
            const Divider(height: 14),
            _summaryRow('NPC 数量', _npcs.isEmpty ? '无' : '${_npcs.length} 个'),
            const Divider(height: 14),
            _summaryRow(
                '开场场景', _openingSceneCtrl.text.trim().isEmpty ? '未填写' : '已填写'),
            const Divider(height: 14),
            _summaryRow(
                '开场选项',
                _openingOptionList.isEmpty
                    ? '未填写'
                    : '${_openingOptionList.length} 个选项'),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color:
                      isDark ? AppColors.darkTextSecondary : Colors.grey[600])),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewPage() {
    _syncNpcsFromControllers();
    final config = _buildConfig();

    final worldviewName = _selWorldviewId != null
        ? (_worldviewPresets
                .where((w) => w['id'] == _selWorldviewId)
                .firstOrNull?['name'] as String? ??
            '')
        : '';
    final characterSummary = config.selectedCharacters.isEmpty
        ? '未选择角色卡'
        : config.selectedCharacters.map((character) {
            final mark = character.isProtagonist ? '当前主角' : '剧情角色';
            return '${character.characterName}（$mark，${character.effectiveRole}）';
          }).join('\n');

    final List<Widget> slivers = <Widget>[];

    slivers.add(
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppColors.accent,
            ),
            child: const Text(
              '以下是你即将进入的场景配置预览，请确认无误后点击"进入场景"',
              style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
            ),
          ),
        ),
      ),
    );

    slivers.add(
      SliverToBoxAdapter(
        child: _buildPreviewSection(
            '',
            '世界观',
            worldviewName.isNotEmpty
                ? '$worldviewName\n$_worldviewDesc'
                : '未选择世界观'),
      ),
    );

    slivers.add(
      SliverToBoxAdapter(
        child: _buildPreviewSection('', '角色卡', characterSummary),
      ),
    );

    if (config.characterRelationships.isNotEmpty) {
      final nameById = {
        for (final character in config.selectedCharacters)
          character.characterId: character.characterName,
      };
      final relationText = config.characterRelationships.map((relation) {
        final source =
            nameById[relation.sourceCharacterId] ?? relation.sourceCharacterId;
        final target =
            nameById[relation.targetCharacterId] ?? relation.targetCharacterId;
        final desc = relation.description.trim();
        return '$source - $target：${relation.effectiveRelation}${desc.isNotEmpty ? '，$desc' : ''}';
      }).join('\n');
      slivers.add(
        SliverToBoxAdapter(
          child: _buildPreviewSection('', '角色关系', relationText),
        ),
      );
    }

    String npcText;
    if (_npcs.isEmpty) {
      npcText = '无 NPC';
    } else {
      npcText = _npcs.map((n) {
        final parts = <String>['名称：${n.name.isNotEmpty ? n.name : '(未命名)'}'];
        if (n.relation.isNotEmpty) parts.add('关系：${n.relation}');
        if (n.personality.isNotEmpty) parts.add('性格：${n.personality}');
        return parts.join(' | ');
      }).join('\n\n');
    }
    slivers.add(
      SliverToBoxAdapter(
        child: _buildPreviewSection('', 'NPC 配角', npcText),
      ),
    );

    slivers.add(
      SliverToBoxAdapter(
        child: _buildPreviewSection(
          '',
          '开场场景',
          config.effectiveOpeningScene.isNotEmpty
              ? config.effectiveOpeningScene
              : '未填写开场场景',
        ),
      ),
    );

    final options = config.openingOptions;
    slivers.add(
      SliverToBoxAdapter(
        child: _buildPreviewSection(
          '',
          '开场选项',
          options.map((o) => '• $o').join('\n'),
        ),
      ),
    );

    slivers.add(
      SliverToBoxAdapter(
          child:
              SizedBox(height: 80 + MediaQuery.of(context).viewInsets.bottom)),
    );

    return SafeArea(
      top: false,
      child: Column(
        children: [
          // AppBar equivalent
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _showPreview = false),
              ),
              const Expanded(
                child: Text('冒险预览',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 48), // balance the back button
            ]),
          ),
          // Scrollable content
          Expanded(
            child: CustomScrollView(slivers: slivers),
          ),
          // Fixed bottom buttons
          AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 420;
                  final saveButton = SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _saveAsPreset(config),
                      icon: const Icon(Icons.save, size: 16),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('保存为预设', style: TextStyle(fontSize: 13)),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.accent),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                    ),
                  );
                  final backButton = OutlinedButton(
                    onPressed: () => setState(() => _showPreview = false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('返回编辑'),
                    ),
                  );
                  final startButton = FilledButton.icon(
                    onPressed: _isStartingAdventure
                        ? null
                        : () {
                            if (!_guardCharacterSetup()) return;
                            _startAdventure(config);
                          },
                    icon: _isStartingAdventure
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: NarrAItorLoading.mini(size: 18),
                          )
                        : const Icon(Icons.play_arrow),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _isStartingAdventure ? '创建中...' : '进入场景',
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  );
                  if (compact) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        saveButton,
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: backButton),
                            const SizedBox(width: 12),
                            Expanded(flex: 2, child: startButton),
                          ],
                        ),
                      ],
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      saveButton,
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: backButton),
                          const SizedBox(width: 12),
                          Expanded(flex: 2, child: startButton),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// C11: 保存当前冒险配置为预设模板
  Future<void> _saveAsPreset(AdventureConfig config) async {
    final nameCtrl = TextEditingController(
        text: config.name.isNotEmpty ? '${config.name}的冒险' : '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存为预设'),
        content: TextField(
          controller: nameCtrl,
          scrollPadding: const EdgeInsets.only(bottom: 120),
          decoration: const InputDecoration(
            labelText: '预设名称',
            hintText: '给这个冒险预设起个名字',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final n = nameCtrl.text.trim();
              Navigator.pop(ctx, n.isEmpty ? '未命名冒险' : n);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    if (name == null || !mounted) return;
    final now = DateTime.now().toIso8601String();
    final wvName = _selWorldviewId != null
        ? (_worldviewPresets
                .where((w) => w['id'] == _selWorldviewId)
                .firstOrNull?['name'] as String? ??
            '')
        : '';
    final wvDesc = _worldviewDesc.isNotEmpty
        ? _worldviewDesc
        : _buildManualWorldviewText();
    final charDataJson = jsonEncode({
      'name': config.name,
      'gender': config.gender,
      'age': config.age,
      'personality': config.personality,
      'profession': config.protagonistClass,
      'background': config.protagonistBackground,
      'openingScene': config.openingScene,
      'openingOptions': config.openingOptions,
    });
    final npcDataJson =
        jsonEncode({'npcs': _npcs.map((n) => n.toJson()).toList()});
    // 内容去重检查与保存统一经模板控制器（内部含 ContentHasher 去重）。
    try {
      final saved =
          await ref.read(adventureTemplateControllerProvider).saveAsTemplate(
                id: 'tmpl_${DateTime.now().millisecondsSinceEpoch}',
                name: name,
                worldviewName: wvName,
                worldviewDesc: wvDesc,
                charDataJson: charDataJson,
                npcDataJson: npcDataJson,
                createdAt: now,
                status: 'complete',
                updatedAt: now,
              );
      if (!mounted) return;
      _showCenteredPresetMessage(saved ? '已保存为预设场景' : '已保存过相同内容，无需重复保存');
    } catch (e) {
      debugPrint('[Builder] 保存预设失败: $e');
    }
  }

  void _showCenteredPresetMessage(String message) {
    BuildContext? dialogContext;
    unawaited(showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      barrierDismissible: true,
      builder: (ctx) {
        dialogContext = ctx;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle,
                    color: AppColors.success, size: 22),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    message,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ));
    Future.delayed(const Duration(milliseconds: 1400), () {
      final ctx = dialogContext;
      if (ctx != null && ctx.mounted) {
        Navigator.of(ctx).pop();
      }
    });
  }

  Widget _buildPreviewSection(String emoji, String title, String content) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor =
        isDark ? AppColors.darkSurfaceElevated : AppColors.surfaceElevated;
    final borderColor = isDark
        ? AppColors.darkTextSecondary.withValues(alpha: 0.24)
        : Colors.grey[200]!;
    final titleColor =
        isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final bodyColor =
        isDark ? AppColors.darkTextSecondary : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: titleColor)),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              content,
              style: TextStyle(
                fontSize: 13,
                color: bodyColor,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
