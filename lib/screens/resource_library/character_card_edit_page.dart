import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;

import '../../application/resources/resource_creation_contracts.dart';
import '../../core/feedback/app_feedback.dart';
import '../../core/config/generation_limits.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/custom_attribute_editor_section.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import '../../core/widgets/form_sub_page_scaffold.dart';
import '../../core/widgets/narr_aitor_dropdown.dart';
import '../../models/custom_attribute_item.dart';
import '../../models/resource_library_mode.dart';
import '../../providers/riverpod_providers.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../features/resource_studio/presentation/pages/resource_studio_page.dart';
import '../../widgets/app_dialogs.dart';

/// 新建/编辑角色卡页面
Future<CharacterCardEditDraft?> showCharacterCardEditPage(
  BuildContext context, {
  Map<String, dynamic>? existingCard,
  String? existingId,
  String? defaultMatchingWorldviewId,
  List<Map<String, dynamic>>? worldviewPresets,
  String? activeWorldviewDescription,
  ResourceLibraryMode mode = ResourceLibraryMode.adventure,
}) {
  final isEdit =
      existingCard != null || (existingId != null && existingId.isNotEmpty);
  return showFormSubPage<CharacterCardEditDraft>(
    context: context,
    title: isEdit ? '编辑角色卡' : '新建角色卡',
    maxWidth: 760,
    builder: (ctx) => CharacterCardEditPage(
      existingCard: existingCard,
      existingId: existingId,
      defaultMatchingWorldviewId: defaultMatchingWorldviewId,
      worldviewPresets: worldviewPresets,
      activeWorldviewDescription: activeWorldviewDescription,
      mode: mode,
    ),
  );
}

class CharacterCardEditPage extends StatefulWidget {
  final Map<String, dynamic>? existingCard;
  final String? existingId;
  final String? defaultMatchingWorldviewId;
  final List<Map<String, dynamic>>? worldviewPresets;
  final String? activeWorldviewDescription;
  final ResourceLibraryMode mode;

  const CharacterCardEditPage({
    super.key,
    this.existingCard,
    this.existingId,
    this.defaultMatchingWorldviewId,
    this.worldviewPresets,
    this.activeWorldviewDescription,
    this.mode = ResourceLibraryMode.adventure,
  });

  @override
  State<CharacterCardEditPage> createState() => _CharacterCardEditPageState();
}

class _CharacterCardEditPageState extends State<CharacterCardEditPage> {
  late final bool isEdit;
  late final CharacterCardEditDraft draft;

  late final TextEditingController nameCtrl;
  late final TextEditingController ageCtrl;
  late final TextEditingController profCtrl;
  late final TextEditingController persCtrl;
  late final TextEditingController bgCtrl;
  late final TextEditingController appearCtrl;
  late final TextEditingController bodyCtrl;
  late final TextEditingController factionCtrl;
  late final TextEditingController locationCtrl;
  late final TextEditingController goalCtrl;
  late final TextEditingController motivationCtrl;
  late final TextEditingController abilitySourceCtrl;
  late final TextEditingController abilityCostCtrl;
  late final tabooCtrl = TextEditingController();
  late final relationshipCtrl = TextEditingController();
  late final customGenderCtrl = TextEditingController();
  late final aiPromptCtrl = TextEditingController();

  bool _openingAiStudio = false;
  bool isDetailedMode = true;
  int _targetTotalCharacters =
      GenerationLimits.detailedCharacterDefaultCharacters;
  late String gender;
  late bool isCustomGender;
  late List<CustomAttributeItem> customAttributes;
  late List<Map<String, dynamic>> worldviewList;
  late String matchingWorldviewId;

  List<Map<String, dynamic>> _existingCharacterCards = [];
  final Set<String> _aiSelectedAssociatedIds = {};
  String _aiRelationType = '同伴';
  late final TextEditingController _aiCustomRelationCtrl;

  @override
  void initState() {
    super.initState();
    isEdit = widget.existingCard != null ||
        (widget.existingId != null && widget.existingId!.isNotEmpty);
    draft = CharacterCardEditDraft.fromExisting(
      widget.existingCard,
      existingId: widget.existingId,
    );

    nameCtrl = TextEditingController(text: draft.name);
    ageCtrl = TextEditingController(text: draft.age);
    profCtrl = TextEditingController(text: draft.profession);
    persCtrl = TextEditingController(text: draft.personality);
    bgCtrl = TextEditingController(text: draft.description);
    appearCtrl = TextEditingController(text: draft.appearance);
    bodyCtrl = TextEditingController(text: draft.bodyDescription);
    factionCtrl = TextEditingController(text: draft.faction);
    locationCtrl = TextEditingController(text: draft.homeLocation);
    goalCtrl = TextEditingController(text: draft.publicGoal);
    motivationCtrl = TextEditingController(text: draft.hiddenMotivation);
    abilitySourceCtrl = TextEditingController(text: draft.abilitySource);
    abilityCostCtrl = TextEditingController(text: draft.abilityCost);
    tabooCtrl.text = draft.taboosText;
    relationshipCtrl.text = draft.relationshipNotes;
    customGenderCtrl.text = draft.customGender;
    _aiCustomRelationCtrl = TextEditingController();

    gender = draft.gender;
    isCustomGender = draft.isCustomGender;
    customAttributes = List.from(draft.customAttributes);
    worldviewList = widget.worldviewPresets ?? [];
    matchingWorldviewId =
        widget.existingCard?['matching_worldview_id'] as String? ??
            widget.defaultMatchingWorldviewId ??
            '';

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final crud = ProviderScope.containerOf(context, listen: false)
            .read(resourceCrudControllerProvider);
        if (widget.worldviewPresets == null) {
          final list = await crud.loadWorldviewPresets(mode: widget.mode);
          if (mounted) {
            setState(() {
              worldviewList = list;
            });
          }
        }
        final cards = await crud.loadCharacterCards(mode: widget.mode);
        if (mounted) {
          setState(() {
            _existingCharacterCards = cards
                .where((c) => c['id']?.toString() != widget.existingId)
                .toList();
          });
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    ageCtrl.dispose();
    profCtrl.dispose();
    persCtrl.dispose();
    bgCtrl.dispose();
    appearCtrl.dispose();
    bodyCtrl.dispose();
    factionCtrl.dispose();
    locationCtrl.dispose();
    goalCtrl.dispose();
    motivationCtrl.dispose();
    abilitySourceCtrl.dispose();
    abilityCostCtrl.dispose();
    tabooCtrl.dispose();
    relationshipCtrl.dispose();
    customGenderCtrl.dispose();
    aiPromptCtrl.dispose();
    _aiCustomRelationCtrl.dispose();
    super.dispose();
  }

  Future<void> _deleteCard() async {
    final crudController = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(resourceCrudControllerProvider);
    final confirm = await AppConfirmDialog.show(
      context: context,
      title: '确认删除',
      message: '确定要删除角色卡「${nameCtrl.text.trim()}」吗？',
      confirmLabel: '删除',
      isDanger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirm) return;
    final cardId = widget.existingId ?? draft.id;
    if (cardId == null || cardId.isEmpty) return;
    final result = await crudController.deleteCharacterCard(
      cardId,
      mode: widget.mode,
    );
    if (!result.success) {
      debugPrint('[CharacterCardEditPage] 删除失败: ${result.errorMessage}');
      if (mounted) {
        AppFeedback.error(context, '删除角色卡失败: ${result.errorMessage}');
      }
      return;
    }
    if (result.message != null && mounted) {
      AppFeedback.success(context, result.message!);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _saveCard() => _persistCard(closeOnSuccess: true);

  Future<bool> _persistCard({required bool closeOnSuccess}) async {
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少填写姓名')),
      );
      return false;
    }
    draft.name = name;
    draft.gender = gender;
    draft.customGender = customGenderCtrl.text.trim();
    draft.age = ageCtrl.text.trim();
    draft.profession = profCtrl.text.trim();
    draft.personality = persCtrl.text.trim();
    draft.description = bgCtrl.text.trim();
    draft.appearance = appearCtrl.text.trim();
    draft.bodyDescription = bodyCtrl.text.trim();
    draft.faction = factionCtrl.text.trim();
    draft.homeLocation = locationCtrl.text.trim();
    draft.publicGoal = goalCtrl.text.trim();
    draft.hiddenMotivation = motivationCtrl.text.trim();
    draft.abilitySource = abilitySourceCtrl.text.trim();
    draft.abilityCost = abilityCostCtrl.text.trim();
    draft.taboosText = tabooCtrl.text;
    draft.relationshipNotes = relationshipCtrl.text.trim();
    draft.worldviewId = matchingWorldviewId;
    draft.customAttributes = customAttributes;

    final result = await ProviderScope.containerOf(
      context,
      listen: false,
    ).read(resourceCrudControllerProvider).saveCharacterCardDraft(
          draft,
          mode: widget.mode,
        );
    if (!result.success) {
      final message = result.errorMessage ?? '未知错误';
      debugPrint('[CharacterCardEditPage] 保存失败: $message');
      if (mounted) {
        AppFeedback.error(context, '保存失败：$message');
      }
      return false;
    }
    if (mounted && closeOnSuccess) Navigator.pop(context, draft);
    return true;
  }

  Future<void> _openManagedAiStudio() async {
    if (_openingAiStudio) return;
    final chat =
        ProviderScope.containerOf(context, listen: false).read(chatProvider);
    if (!chat.isKeyConfigured) {
      showApiSettings(context);
      return;
    }

    if (isEdit && !await _persistCard(closeOnSuccess: false)) {
      return;
    }
    if (!mounted) return;
    final existingResourceId = widget.existingId ?? draft.id;

    final matchedWorldview = worldviewList
        .where((worldview) => worldview['id'] == matchingWorldviewId)
        .firstOrNull;
    final worldviewDescription =
        matchedWorldview?['description']?.toString().trim().isNotEmpty == true
            ? matchedWorldview!['description'].toString().trim()
            : widget.activeWorldviewDescription?.trim() ?? '';
    final selectedNames = _existingCharacterCards
        .where(
          (card) => _aiSelectedAssociatedIds.contains(card['id']?.toString()),
        )
        .map((card) => card['name']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final relation = _aiRelationType == '自定义'
        ? _aiCustomRelationCtrl.text.trim()
        : _aiRelationType;
    final request = aiPromptCtrl.text.trim().isEmpty
        ? '请设计一个富有特色与戏剧魅力的角色卡设定。'
        : aiPromptCtrl.text.trim();
    final currentName = nameCtrl.text.trim();
    final referenceLines = <String>[
      request,
      if (worldviewDescription.isNotEmpty) '世界观参考：$worldviewDescription',
      if (selectedNames.isNotEmpty)
        '关联角色：${selectedNames.join('、')}；关系：${relation.isEmpty ? '同伴' : relation}',
      if (currentName.isNotEmpty) '当前姓名：$currentName',
      if (ageCtrl.text.trim().isNotEmpty) '当前年龄：${ageCtrl.text.trim()}',
      if (profCtrl.text.trim().isNotEmpty) '当前身份：${profCtrl.text.trim()}',
      if (persCtrl.text.trim().isNotEmpty) '当前性格：${persCtrl.text.trim()}',
      if (bgCtrl.text.trim().isNotEmpty) '当前背景：${bgCtrl.text.trim()}',
      if (appearCtrl.text.trim().isNotEmpty) '当前外貌：${appearCtrl.text.trim()}',
    ];
    final targetCharacters = isDetailedMode
        ? _targetTotalCharacters
        : GenerationLimits.detailedCharacterMinimumCharacters;

    setState(() => _openingAiStudio = true);
    try {
      await AppRouter.push<void>(
        context,
        pageBuilder: (_) => ResourceStudioPage(
          creationDraft: ResourceStudioCreationDraft(
            type: ResourceType.character,
            name: currentName.isEmpty ? 'AI 角色卡' : currentName,
            referenceSource: ReferenceSource.text(
              referenceLines.join('\n'),
              label: '角色卡编辑器创建参考',
            ),
            targetCharacters: targetCharacters,
            origin: isEdit
                ? 'character-editor-regeneration'
                : 'character-editor-create',
            libraryMode: widget.mode.storageValue,
            targetResourceId: isEdit && existingResourceId != null
                ? ResourceId(existingResourceId)
                : null,
          ),
        ),
      );
      if (mounted && isEdit) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _openingAiStudio = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(children: [
              Icon(isEdit ? Icons.edit : Icons.person_add,
                  size: 20, color: AppColors.accent),
              const SizedBox(width: 8),
              const Text('角色卡信息',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 16),
            // Worldview dropdown
            NarrAItorDropdown<String>(
              value: matchingWorldviewId.isEmpty ? null : matchingWorldviewId,
              label: '契合世界观（可选）',
              options: [
                const NarrAItorDropdownOption<String>(value: null, label: '无'),
                ...worldviewList.map((wv) => NarrAItorDropdownOption<String>(
                      value: wv['id'] as String?,
                      label: wv['name'] as String? ?? '',
                    )),
              ],
              onChanged: (v) => setState(() => matchingWorldviewId = v ?? ''),
            ),
            const SizedBox(height: 10),
            // AI 辅助编写角色卡
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.28),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'AI 智能辅助编写角色卡',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: _openingAiStudio
                            ? null
                            : () => setState(
                                () => isDetailedMode = !isDetailedMode),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isDetailedMode
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.15)
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDetailedMode
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.5)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isDetailedMode
                                    ? Icons.auto_stories_rounded
                                    : Icons.flash_on_rounded,
                                size: 12,
                                color: isDetailedMode
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isDetailedMode ? '详细模式' : '简约模式',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDetailedMode
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (isDetailedMode) ...[
                    const SizedBox(height: 8),
                    Text(
                      '目标有效内容 $_targetTotalCharacters 字',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Slider(
                      value: _targetTotalCharacters.toDouble(),
                      min: GenerationLimits.detailedCharacterMinimumCharacters
                          .toDouble(),
                      max: GenerationLimits.detailedCharacterMaximumCharacters
                          .toDouble(),
                      divisions: 8,
                      label: '$_targetTotalCharacters',
                      onChanged: _openingAiStudio
                          ? null
                          : (value) => setState(
                                () => _targetTotalCharacters = value.round(),
                              ),
                    ),
                    Text(
                      '生成将在资源工作室中持续保存，可恢复并可追踪修改记录',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (_existingCharacterCards.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    AppMultiSelectDropdown<String>(
                      values: _aiSelectedAssociatedIds,
                      label: '关联已有角色（可选）',
                      hintText: '点击选择要建立关系的已有角色（留空为独立角色）',
                      emptyText: '暂无其他角色',
                      triggerHeight: 38,
                      triggerPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      direction: AppDropdownDirection.down,
                      selectedBuilder: (values) => values.isEmpty
                          ? '不关联（作为独立新角色构思）'
                          : '已关联 ${values.length} 位角色',
                      options: _existingCharacterCards.map((card) {
                        return AppDropdownOption(
                          value: card['id']?.toString() ?? '',
                          label: card['name']?.toString() ?? '未命名角色',
                        );
                      }).toList(),
                      onChanged: _openingAiStudio
                          ? null
                          : (values) => setState(() {
                                _aiSelectedAssociatedIds
                                  ..clear()
                                  ..addAll(values);
                              }),
                    ),
                    if (_aiSelectedAssociatedIds.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            '羁绊关系：',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 4),
                          AppDropdown<String>.compact(
                            value: _aiRelationType,
                            direction: AppDropdownDirection.down,
                            options: const [
                              AppDropdownOption(value: '同伴', label: '同伴 / 队友'),
                              AppDropdownOption(value: '青梅竹马', label: '青梅竹马'),
                              AppDropdownOption(
                                  value: '恋人', label: '恋人 / 命定伴侣'),
                              AppDropdownOption(
                                  value: '师徒', label: '师徒 (师承/弟子)'),
                              AppDropdownOption(
                                  value: '宿敌', label: '宿敌 / 竞争对手'),
                              AppDropdownOption(value: '亲人', label: '家族亲人'),
                              AppDropdownOption(
                                  value: '救命恩人', label: '救命恩人 / 报恩'),
                              AppDropdownOption(value: '雇佣关系', label: '雇佣关系'),
                              AppDropdownOption(
                                  value: '自定义', label: '自定义关系...'),
                            ],
                            onChanged: _openingAiStudio
                                ? null
                                : (val) {
                                    if (val != null) {
                                      setState(() => _aiRelationType = val);
                                    }
                                  },
                          ),
                          const SizedBox(width: 6),
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
                                ].map((preset) {
                                  final isSel = _aiRelationType == preset;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: ChoiceChip(
                                      label: Text(preset,
                                          style: const TextStyle(fontSize: 11)),
                                      selected: isSel,
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      onSelected: _openingAiStudio
                                          ? null
                                          : (selected) {
                                              if (selected) {
                                                setState(() =>
                                                    _aiRelationType = preset);
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
                            enabled: !_openingAiStudio,
                            style: const TextStyle(fontSize: 12),
                            decoration: const InputDecoration(
                              labelText: '自定义关系描述',
                              hintText: '例如：指腹为婚的未婚妻、异界灵魂共生者...',
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: aiPromptCtrl,
                          enabled: !_openingAiStudio,
                          decoration: const InputDecoration(
                            hintText:
                                '输入角色核心词或设定要求（如：冷傲银发女剑圣、背叛教会的流浪学者），留空则自由发挥...',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed:
                            _openingAiStudio ? null : _openManagedAiStudio,
                        icon: _openingAiStudio
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.auto_awesome, size: 16),
                        label: Text(
                          _openingAiStudio
                              ? '正在打开...'
                              : (isEdit ? 'AI 重新生成' : 'AI 填入'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameCtrl,
              scrollPadding: const EdgeInsets.only(bottom: 120),
              decoration: const InputDecoration(
                  labelText: '姓名 *',
                  border: OutlineInputBorder(),
                  isDense: true),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: NarrAItorDropdown<String>(
                  value: gender,
                  label: '性别',
                  options: ['男', '女', '其他']
                      .map((g) => NarrAItorDropdownOption(value: g, label: g))
                      .toList(),
                  onChanged: (v) => setState(() {
                    gender = v ?? '男';
                    isCustomGender = gender == '其他';
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: ageCtrl,
                  scrollPadding: const EdgeInsets.only(bottom: 120),
                  decoration: const InputDecoration(
                      labelText: '年龄',
                      border: OutlineInputBorder(),
                      isDense: true),
                  keyboardType: TextInputType.number,
                ),
              ),
            ]),
            if (isCustomGender) ...[
              const SizedBox(height: 10),
              TextField(
                controller: customGenderCtrl,
                decoration: const InputDecoration(
                    labelText: '自定义性别',
                    border: OutlineInputBorder(),
                    isDense: true),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: profCtrl,
              scrollPadding: const EdgeInsets.only(bottom: 120),
              decoration: const InputDecoration(
                  labelText: '职业/身份',
                  border: OutlineInputBorder(),
                  isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: persCtrl,
              scrollPadding: const EdgeInsets.only(bottom: 120),
              decoration: const InputDecoration(
                  labelText: '性格', border: OutlineInputBorder(), isDense: true),
              maxLines: 3,
              minLines: 2,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: bgCtrl,
              scrollPadding: const EdgeInsets.only(bottom: 120),
              decoration: const InputDecoration(
                  labelText: '背景故事',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                  isDense: true),
              maxLines: 6,
              minLines: 3,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: appearCtrl,
              scrollPadding: const EdgeInsets.only(bottom: 120),
              decoration: const InputDecoration(
                  labelText: '外貌描述',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                  isDense: true),
              maxLines: 3,
              minLines: 2,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: bodyCtrl,
              scrollPadding: const EdgeInsets.only(bottom: 120),
              decoration: const InputDecoration(
                  labelText: '身材体态与生理特征',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                  isDense: true),
              maxLines: 2,
              minLines: 1,
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child:
                  Text('世界内设定', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            TextField(
                controller: factionCtrl,
                decoration: const InputDecoration(
                    labelText: '所属势力',
                    border: OutlineInputBorder(),
                    isDense: true)),
            const SizedBox(height: 10),
            TextField(
                controller: locationCtrl,
                decoration: const InputDecoration(
                    labelText: '活动地点 / 家乡',
                    border: OutlineInputBorder(),
                    isDense: true)),
            const SizedBox(height: 10),
            TextField(
                controller: goalCtrl,
                decoration: const InputDecoration(
                    labelText: '公开目标',
                    border: OutlineInputBorder(),
                    isDense: true)),
            const SizedBox(height: 10),
            TextField(
                controller: motivationCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: '隐藏动机（供叙事使用）',
                    border: OutlineInputBorder(),
                    isDense: true)),
            const SizedBox(height: 10),
            TextField(
                controller: abilitySourceCtrl,
                decoration: const InputDecoration(
                    labelText: '能力来源',
                    border: OutlineInputBorder(),
                    isDense: true)),
            const SizedBox(height: 10),
            TextField(
                controller: abilityCostCtrl,
                decoration: const InputDecoration(
                    labelText: '能力代价 / 限制',
                    border: OutlineInputBorder(),
                    isDense: true)),
            const SizedBox(height: 10),
            TextField(
                controller: tabooCtrl,
                decoration: const InputDecoration(
                    labelText: '禁忌（用“、”分隔）',
                    border: OutlineInputBorder(),
                    isDense: true)),
            const SizedBox(height: 10),
            TextField(
                controller: relationshipCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: '关系网络备注',
                    border: OutlineInputBorder(),
                    isDense: true)),
            const SizedBox(height: 16),
            CustomAttributeEditorSection(
              initialItems: customAttributes,
              onChanged: (items) {
                customAttributes = items;
              },
            ),
            const SizedBox(height: 20),
            // Bottom buttons
            Row(children: [
              if (isEdit)
                TextButton(
                  onPressed: _deleteCard,
                  child: const Text('删除',
                      style: TextStyle(color: AppColors.error)),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saveCard,
                child: Text(isEdit ? '保存' : '创建'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
